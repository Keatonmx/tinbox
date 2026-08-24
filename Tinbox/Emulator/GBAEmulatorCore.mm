//
//  GBAEmulatorCore.mm
//  Tinbox
//
//  Objective-C++ bridge over libmgba. Written against the mGBA headers in
//  Vendor/mgba-dist/include (see Scripts/build-mgba.sh). `mgba/flags.h` MUST be
//  the first mGBA include: it carries the ENABLE_*/USE_* defines the library was
//  compiled with, and `struct mCore`'s layout depends on them.
//
//  One bridge object serves both platforms: `loadROMAtURL:` asks mGBA which core
//  handles the file (`mCoreFind`) and rebuilds the core only when the platform
//  changes (GBA ↔ GB/GBC).
//

#import "GBAEmulatorCore.h"

#include <mgba/flags.h>
#include <mgba/core/core.h>
#include <mgba/core/config.h>
#include <mgba/core/cheats.h>
#include <mgba/core/interface.h>
#include <mgba/core/rewind.h>
#include <mgba/core/serialize.h>
#include <mgba/core/version.h>
#include <mgba/gba/core.h>
#include <mgba/gba/interface.h>
#include <mgba/gb/core.h>
#include <mgba/internal/gba/gba.h>
#include <mgba/internal/gba/cheats.h>
#include <mgba/internal/gba/input.h>
#include <mgba/internal/gba/memory.h>
#include <mgba/internal/gba/savedata.h>
#include <mgba/internal/gb/gb.h>
#include <mgba/internal/gb/cheats.h>
#include <mgba/internal/gb/memory.h>
#include <mgba-util/audio-buffer.h>
#include <mgba-util/image.h>
#include <mgba-util/vfs.h>

#include <fcntl.h>
#include <string.h>

#pragma mark - Peripheral glue structs

// mGBA peripheral callbacks receive the peripheral struct itself; each one is
// wrapped so the callback can find the owning GBAEmulatorCore / its state.

struct TinboxRumble {
    struct mRumbleIntegrator integrator; // must be first (cast back from mRumble*)
    void* __unsafe_unretained owner;
};

struct TinboxRotation {
    struct mRotationSource source;       // must be first
    int32_t tiltX;
    int32_t tiltY;
    int32_t gyroZ;
};

struct TinboxLuminance {
    struct GBALuminanceSource source;    // must be first
    uint8_t value;
};

// Full-scale tilt value used by mGBA's own frontends (SensorView: 0xE0 << 21).
static const float kTiltFullScale = 469762048.0f;
// gpio.c `_gyroReadPins` does `(sample >> 21) + 0x700`, so ±2^31 maps to ±0x400.
static const float kGyroFullScale = 2.0e9f;

static void _rotationSample(struct mRotationSource* s) { (void) s; }
static int32_t _rotationTiltX(struct mRotationSource* s) { return ((struct TinboxRotation*) s)->tiltX; }
static int32_t _rotationTiltY(struct mRotationSource* s) { return ((struct TinboxRotation*) s)->tiltY; }
static int32_t _rotationGyroZ(struct mRotationSource* s) { return ((struct TinboxRotation*) s)->gyroZ; }

static void _luxSample(struct GBALuminanceSource* s) { (void) s; }
static uint8_t _luxRead(struct GBALuminanceSource* s) { return ((struct TinboxLuminance*) s)->value; }

// Real-time clock fed to the cores; `offset` shifts it forward ("time travel"
// for berry growth and day/night events). 0 == the phone's real clock.
struct TinboxRTC {
    struct mRTCSource source;    // must be first
    int64_t offset;
};
static void _rtcSample(struct mRTCSource* s) { (void) s; }
static time_t _rtcUnixTime(struct mRTCSource* s) {
    return time(0) + (time_t) ((struct TinboxRTC*) s)->offset;
}

static const int kSaveFlags = SAVESTATE_SCREENSHOT | SAVESTATE_SAVEDATA | SAVESTATE_RTC | SAVESTATE_METADATA;
static const int kLoadFlags = SAVESTATE_SCREENSHOT | SAVESTATE_SAVEDATA | SAVESTATE_RTC;

/// Platform of a ROM file (or of the first recognised ROM inside a .zip),
/// without allocating a core — mirrors mCoreFind's archive walk.
static enum mPlatform _platformForPath(const char* path) {
    enum mPlatform platform = mPLATFORM_NONE;
    struct VDir* archive = VDirOpenArchive(path);
    if (archive) {
        struct VDirEntry* dirent = archive->listNext(archive);
        while (dirent && platform == mPLATFORM_NONE) {
            struct VFile* vf = archive->openFile(archive, dirent->name(dirent), O_RDONLY);
            if (vf) {
                platform = mCoreIsCompatible(vf);
                vf->close(vf);
            }
            dirent = archive->listNext(archive);
        }
        archive->close(archive);
        return platform;
    }
    struct VFile* vf = VFileOpen(path, O_RDONLY);
    if (!vf) return mPLATFORM_NONE;
    platform = mCoreIsCompatible(vf);
    vf->close(vf);
    return platform;
}

#pragma mark - GBAEmulatorCore

@interface GBAEmulatorCore () {
    struct mCore* _core;
    TinboxPlatform _platform;
    mColor* _videoBuffer;
    unsigned _width;
    unsigned _height;

    NSURL* _saveDirectory;
    NSURL* _stateDirectory;
    NSURL* _screenshotDirectory;

    struct mCoreCallbacks _callbacks;
    struct TinboxRumble _rumble;
    struct TinboxRotation _rotation;
    struct TinboxLuminance _lux;
    struct TinboxRTC _rtc;
    int64_t _rtcOffset;

    struct mCoreRewindContext _rewind;
    BOOL _rewindEnabled;
    NSUInteger _rewindInterval;
    NSUInteger _rewindEntries;
    NSUInteger _rewindFrameCounter;
    // Remembered so a new core gets the same rewind setup.
    BOOL _rewindWanted;
    NSUInteger _rewindSeconds;

    NSString* _biosPath;
    NSString* _romPath;
    NSInteger _luminanceLevel;
    NSInteger _volume;
    BOOL _muted;
}
- (void)applyBIOSConfiguration;
- (BOOL)setUpCore:(struct mCore*)core;
- (void)tearDownCore;
@end

static void _savedataUpdated(void* context) {
    GBAEmulatorCore* core = (__bridge GBAEmulatorCore*) context;
    id<GBAEmulatorCoreDelegate> delegate = core.delegate;
    if ([delegate respondsToSelector:@selector(emulatorCoreDidUpdateSaveData:)]) {
        [delegate emulatorCoreDidUpdateSaveData:core];
    }
}

static void _rumbleSet(struct mRumbleIntegrator* integrator, float value) {
    struct TinboxRumble* rumble = (struct TinboxRumble*) integrator;
    GBAEmulatorCore* core = (__bridge GBAEmulatorCore*) rumble->owner;
    id<GBAEmulatorCoreDelegate> delegate = core.delegate;
    if ([delegate respondsToSelector:@selector(emulatorCore:rumbleIntensity:)]) {
        [delegate emulatorCore:core rumbleIntensity:value];
    }
}

@implementation GBAEmulatorCore

+ (NSString*)coreVersion {
    return [NSString stringWithFormat:@"mGBA %s (%s)", projectVersion, gitCommitShort];
}

- (instancetype)initWithSaveDirectory:(NSURL*)saveDirectory
                       stateDirectory:(NSURL*)stateDirectory
                  screenshotDirectory:(NSURL*)screenshotDirectory {
    self = [super init];
    if (!self) {
        return nil;
    }
    _saveDirectory = saveDirectory;
    _stateDirectory = stateDirectory;
    _screenshotDirectory = screenshotDirectory;
    _platform = TinboxPlatformNone;
    _width = 240;
    _height = 160;
    _volume = 100;
    _rewindInterval = 2;
    _luminanceLevel = 0;
    memset(&_rewind, 0, sizeof(_rewind));

    // A GBA core from the start so callers have a valid video buffer and
    // sample rate before the first ROM; loadROM swaps it if a GB ROM comes in.
    if (![self setUpCore:GBACoreCreate()]) {
        return nil;
    }
    return self;
}

- (void)dealloc {
    [self tearDownCore];
}

#pragma mark - Core lifecycle

/// Takes ownership of an uninitialised core returned by mCoreFind / *CoreCreate.
- (BOOL)setUpCore:(struct mCore*)core {
    if (!core) return NO;
    [self tearDownCore];
    _core = core;
    _core->init(_core);
    _platform = _core->platform(_core) == mPLATFORM_GB ? TinboxPlatformGB : TinboxPlatformGBA;

    // Configuration. Paths are absolute; mGBA opens/creates the directories in
    // mDirectorySetMapOptions, which is what makes battery saves land in
    // Documents/Saves automatically.
    mCoreInitConfig(_core, "tinbox");
    mCoreConfigSetValue(&_core->config, "savegamePath", _saveDirectory.fileSystemRepresentation);
    mCoreConfigSetValue(&_core->config, "savestatePath", _stateDirectory.fileSystemRepresentation);
    mCoreConfigSetValue(&_core->config, "screenshotPath", _screenshotDirectory.fileSystemRepresentation);
    mCoreConfigSetIntValue(&_core->config, "useBios", 0);
    mCoreConfigSetIntValue(&_core->config, "skipBios", 0);
    mCoreConfigSetIntValue(&_core->config, "volume", (int) (_volume * 0x100 / 100));   // 0x100 == GBA_AUDIO_VOLUME_MAX; unset == silent
    mCoreConfigSetIntValue(&_core->config, "mute", _muted ? 1 : 0);
    mCoreConfigSetIntValue(&_core->config, "frameskip", 0);
    mCoreConfigSetUIntValue(&_core->config, "audioBuffers", 16384);   // ≥ one frame even at 262144 Hz
    mCoreConfigSetIntValue(&_core->config, "cheatAutosave", 0);
    mCoreConfigSetIntValue(&_core->config, "cheatAutoload", 0);
    mCoreConfigSetValue(&_core->config, "idleOptimization", "remove");
    if (_platform == TinboxPlatformGB) {
        // Super Game Boy borders off: the view is sized to 160×144.
        mCoreConfigSetIntValue(&_core->config, "sgb.borders", 0);
    }
    mCoreLoadForeignConfig(_core, &_core->config);

    // Video: one RGBA8 buffer, stride == width.
    _core->baseVideoSize(_core, &_width, &_height);
    _videoBuffer = (mColor*) calloc((size_t) _width * _height, sizeof(mColor));
    _core->setVideoBuffer(_core, _videoBuffer, _width);

    // Callbacks.
    memset(&_callbacks, 0, sizeof(_callbacks));
    _callbacks.context = (__bridge void*) self;
    _callbacks.savedataUpdated = _savedataUpdated;
    _core->addCoreCallbacks(_core, &_callbacks);

    // Peripherals (rumble + rotation exist on both platforms; luminance is GBA-only).
    memset(&_rumble, 0, sizeof(_rumble));
    mRumbleIntegratorInit(&_rumble.integrator);
    _rumble.integrator.setRumble = _rumbleSet;
    _rumble.owner = (__bridge void*) self;
    _core->setPeripheral(_core, mPERIPH_RUMBLE, &_rumble.integrator.d);

    memset(&_rotation, 0, sizeof(_rotation));
    _rotation.source.sample = _rotationSample;
    _rotation.source.readTiltX = _rotationTiltX;
    _rotation.source.readTiltY = _rotationTiltY;
    _rotation.source.readGyroZ = _rotationGyroZ;
    _core->setPeripheral(_core, mPERIPH_ROTATION, &_rotation.source);

    memset(&_rtc, 0, sizeof(_rtc));
    _rtc.source.sample = _rtcSample;
    _rtc.source.unixTime = _rtcUnixTime;
    _rtc.offset = _rtcOffset;
    _core->setPeripheral(_core, mPERIPH_RTC, &_rtc.source);

    if (_platform == TinboxPlatformGBA) {
        memset(&_lux, 0, sizeof(_lux));
        _lux.source.sample = _luxSample;
        _lux.source.readLuminance = _luxRead;
        _core->setPeripheral(_core, mPERIPH_GBA_LUMINANCE, &_lux.source);
        [self applyLuminanceLevel:_luminanceLevel];
    }

    // Rewind history is tied to a core's state size; rebuild it for this core.
    memset(&_rewind, 0, sizeof(_rewind));
    _rewindEnabled = NO;
    if (_rewindWanted) {
        [self setRewindEnabled:YES seconds:_rewindSeconds frameInterval:_rewindInterval];
    }
    return YES;
}

- (void)tearDownCore {
    if (!_core) return;
    if (_rewindEnabled) {
        mCoreRewindContextDeinit(&_rewind);
        memset(&_rewind, 0, sizeof(_rewind));
        _rewindEnabled = NO;
    }
    [self unloadROM];
    _core->removeCoreCallbacks(_core, &_callbacks);
    mCoreConfigDeinit(&_core->config);
    _core->deinit(_core);
    _core = NULL;
    free(_videoBuffer);
    _videoBuffer = NULL;
    _platform = TinboxPlatformNone;
}

#pragma mark - Video

- (NSUInteger)videoWidth { return _width; }
- (NSUInteger)videoHeight { return _height; }
- (const uint32_t*)videoBuffer { return (const uint32_t*) _videoBuffer; }
- (NSUInteger)videoBufferByteLength { return (NSUInteger) _width * _height * sizeof(mColor); }

- (NSData*)copyFramebuffer {
    return [NSData dataWithBytes:_videoBuffer length:self.videoBufferByteLength];
}

#pragma mark - ROM

- (TinboxPlatform)platform {
    return _platform;
}

- (BOOL)isROMLoaded {
    return _romPath != nil;
}

- (NSString*)gameTitle {
    if (!_romPath) return @"";
    struct mGameInfo info;
    memset(&info, 0, sizeof(info));
    _core->getGameInfo(_core, &info);
    NSString* title = [[NSString alloc] initWithBytes:info.title
                                               length:strnlen(info.title, sizeof(info.title))
                                             encoding:NSISOLatin1StringEncoding];
    return title ?: @"";
}

- (NSString*)gameCode {
    if (!_romPath) return @"";
    struct mGameInfo info;
    memset(&info, 0, sizeof(info));
    _core->getGameInfo(_core, &info);
    NSString* code = [[NSString alloc] initWithBytes:info.code
                                              length:strnlen(info.code, sizeof(info.code))
                                            encoding:NSISOLatin1StringEncoding];
    return code ?: @"";
}

- (TinboxCartHardware)cartridgeHardware {
    if (!_romPath) return TinboxCartHardwareNone;
    TinboxCartHardware hw = TinboxCartHardwareNone;
    if (_platform == TinboxPlatformGBA) {
        struct GBA* gba = (struct GBA*) _core->board;
        uint32_t devices = gba->memory.hw.devices;
        if (devices & HW_RTC)          hw |= TinboxCartHardwareRTC;
        if (devices & HW_RUMBLE)       hw |= TinboxCartHardwareRumble;
        if (devices & HW_LIGHT_SENSOR) hw |= TinboxCartHardwareSolar;
        if (devices & HW_GYRO)         hw |= TinboxCartHardwareGyro;
        if (devices & HW_TILT)         hw |= TinboxCartHardwareTilt;
    } else {
        struct GB* gb = (struct GB*) _core->board;
        switch (gb->memory.mbcType) {
            case GB_MBC5_RUMBLE: hw |= TinboxCartHardwareRumble; break;
            case GB_MBC7:        hw |= TinboxCartHardwareTilt;   break;
            case GB_MBC3_RTC:    hw |= TinboxCartHardwareRTC;    break;
            default: break;
        }
    }
    return hw;
}

- (BOOL)loadROMAtURL:(NSURL*)romURL error:(NSError**)error {
    [self unloadROM];

    // Which platform is this file? (Looks inside .zip archives too.)
    enum mPlatform detected = _platformForPath(romURL.fileSystemRepresentation);
    if (detected == mPLATFORM_NONE) {
        if (error) {
            *error = [NSError errorWithDomain:@"Tinbox.GBAEmulatorCore"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Not a Game Boy / Game Boy Advance ROM."}];
        }
        return NO;
    }
    TinboxPlatform wanted = detected == mPLATFORM_GB ? TinboxPlatformGB : TinboxPlatformGBA;
    if (wanted != _platform || !_core) {
        if (![self setUpCore:mCoreCreate(detected)]) {
            if (error) {
                *error = [NSError errorWithDomain:@"Tinbox.GBAEmulatorCore" code:2
                                         userInfo:@{NSLocalizedDescriptionKey: @"Couldn't start the emulator core."}];
            }
            return NO;
        }
    }

    // mCoreLoadFile resolves archives (.zip) through mDirectorySetOpenPath and
    // validates the payload with core->isROM.
    if (!mCoreLoadFile(_core, romURL.fileSystemRepresentation)) {
        if (error) {
            *error = [NSError errorWithDomain:@"Tinbox.GBAEmulatorCore"
                                         code:3
                                     userInfo:@{NSLocalizedDescriptionKey: @"mGBA could not load this ROM."}];
        }
        return NO;
    }
    _romPath = romURL.path;

    // Attach <rom>.sav from the configured save directory (created if missing).
    mCoreAutoloadSave(_core);

    [self applyBIOSConfiguration];
    _core->reset(_core);
    return YES;
}

- (void)unloadROM {
    if (!_romPath || !_core) return;
    [self removeAllCheats];
    [self flushSaveData];
    _core->unloadROM(_core);
    _romPath = nil;
    if (_rewindEnabled) {
        // Drop history that belongs to the previous game.
        mCoreRewindContextDeinit(&_rewind);
        memset(&_rewind, 0, sizeof(_rewind));
        mCoreRewindContextInit(&_rewind, _rewindEntries, false);
        _rewindFrameCounter = 0;
    }
}

- (BOOL)applyPatchAtURL:(NSURL*)patchURL {
    if (!_romPath) return NO;
    struct VFile* vf = VFileOpen(patchURL.fileSystemRepresentation, O_RDONLY);
    if (!vf) return NO;
    // loadPatch applies IPS/UPS/BPS in memory; the ROM on disk is untouched.
    BOOL ok = _core->loadPatch(_core, vf);
    vf->close(vf);
    if (ok) {
        _core->reset(_core);
    }
    return ok;
}

- (NSData*)copyROMData {
    if (!_romPath) return nil;
    if (_platform == TinboxPlatformGBA) {
        struct GBA* gba = (struct GBA*) _core->board;
        if (!gba->memory.rom || !gba->memory.romSize) return nil;
        return [NSData dataWithBytes:gba->memory.rom length:gba->memory.romSize];
    }
    struct GB* gb = (struct GB*) _core->board;
    if (!gb->memory.rom || !gb->memory.romSize) return nil;
    return [NSData dataWithBytes:gb->memory.rom length:gb->memory.romSize];
}

#pragma mark - BIOS

- (BOOL)usesBIOSFile {
    return _biosPath != nil;
}

- (BOOL)setBIOSFileURL:(NSURL*)biosURL {
    if (!biosURL) {
        _biosPath = nil;
        [self applyBIOSConfiguration];
        return YES;
    }
    struct VFile* vf = VFileOpen(biosURL.fileSystemRepresentation, O_RDONLY);
    if (!vf) return NO;
    BOOL valid = GBAIsBIOS(vf);
    vf->close(vf);
    if (!valid) return NO;

    _biosPath = biosURL.path;
    [self applyBIOSConfiguration];
    // Deliberately no reset here: a running game keeps running; the BIOS is
    // picked up by GBA reset (opts.useBios/opts.bios) on the next ROM load.
    return YES;
}

- (BOOL)loadBIOSNow {
    if (!_romPath || !_biosPath || _platform != TinboxPlatformGBA) return NO;
    struct VFile* biosVF = VFileOpen(_biosPath.fileSystemRepresentation, O_RDONLY);
    if (!biosVF) return NO;
    // core->loadBIOS validates (GBAIsBIOS) and takes ownership on success.
    if (!_core->loadBIOS(_core, biosVF, 0)) {
        biosVF->close(biosVF);
        return NO;
    }
    _core->reset(_core);
    return YES;
}

- (void)applyBIOSConfiguration {
    if (!_core) return;
    // The BIOS file is a GBA BIOS; GB boots without one.
    if (_biosPath && _platform == TinboxPlatformGBA) {
        mCoreConfigSetValue(&_core->config, "bios", _biosPath.fileSystemRepresentation);
        mCoreConfigSetIntValue(&_core->config, "useBios", 1);
    } else {
        mCoreConfigSetValue(&_core->config, "bios", NULL);
        mCoreConfigSetIntValue(&_core->config, "useBios", 0);
    }
    mCoreLoadForeignConfig(_core, &_core->config);
}

- (void)reset {
    if (_romPath) {
        _core->reset(_core);
    }
}

#pragma mark - Execution

- (void)runFrame {
    if (!_romPath) return;
    _core->runFrame(_core);
    if (_rewindEnabled) {
        if (++_rewindFrameCounter >= _rewindInterval) {
            _rewindFrameCounter = 0;
            mCoreRewindAppend(&_rewind, _core);
        }
    }
}

- (uint32_t)frameCounter {
    return _romPath ? _core->frameCounter(_core) : 0;
}

- (void)setKeys:(GBAKeyMask)keys {
    // GBA and GB share bit positions for A/B/Select/Start/Right/Left/Up/Down;
    // L/R are GBA-only and ignored by the GB core.
    _core->setKeys(_core, keys);
}

- (GBAKeyMask)keys {
    return (GBAKeyMask) _core->getKeys(_core);
}

#pragma mark - Audio

- (NSUInteger)audioSampleRate {
    return _core->audioSampleRate(_core);
}

- (NSUInteger)availableAudioFrames {
    struct mAudioBuffer* buffer = _core->getAudioBuffer(_core);
    return buffer ? mAudioBufferAvailable(buffer) : 0;
}

- (NSUInteger)readAudioFrames:(int16_t*)out count:(NSUInteger)frames {
    struct mAudioBuffer* buffer = _core->getAudioBuffer(_core);
    if (!buffer) return 0;
    return mAudioBufferRead(buffer, out, frames);
}

- (void)clearAudio {
    struct mAudioBuffer* buffer = _core->getAudioBuffer(_core);
    if (buffer) mAudioBufferClear(buffer);
}

- (void)setAudioBufferFrames:(NSUInteger)frames {
    _core->setAudioBufferSize(_core, frames);
}

- (void)setVolume:(NSInteger)volume {
    _volume = MAX((NSInteger) 0, MIN((NSInteger) 100, volume));
    mCoreConfigSetIntValue(&_core->config, "volume", (int) (_volume * 0x100 / 100));
    _core->reloadConfigOption(_core, "volume", &_core->config);
}

- (void)setMuted:(BOOL)muted {
    _muted = muted;
    mCoreConfigSetIntValue(&_core->config, "mute", muted ? 1 : 0);
    _core->reloadConfigOption(_core, "mute", &_core->config);
}

#pragma mark - Save states

- (BOOL)saveStateToURL:(NSURL*)url {
    if (!_romPath) return NO;
    struct VFile* vf = VFileOpen(url.fileSystemRepresentation, O_CREAT | O_TRUNC | O_RDWR);
    if (!vf) return NO;
    BOOL ok = mCoreSaveStateNamed(_core, vf, kSaveFlags);
    vf->close(vf);
    return ok;
}

- (BOOL)loadStateFromURL:(NSURL*)url {
    if (!_romPath) return NO;
    struct VFile* vf = VFileOpen(url.fileSystemRepresentation, O_RDONLY);
    if (!vf) return NO;
    BOOL ok = mCoreLoadStateNamed(_core, vf, kLoadFlags);
    vf->close(vf);
    if (ok) {
        [self clearAudio];
    }
    return ok;
}

- (NSData*)serializeState {
    if (!_romPath) return nil;
    struct VFile* vf = VFileMemChunk(NULL, 0);
    if (!vf) return nil;
    NSData* data = nil;
    if (mCoreSaveStateNamed(_core, vf, kSaveFlags)) {
        ssize_t size = vf->size(vf);
        void* mapped = vf->map(vf, (size_t) size, MAP_READ);
        if (mapped) {
            data = [NSData dataWithBytes:mapped length:(NSUInteger) size];
            vf->unmap(vf, mapped, (size_t) size);
        }
    }
    vf->close(vf);
    return data;
}

- (BOOL)deserializeState:(NSData*)data {
    if (!_romPath || data.length == 0) return NO;
    struct VFile* vf = VFileMemChunk(data.bytes, data.length);
    if (!vf) return NO;
    BOOL ok = mCoreLoadStateNamed(_core, vf, kLoadFlags);
    vf->close(vf);
    if (ok) {
        [self clearAudio];
    }
    return ok;
}

- (void)flushSaveData {
    if (!_romPath) return;
    if (_platform == TinboxPlatformGBA) {
        struct GBA* gba = (struct GBA*) _core->board;
        struct GBASavedata* savedata = &gba->memory.savedata;
        if (!savedata->vf || !savedata->data) return;
        if (savedata->maskWriteback) {
            GBASavedataUnmask(savedata);
        }
        if (savedata->mapMode & MAP_WRITE) {
            savedata->vf->sync(savedata->vf, savedata->data, GBASavedataSize(savedata));
        }
    } else {
        struct GB* gb = (struct GB*) _core->board;
        if (!gb->sramVf || !gb->memory.sram) return;
        if (gb->sramMaskWriteback) {
            GBSavedataUnmask(gb);
        }
        if (gb->sramVf == gb->sramRealVf) {
            gb->sramVf->sync(gb->sramVf, gb->memory.sram, gb->sramSize);
        }
    }
}

#pragma mark - Rewind

- (BOOL)isRewindEnabled {
    return _rewindEnabled;
}

- (void)setRewindEnabled:(BOOL)enabled seconds:(NSUInteger)seconds frameInterval:(NSUInteger)interval {
    _rewindWanted = enabled && seconds > 0;
    _rewindSeconds = seconds;
    NSUInteger wantedInterval = MAX((NSUInteger) 1, interval);
    NSUInteger wantedEntries = MAX((NSUInteger) 2, (seconds * 60) / wantedInterval);
    if (enabled && _rewindEnabled && wantedInterval == _rewindInterval && wantedEntries == _rewindEntries) {
        return; // unchanged — keep the history
    }
    if (!enabled && !_rewindEnabled) {
        return;
    }
    if (_rewindEnabled) {
        mCoreRewindContextDeinit(&_rewind);
        memset(&_rewind, 0, sizeof(_rewind));
        _rewindEnabled = NO;
    }
    if (!enabled || seconds == 0 || !_core) {
        return;
    }
    _rewindInterval = wantedInterval;
    // GBA runs at ~59.73 fps; one delta-compressed snapshot every `interval` frames.
    _rewindEntries = wantedEntries;
    mCoreRewindContextInit(&_rewind, _rewindEntries, false);
    _rewindFrameCounter = 0;
    _rewindEnabled = YES;
}

- (BOOL)rewindFrames:(NSUInteger)frames {
    if (!_rewindEnabled || !_romPath) return NO;
    unsigned steps = (unsigned) MAX((NSUInteger) 1, frames / _rewindInterval);
    BOOL ok = mCoreRewindRestore(&_rewind, _core, steps);
    if (ok) {
        [self clearAudio];
    }
    return ok;
}

#pragma mark - Cheats

static struct mCheatDevice* _cheatDevice(struct mCore* core) {
    struct mCheatDevice* device = core->cheatDevice(core);
    if (device) {
        device->autosave = false;
    }
    return device;
}

+ (NSArray<NSString*>*)normalizedLinesForCode:(NSString*)code {
    NSMutableArray<NSString*>* lines = [NSMutableArray array];
    NSCharacterSet* ws = NSCharacterSet.whitespaceCharacterSet;
    for (NSString* raw in [code componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString* line = [[raw stringByTrimmingCharactersInSet:ws] uppercaseString];
        if (line.length == 0) continue;
        // Accept "XXXXXXXXYYYYYYYY", "XXXXXXXX YYYYYYYY" and CodeBreaker "XXXXXXXX YYYY".
        NSString* compact = [[line componentsSeparatedByCharactersInSet:ws] componentsJoinedByString:@""];
        if (compact.length == 16 || compact.length == 12) {
            line = [NSString stringWithFormat:@"%@ %@", [compact substringToIndex:8], [compact substringFromIndex:8]];
        }
        [lines addObject:line];
    }
    return lines;
}

+ (BOOL)validateCheatCode:(NSString*)code type:(GBACheatCodeType)type {
    NSArray<NSString*>* lines = [self normalizedLinesForCode:code];
    if (lines.count == 0) return NO;
    NSRegularExpression* gs = [NSRegularExpression regularExpressionWithPattern:@"^[0-9A-F]{8} [0-9A-F]{8}$" options:0 error:NULL];
    NSRegularExpression* cb = [NSRegularExpression regularExpressionWithPattern:@"^[0-9A-F]{8} [0-9A-F]{4}$" options:0 error:NULL];
    // Game Boy GameShark (8 hex) and Game Genie (XXX-XXX / XXX-XXX-XXX) codes.
    NSRegularExpression* gbgs = [NSRegularExpression regularExpressionWithPattern:@"^[0-9A-F]{8}$" options:0 error:NULL];
    NSRegularExpression* gg = [NSRegularExpression regularExpressionWithPattern:@"^[0-9A-F]{3}-[0-9A-F]{3}(-[0-9A-F]{3})?$" options:0 error:NULL];
    for (NSString* line in lines) {
        NSRange r = NSMakeRange(0, line.length);
        BOOL isGS = [gs numberOfMatchesInString:line options:0 range:r] == 1;
        BOOL isCB = [cb numberOfMatchesInString:line options:0 range:r] == 1;
        BOOL isGB = [gbgs numberOfMatchesInString:line options:0 range:r] == 1
                 || [gg numberOfMatchesInString:line options:0 range:r] == 1;
        switch (type) {
            case GBACheatCodeTypeCodeBreaker:
                if (!isCB) return NO;
                break;
            case GBACheatCodeTypeGameShark:
            case GBACheatCodeTypeActionReplay:
                if (!isGS && !isGB) return NO;
                break;
            case GBACheatCodeTypeAutodetect:
                if (!isGS && !isCB && !isGB) return NO;
                break;
        }
    }
    return YES;
}

- (NSUInteger)setCheats:(NSArray<NSDictionary<NSString*, id>*>*)cheats {
    [self removeAllCheats];
    if (!_romPath) return 0;
    struct mCheatDevice* device = _cheatDevice(_core);
    if (!device) return 0;

    NSUInteger installed = 0;
    for (NSDictionary* entry in cheats) {
        NSString* name = entry[@"name"] ?: @"Cheat";
        NSString* code = entry[@"code"] ?: @"";
        GBACheatCodeType type = (GBACheatCodeType) [entry[@"type"] integerValue];
        BOOL enabled = [entry[@"enabled"] boolValue];
        // The numeric types are GBA's; the GB core auto-detects its own formats.
        int coreType = _platform == TinboxPlatformGBA ? (int) type : (int) GB_CHEAT_AUTODETECT;

        struct mCheatSet* set = device->createSet(device, name.UTF8String);
        BOOL parsedAny = NO;
        for (NSString* line in [GBAEmulatorCore normalizedLinesForCode:code]) {
            if (mCheatAddLine(set, line.UTF8String, coreType)) {
                parsedAny = YES;
            }
        }
        // Keep the slot even if parsing failed so Swift-side indices stay aligned.
        set->enabled = parsedAny && enabled;
        mCheatAddSet(device, set);
        mCheatRefresh(device, set);
        if (parsedAny) installed++;
    }
    return installed;
}

- (void)setCheatAtIndex:(NSUInteger)index enabled:(BOOL)enabled {
    if (!_romPath) return;
    struct mCheatDevice* device = _cheatDevice(_core);
    if (!device || index >= mCheatSetsSize(&device->cheats)) return;
    struct mCheatSet* set = *mCheatSetsGetPointer(&device->cheats, index);
    set->enabled = enabled;
    mCheatRefresh(device, set);
}

- (void)removeAllCheats {
    if (!_romPath) return;
    struct mCheatDevice* device = _cheatDevice(_core);
    if (!device) return;
    while (mCheatSetsSize(&device->cheats) > 0) {
        struct mCheatSet* set = *mCheatSetsGetPointer(&device->cheats, 0);
        mCheatRemoveSet(device, set);   // unpatches ROM / detaches hooks
        mCheatSetDeinit(set);           // frees the set
    }
}

#pragma mark - Archives

+ (NSUInteger)extractZipAtURL:(NSURL*)zipURL toDirectory:(NSURL*)directory {
    struct VDir* dir = VDirOpenArchive(zipURL.fileSystemRepresentation);
    if (!dir) return 0;
    NSFileManager* fm = NSFileManager.defaultManager;
    NSUInteger written = 0;
    struct VDirEntry* entry;
    while ((entry = dir->listNext(dir))) {
        const char* cname = entry->name(entry);
        if (!cname) continue;
        NSString* name = [NSString stringWithUTF8String:cname];
        if (name.length == 0 || [name hasPrefix:@"__MACOSX"] || [name containsString:@".."]) continue;
        if (entry->type(entry) == VFS_DIRECTORY || [name hasSuffix:@"/"]) continue;
        struct VFile* vf = dir->openFile(dir, cname, O_RDONLY);
        if (!vf) continue;
        ssize_t size = vf->size(vf);
        NSMutableData* data = [NSMutableData dataWithLength:(NSUInteger) MAX(size, 0)];
        if (size > 0) {
            vf->seek(vf, 0, SEEK_SET);
            vf->read(vf, data.mutableBytes, (size_t) size);
        }
        vf->close(vf);
        NSURL* dest = [directory URLByAppendingPathComponent:name];
        [fm createDirectoryAtURL:dest.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:NULL];
        if ([data writeToURL:dest atomically:YES]) written++;
    }
    dir->close(dir);
    return written;
}

#pragma mark - Sensors

static float _clamp1(float v) { return v < -1.f ? -1.f : (v > 1.f ? 1.f : v); }

- (void)setTiltX:(float)tiltX tiltY:(float)tiltY gyroZ:(float)gyroZ {
    _rotation.tiltX = (int32_t) (_clamp1(tiltX) * kTiltFullScale);
    _rotation.tiltY = (int32_t) (_clamp1(tiltY) * kTiltFullScale);
    _rotation.gyroZ = (int32_t) (_clamp1(gyroZ) * kGyroFullScale);
}

- (void)setRTCOffsetSeconds:(int64_t)seconds {
    _rtcOffset = seconds;
    _rtc.offset = seconds;
}

- (NSInteger)luminanceLevel {
    return _luminanceLevel;
}

- (void)applyLuminanceLevel:(NSInteger)level {
    // Same mapping as mGBA's Qt frontend (InputController::setLuminanceLevel).
    level = MAX((NSInteger) 0, MIN((NSInteger) 10, level));
    _luminanceLevel = level;
    int value = 0x16;
    if (level > 0) {
        value += GBA_LUX_LEVELS[level - 1];
    }
    _lux.value = (uint8_t) (0xFF - value);
}

@end
