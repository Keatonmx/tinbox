//
//  GBAEmulatorCore.h
//  Tinbox
//
//  Objective-C++ bridge around libmgba (mCore). Swift never touches mGBA
//  types directly; everything goes through this class.
//
//  Threading: the core is NOT thread-safe. EmulatorSession owns a dedicated
//  emulation thread and serialises every call into this object through its
//  own lock. The only members safe to read from any thread are the immutable
//  dimension properties.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Bit positions match mGBA's `enum GBAKey` (include/mgba/internal/gba/input.h).
typedef NS_OPTIONS(uint32_t, GBAKeyMask) {
    GBAKeyMaskA      NS_SWIFT_NAME(a)      = 1u << 0,
    GBAKeyMaskB      NS_SWIFT_NAME(b)      = 1u << 1,
    GBAKeyMaskSelect NS_SWIFT_NAME(select) = 1u << 2,
    GBAKeyMaskStart  NS_SWIFT_NAME(start)  = 1u << 3,
    GBAKeyMaskRight  NS_SWIFT_NAME(right)  = 1u << 4,
    GBAKeyMaskLeft   NS_SWIFT_NAME(left)   = 1u << 5,
    GBAKeyMaskUp     NS_SWIFT_NAME(up)     = 1u << 6,
    GBAKeyMaskDown   NS_SWIFT_NAME(down)   = 1u << 7,
    GBAKeyMaskR      NS_SWIFT_NAME(r)      = 1u << 8,
    GBAKeyMaskL      NS_SWIFT_NAME(l)      = 1u << 9,
};

/// Values match mGBA's `enum GBACheatType` (include/mgba/internal/gba/cheats.h).
typedef NS_ENUM(NSInteger, GBACheatCodeType) {
    GBACheatCodeTypeAutodetect   = 0,
    GBACheatCodeTypeCodeBreaker  = 1,
    GBACheatCodeTypeGameShark    = 2,
    GBACheatCodeTypeActionReplay = 3,
};

typedef NS_OPTIONS(NSUInteger, TinboxCartHardware) {
    TinboxCartHardwareNone   = 0,
    TinboxCartHardwareRTC    NS_SWIFT_NAME(rtc)    = 1 << 0,
    TinboxCartHardwareRumble NS_SWIFT_NAME(rumble) = 1 << 1,
    TinboxCartHardwareSolar  NS_SWIFT_NAME(solar)  = 1 << 2,
    TinboxCartHardwareGyro   NS_SWIFT_NAME(gyro)   = 1 << 3,
    TinboxCartHardwareTilt   NS_SWIFT_NAME(tilt)   = 1 << 4,
};

@class GBAEmulatorCore;

@protocol GBAEmulatorCoreDelegate <NSObject>
@optional
/// Called on the emulation thread whenever the cartridge rumble motor state is
/// integrated for a frame. `intensity` is 0…1 (duty cycle over the frame).
- (void)emulatorCore:(GBAEmulatorCore *)core rumbleIntensity:(float)intensity;
/// Called on the emulation thread after the core flushed battery-backed save data.
- (void)emulatorCoreDidUpdateSaveData:(GBAEmulatorCore *)core;
@end

@interface GBAEmulatorCore : NSObject

/// Creates the core and its configuration. Battery saves (.sav) are written to
/// `saveDirectory`; mGBA's own slot-based state API uses `stateDirectory`
/// (Tinbox uses explicit file URLs for states, but the directory is configured
/// so `mCoreAutoloadSave`/`mCoreGetState` work too).
- (nullable instancetype)initWithSaveDirectory:(NSURL *)saveDirectory
                       stateDirectory:(NSURL *)stateDirectory
                   screenshotDirectory:(NSURL *)screenshotDirectory NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, weak, nullable) id<GBAEmulatorCoreDelegate> delegate;

#pragma mark - Video

/// 240 × 160 for the GBA. Fixed for the lifetime of the object.
@property (nonatomic, readonly) NSUInteger videoWidth;
@property (nonatomic, readonly) NSUInteger videoHeight;
/// Packed 32-bit pixels, `videoWidth` pixels per row (stride == width).
/// Byte order in memory is R,G,B,X (mGBA's native 32-bit `mColor` with
/// COLOR_16_BIT undefined) → use MTLPixelFormatRGBA8Unorm and ignore alpha.
@property (nonatomic, readonly) const uint32_t *videoBuffer;
@property (nonatomic, readonly) NSUInteger videoBufferByteLength;

#pragma mark - ROM / BIOS / patches

@property (nonatomic, readonly) BOOL isROMLoaded;
@property (nonatomic, readonly, copy) NSString *gameTitle;   // internal header title, e.g. "POKEMON EMER"
@property (nonatomic, readonly, copy) NSString *gameCode;    // e.g. "BPEE"
@property (nonatomic, readonly) TinboxCartHardware cartridgeHardware;

/// Loads a .gba (or .zip containing a .gba), attaches the battery save from
/// the save directory, applies BIOS settings and resets the core.
- (BOOL)loadROMAtURL:(NSURL *)romURL error:(NSError **)error NS_SWIFT_NAME(loadROM(at:));
- (void)unloadROM;

/// Applies an IPS/UPS/BPS patch in memory to the currently loaded ROM
/// (the file on disk is untouched). Call after loadROM; the core is reset.
- (BOOL)applyPatchAtURL:(NSURL *)patchURL NS_SWIFT_NAME(applyPatch(at:));

/// The ROM image currently in memory (patched, if a patch was applied).
- (nullable NSData *)copyROMData;

/// `nil` selects HLE BIOS. A real `gba_bios.bin` is validated before use.
/// Takes effect on the next reset / ROM load.
- (BOOL)setBIOSFileURL:(nullable NSURL *)biosURL NS_SWIFT_NAME(setBIOSFile(_:));
@property (nonatomic, readonly) BOOL usesBIOSFile;
/// Loads the configured BIOS into the running core via `core->loadBIOS` and
/// resets. Used when the user imports a BIOS while a game is open.
- (BOOL)loadBIOSNow;

- (void)reset;

#pragma mark - Execution

/// Runs exactly one emulated frame (~16.74 ms of GBA time).
- (void)runFrame;
@property (nonatomic, readonly) uint32_t frameCounter;

/// Replace the full key state (never poke REG_KEYINPUT).
- (void)setKeys:(GBAKeyMask)keys;
- (GBAKeyMask)keys;

#pragma mark - Audio

/// 32768 Hz for the GBA core.
@property (nonatomic, readonly) NSUInteger audioSampleRate;
/// Number of stereo frames currently buffered by the core.
- (NSUInteger)availableAudioFrames;
/// Copies up to `frames` interleaved stereo int16 frames into `out`. Returns frames written.
- (NSUInteger)readAudioFrames:(int16_t *)out count:(NSUInteger)frames NS_SWIFT_NAME(readAudioFrames(_:count:));
- (void)clearAudio;
/// Resize the core-side ring buffer (frames). Default 4096.
- (void)setAudioBufferFrames:(NSUInteger)frames;
/// 0…100
- (void)setVolume:(NSInteger)volume;
- (void)setMuted:(BOOL)muted;

#pragma mark - Save states

/// Writes a full state (+ savedata, RTC, metadata and embedded screenshot).
- (BOOL)saveStateToURL:(NSURL *)url NS_SWIFT_NAME(saveState(to:));
- (BOOL)loadStateFromURL:(NSURL *)url NS_SWIFT_NAME(loadState(from:));
/// In-memory variants for auto-suspend / rewind-on-exit style use.
- (nullable NSData *)serializeState;
- (BOOL)deserializeState:(NSData *)data;
/// Flushes battery-backed save RAM to its .sav file immediately.
- (void)flushSaveData;

#pragma mark - Rewind

/// Keeps `seconds` of history. mGBA stores one delta-compressed snapshot every
/// `interval` frames. Disabling frees the buffer.
- (void)setRewindEnabled:(BOOL)enabled seconds:(NSUInteger)seconds frameInterval:(NSUInteger)interval NS_SWIFT_NAME(setRewind(enabled:seconds:frameInterval:));
@property (nonatomic, readonly) BOOL isRewindEnabled;
/// Steps back `frames` emulated frames (rounded to the snapshot interval).
/// Returns NO if no history is available.
- (BOOL)rewindFrames:(NSUInteger)frames NS_SWIFT_NAME(rewind(frames:));

#pragma mark - Cheats

/// Replaces the whole cheat list. `code` may contain several lines separated by
/// newlines. Returns the number of codes that parsed successfully.
- (NSUInteger)setCheats:(NSArray<NSDictionary<NSString *, id> *> *)cheats; // keys: name, code, type(NSNumber), enabled(NSNumber)
- (void)setCheatAtIndex:(NSUInteger)index enabled:(BOOL)enabled NS_SWIFT_NAME(setCheat(at:enabled:));
- (void)removeAllCheats;
/// Validates a code without installing it.
+ (BOOL)validateCheatCode:(NSString *)code type:(GBACheatCodeType)type;

#pragma mark - Sensors

/// Tilt in g (−1…1). Gyro Z in normalised units (−1…1 ≈ ±one full turn/s).
- (void)setTiltX:(float)tiltX tiltY:(float)tiltY gyroZ:(float)gyroZ NS_SWIFT_NAME(setTilt(x:y:gyroZ:));
/// Solar sensor brightness level 0 (dark) … 10 (direct sun).
- (void)applyLuminanceLevel:(NSInteger)level NS_SWIFT_NAME(applyLuminanceLevel(_:));
@property (nonatomic, readonly) NSInteger luminanceLevel;

#pragma mark - Misc

/// Copies the current framebuffer into a freshly allocated RGBA8 buffer (caller owns it via NSData).
- (NSData *)copyFramebuffer;
@property (class, nonatomic, readonly) NSString *coreVersion;

@end

NS_ASSUME_NONNULL_END
