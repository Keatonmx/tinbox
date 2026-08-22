//
//  GBAEmulatorCore.mm
//  Tinbox
//
//  Objective-C++ bridge over libmgba. Written against the mGBA headers in
//  Vendor/mgba-dist/include (see Scripts/build-mgba.sh). `mgba/flags.h` MUST be
//  the first mGBA include: it carries the ENABLE_*/USE_* defines the library was
//  compiled with, and `struct mCore`'s layout depends on them.
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
#include <mgba/internal/gba/gba.h>
#include <mgba/internal/gba/cheats.h>
#include <mgba/internal/gba/input.h>
#include <mgba/internal/gba/memory.h>
#include <mgba/internal/gba/savedata.h>
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

static const int kSaveFlags = SAVESTATE_SCREENSHOT | SAVESTATE_SAVEDATA | SAVESTATE_RTC | SAVESTATE_METADATA;
static const int kLoadFlags = SAVESTATE_SCREENSHOT | SAVESTATE_SAVEDATA | SAVESTATE_RTC;

#pragma mark - GBAEmulatorCore

@interface GBAEmulatorCore () {
    struct mCore* _core;
    mColor* _videoBuffer;
    unsigned _width;
    unsigned _height;

    struct mCoreCallbacks _callbacks;
    struct TinboxRumble _rumble;
    struct TinboxRotation _rotation;
    struct TinboxLuminance _lux;

    struct mCoreRewindContext _rewind;
    BOOL _rewindEnabled;
    NSUInteger _rewindInterval;
    NSUInteger _rewindEntries;
    NSUInteger _rewindFrameCounter;

    NSString* _biosPath;
    NSString* _romPath;
    NSInteger _luminanceLevel;
}
- (void)applyBIOSConfiguration;
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

    _core = GBACoreCreate();
    if (!_core) {
        return nil;
    }
    _core->init(_core);

    // Configuration. Paths are absolute; mGBA opens/creates the directories in
    // mDirectorySetMapOptions, which is what makes battery saves land in
    // Documents/Saves automatically.
    mCoreInitConfig(_core, "tinbox");
    mCoreConfigSetValue(&_core->config, "savegamePath", saveDirectory.fileSystemRepresentation);
    mCoreConfigSetValue(&_core->config, "savestatePath", stateDirectory.fileSystemRepresentation);
    mCoreConfigSetValue(&_core->config, "screenshotPath", screenshotDirectory.fileSystemRepresentation);
    mCoreConfigSetIntValue(&_core->config, "useBios", 0);
    mCoreConfigSetIntValue(&_core->config, "skipBios", 0);
    mCoreConfigSetIntValue(&_core->config, "volume", 0x100);   // GBA_AUDIO_VOLUME_MAX; unset == silent
    mCoreConfigSetIntValue(&_core->config, "mute", 0);
    mCoreConfigSetIntValue(&_core->config, "frameskip", 0);
    mCoreConfigSetUIntValue(&_core->config, "audioBuffers", 4096);
    mCoreConfigSetIntValue(&_core->config, "cheatAutosave", 0);
    mCoreConfigSetIntValue(&_core->config, "cheatAutoload", 0);
    mCoreConfigSetValue(&_core->config, "idleOptimization", "remove");
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

    // Peripherals.
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

    memset(&_lux, 0, sizeof(_lux));
    _lux.source.sample = _luxSample;
    _lux.source.readLuminance = _luxRead;
    _core->setPeripheral(_core, mPERIPH_GBA_LUMINANCE, &_lux.source);
    [self applyLuminanceLevel:0];

    memset(&_rewind, 0, sizeof(_rewind));
    _rewindInterval = 1;

    return self;
}

- (void)dealloc {
    if (_core) {
        [self setRewindEnabled:NO seconds:0 frameInterval:1];
        [self unloadROM];
        _core->removeCoreCallbacks(_core, &_callbacks);
        mCoreConfigDeinit(&_core->config);
        _core->deinit(_core);
        _core = NULL;
    }
    free(_videoBuffer);
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
    struct GBA* gba = (struct GBA*) _core->board;
    uint32_t devices = gba->memory.hw.devices;
    TinboxCartHardware hw = TinboxCartHardwareNone;
    if (devices & HW_RTC)          hw |= TinboxCartHardwareRTC;
    if (devices & HW_RUMBLE)       hw |= TinboxCartHardwareRumble;
    if (devices & HW_LIGHT_SENSOR) hw |= TinboxCartHardwareSolar;
    if (devices & HW_GYRO)         hw |= TinboxCartHardwareGyro;
    if (devices & HW_TILT)         hw |= TinboxCartHardwareTilt;
    return hw;
}

- (BOOL)loadROMAtURL:(NSURL*)romURL error:(NSError**)error {
    [self unloadROM];

    // mCoreLoadFile resolves archives (.zip) through mDirectorySetOpenPath and
    // validates the payload with core->isROM (GBAIsROM).
    if (!mCoreLoadFile(_core, romURL.fileSystemRepresentation)) {
        if (error) {
            *error = [NSError errorWithDomain:@"Tinbox.GBAEmulatorCore"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"mGBA could not load this file as a GBA ROM."}];
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
    if (!_romPath) return;
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
    // loadPatch applies IPS/UPS/BPS in memory (GBAApplyPatch); the ROM on disk is untouched.
    BOOL ok = _core->loadPatch(_core, vf);
    vf->close(vf);
    if (ok) {
        _core->reset(_core);
    }
    return ok;
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
    if (!_romPath || !_biosPath) return NO;
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
    if (_biosPath) {
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
    volume = MAX((NSInteger) 0, MIN((NSInteger) 100, volume));
    mCoreConfigSetIntValue(&_core->config, "volume", (int) (volume * 0x100 / 100));
    _core->reloadConfigOption(_core, "volume", &_core->config);
}

- (void)setMuted:(BOOL)muted {
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
    struct GBA* gba = (struct GBA*) _core->board;
    struct GBASavedata* savedata = &gba->memory.savedata;
    if (!savedata->vf || !savedata->data) return;
    if (savedata->maskWriteback) {
        GBASavedataUnmask(savedata);
    }
    if (savedata->mapMode & MAP_WRITE) {
        savedata->vf->sync(savedata->vf, savedata->data, GBASavedataSize(savedata));
    }
}

#pragma mark - Rewind

- (BOOL)isRewindEnabled {
    return _rewindEnabled;
}

- (void)setRewindEnabled:(BOOL)enabled seconds:(NSUInteger)seconds frameInterval:(NSUInteger)interval {
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
    if (!enabled || seconds == 0) {
        return;
    }
    _rewindInterval = MAX((NSUInteger) 1, interval);
    // GBA runs at ~59.73 fps; one delta-compressed snapshot every `interval` frames.
    _rewindEntries = MAX((NSUInteger) 2, (seconds * 60) / _rewindInterval);
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
    for (NSString* line in lines) {
        NSRange r = NSMakeRange(0, line.length);
        BOOL isGS = [gs numberOfMatchesInString:line options:0 range:r] == 1;
        BOOL isCB = [cb numberOfMatchesInString:line options:0 range:r] == 1;
        switch (type) {
            case GBACheatCodeTypeCodeBreaker:
                if (!isCB) return NO;
                break;
            case GBACheatCodeTypeGameShark:
            case GBACheatCodeTypeActionReplay:
                if (!isGS) return NO;
                break;
            case GBACheatCodeTypeAutodetect:
                if (!isGS && !isCB) return NO;
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

        struct mCheatSet* set = device->createSet(device, name.UTF8String);
        BOOL parsedAny = NO;
        for (NSString* line in [GBAEmulatorCore normalizedLinesForCode:code]) {
            if (mCheatAddLine(set, line.UTF8String, (int) type)) {
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

#pragma mark - Sensors

static float _clamp1(float v) { return v < -1.f ? -1.f : (v > 1.f ? 1.f : v); }

- (void)setTiltX:(float)tiltX tiltY:(float)tiltY gyroZ:(float)gyroZ {
    _rotation.tiltX = (int32_t) (_clamp1(tiltX) * kTiltFullScale);
    _rotation.tiltY = (int32_t) (_clamp1(tiltY) * kTiltFullScale);
    _rotation.gyroZ = (int32_t) (_clamp1(gyroZ) * kGyroFullScale);
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
