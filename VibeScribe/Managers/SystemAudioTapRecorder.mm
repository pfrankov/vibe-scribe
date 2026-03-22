#import "SystemAudioTapRecorder.h"

#import <AudioToolbox/ExtendedAudioFile.h>
#import <CoreAudio/AudioHardwareTapping.h>
#import <CoreAudio/CATapDescription.h>
#import <algorithm>
#import <cstdint>
#import <cstring>
#import <cmath>
#import <atomic>
#import <vector>
#import <unistd.h>

namespace {

constexpr AudioObjectPropertyAddress PropertyAddress(
    AudioObjectPropertySelector selector,
    AudioObjectPropertyScope scope = kAudioObjectPropertyScopeGlobal,
    AudioObjectPropertyElement element = kAudioObjectPropertyElementMain
) noexcept {
    return {selector, scope, element};
}

enum class StreamDirection : UInt32 {
    output = 0,
    input = 1,
};

NSString *const SystemAudioTapRecorderErrorDomain = @"VibeScribe.SystemAudioTapRecorder";

static NSString *StatusDebugString(OSStatus status) {
    UInt32 bigEndian = CFSwapInt32HostToBig(static_cast<UInt32>(status));
    char chars[5] = {};
    memcpy(chars, &bigEndian, sizeof(bigEndian));

    for (char character : chars) {
        if (character == 0) {
            continue;
        }
        if (character < 32 || character > 126) {
            return [NSString stringWithFormat:@"%d", static_cast<int>(status)];
        }
    }

    return [NSString stringWithFormat:@"'%s' (%d)", chars, static_cast<int>(status)];
}

static NSError *MakeStatusError(OSStatus status, NSString *description) {
    NSString *debug = StatusDebugString(status);
    NSString *message = [NSString stringWithFormat:@"%@ [%@]", description, debug];
    return [NSError errorWithDomain:SystemAudioTapRecorderErrorDomain
                               code:status
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static float NormalizedMeterLevelFromBufferList(const AudioBufferList *bufferList,
                                                const AudioStreamBasicDescription &format) noexcept {
    if (bufferList == nullptr || bufferList->mNumberBuffers == 0) {
        return 0.0f;
    }

    const bool isFloat = (format.mFormatFlags & kAudioFormatFlagIsFloat) != 0;
    const bool isSignedInteger = (format.mFormatFlags & kAudioFormatFlagIsSignedInteger) != 0;
    const int bitsPerChannel = static_cast<int>(format.mBitsPerChannel);
    const int bytesPerSample = std::max(1, bitsPerChannel / 8);

    double sumSquares = 0.0;
    int countedSamples = 0;

    for (UInt32 bufferIndex = 0; bufferIndex < bufferList->mNumberBuffers; ++bufferIndex) {
        const AudioBuffer &buffer = bufferList->mBuffers[bufferIndex];
        if (buffer.mData == nullptr || buffer.mDataByteSize == 0) {
            continue;
        }

        const int channels = std::max<UInt32>(1, buffer.mNumberChannels);
        const int sampleCount = static_cast<int>(buffer.mDataByteSize) / bytesPerSample;
        if (sampleCount <= 0) {
            continue;
        }

        const int step = std::max(1, sampleCount / 1024);

        if (isFloat && bitsPerChannel == 32) {
            const auto *samples = static_cast<const float *>(buffer.mData);
            for (int index = 0; index < sampleCount; index += step) {
                const double value = static_cast<double>(samples[index]);
                sumSquares += value * value;
                ++countedSamples;
            }
        } else if (isSignedInteger && bitsPerChannel == 16) {
            const auto *samples = static_cast<const int16_t *>(buffer.mData);
            constexpr double scale = 1.0 / static_cast<double>(INT16_MAX);
            for (int index = 0; index < sampleCount; index += step) {
                const double value = static_cast<double>(samples[index]) * scale;
                sumSquares += value * value;
                ++countedSamples;
            }
        } else if (isSignedInteger && bitsPerChannel == 32) {
            const auto *samples = static_cast<const int32_t *>(buffer.mData);
            constexpr double scale = 1.0 / static_cast<double>(INT32_MAX);
            for (int index = 0; index < sampleCount; index += step) {
                const double value = static_cast<double>(samples[index]) * scale;
                sumSquares += value * value;
                ++countedSamples;
            }
        } else {
            const int frameCount = sampleCount / channels;
            if (frameCount <= 0) {
                continue;
            }

            const auto *bytes = static_cast<const uint8_t *>(buffer.mData);
            for (int frameIndex = 0; frameIndex < frameCount; frameIndex += std::max(1, frameCount / 1024)) {
                const int byteIndex = frameIndex * bytesPerSample;
                const double value = static_cast<double>(bytes[byteIndex]) / 255.0;
                sumSquares += value * value;
                ++countedSamples;
            }
        }
    }

    if (countedSamples == 0) {
        return 0.0f;
    }

    const double rms = std::sqrt(sumSquares / static_cast<double>(countedSamples));
    const double powerDb = 20.0 * std::log10(rms + 1e-12);
    const double minDb = -80.0;
    const double clipped = std::max(minDb, powerDb);
    const double normalizedDb = (clipped - minDb) / (-minDb);
    return static_cast<float>(std::clamp(std::pow(normalizedDb, 1.1), 0.0, 1.0));
}

static OSStatus SystemAudioTapIOProc(AudioObjectID,
                                     const AudioTimeStamp *,
                                     const AudioBufferList *inInputData,
                                     const AudioTimeStamp *,
                                     AudioBufferList *,
                                     const AudioTimeStamp *,
                                     void *inClientData) noexcept;

} // namespace

@interface SystemAudioTapRecorder () {
    AudioObjectID _tapID;
    AudioObjectID _aggregateDeviceID;
    AudioDeviceIOProcID _ioProcID;
    AudioStreamBasicDescription _inputStreamFormat;
    BOOL _hasInputStreamFormat;
    ExtAudioFileRef _recordingFile;
    std::atomic_bool _recordingFlag;
    std::atomic_bool _pausedFlag;
    std::atomic<float> _meterLevelAtomic;
}

@property (atomic, readwrite, getter=isRecording) BOOL recording;
@property (nonatomic, readwrite, nullable) NSURL *outputURL;

@end

@implementation SystemAudioTapRecorder

- (instancetype)init {
    self = [super init];
    if (self == nil) {
        return nil;
    }

    _tapID = kAudioObjectUnknown;
    _aggregateDeviceID = kAudioObjectUnknown;
    _ioProcID = nullptr;
    _recordingFile = nullptr;
    _hasInputStreamFormat = NO;
    _recordingFlag.store(false);
    _pausedFlag.store(false);
    _meterLevelAtomic.store(0.0f);
    _recording = NO;
    memset(&_inputStreamFormat, 0, sizeof(_inputStreamFormat));
    return self;
}

- (void)dealloc {
    [self invalidate];
}

- (BOOL)isPaused {
    return _pausedFlag.load();
}

- (void)setPaused:(BOOL)paused {
    _pausedFlag.store(paused);
    if (paused) {
        _meterLevelAtomic.store(0.0f);
    }
}

- (float)meterLevel {
    return _meterLevelAtomic.load();
}

- (BOOL)prepareRecordingAtURL:(NSURL *)outputURL
             excludedBundleID:(nullable NSString *)excludedBundleID
                        error:(NSError * _Nullable * _Nullable)error {
    [self stopRecording];
    self.outputURL = outputURL;
    _meterLevelAtomic.store(0.0f);
    _pausedFlag.store(false);

    if (![self createTapExcludingBundleID:excludedBundleID error:error]) {
        [self stopRecording];
        return NO;
    }

    if (![self createAggregateDevice:error]) {
        [self stopRecording];
        return NO;
    }

    if (![self waitForInputStreamFormat:error]) {
        [self stopRecording];
        return NO;
    }

    return YES;
}

- (BOOL)startRecordingAndReturnError:(NSError * _Nullable * _Nullable)error {
    if (_aggregateDeviceID == kAudioObjectUnknown || !_hasInputStreamFormat) {
        if (error != nullptr) {
            *error = [NSError errorWithDomain:SystemAudioTapRecorderErrorDomain
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"System audio capture is not prepared."}];
        }
        return NO;
    }

    if (![self openRecordingFile:error]) {
        return NO;
    }

    OSStatus status = AudioDeviceCreateIOProcID(
        _aggregateDeviceID,
        SystemAudioTapIOProc,
        (__bridge void *)self,
        &_ioProcID
    );
    if (status != noErr) {
        [self closeRecordingFile];
        if (error != nullptr) {
            *error = MakeStatusError(status, @"Failed to create audio device IO proc.");
        }
        return NO;
    }

    status = AudioDeviceStart(_aggregateDeviceID, _ioProcID);
    if (status != noErr) {
        AudioDeviceDestroyIOProcID(_aggregateDeviceID, _ioProcID);
        _ioProcID = nullptr;
        [self closeRecordingFile];
        if (error != nullptr) {
            *error = MakeStatusError(status, @"Failed to start aggregate device IO.");
        }
        return NO;
    }

    _recordingFlag.store(true);
    self.recording = YES;
    return YES;
}

- (void)stopRecording {
    _recordingFlag.store(false);
    _pausedFlag.store(false);
    _meterLevelAtomic.store(0.0f);
    self.recording = NO;

    if (_aggregateDeviceID != kAudioObjectUnknown && _ioProcID != nullptr) {
        AudioDeviceStop(_aggregateDeviceID, _ioProcID);
        AudioDeviceDestroyIOProcID(_aggregateDeviceID, _ioProcID);
        _ioProcID = nullptr;
    }

    [self closeRecordingFile];
    [self destroyAggregateDevice];
    [self destroyTap];

    _hasInputStreamFormat = NO;
    memset(&_inputStreamFormat, 0, sizeof(_inputStreamFormat));
}

- (void)invalidate {
    [self stopRecording];
    self.outputURL = nil;
}

- (BOOL)createTapExcludingBundleID:(nullable NSString *)excludedBundleID
                             error:(NSError * _Nullable * _Nullable)error {
    CATapDescription *description = [[CATapDescription alloc] initMonoGlobalTapButExcludeProcesses:@[]];
    description.name = @"VibeScribe System Audio";
    description.privateTap = YES;
    description.muteBehavior = CATapUnmuted;

    if (excludedBundleID.length > 0) {
        description.bundleIDs = @[excludedBundleID];
    }

    OSStatus status = AudioHardwareCreateProcessTap(description, &_tapID);
    if (status != noErr) {
        if (error != nullptr) {
            *error = MakeStatusError(status, @"Failed to create the Core Audio process tap.");
        }
        return NO;
    }

    return YES;
}

- (BOOL)createAggregateDevice:(NSError * _Nullable * _Nullable)error {
    NSString *tapUID = [self tapUID:error];
    if (tapUID == nil) {
        return NO;
    }

    NSString *defaultOutputUID = [self defaultOutputDeviceUID:error];
    if (defaultOutputUID == nil) {
        return NO;
    }

    NSDictionary *description = @{
        @kAudioAggregateDeviceNameKey: @"VibeScribe System Audio Device",
        @kAudioAggregateDeviceUIDKey: [[NSUUID UUID] UUIDString],
        @kAudioAggregateDeviceIsPrivateKey: @YES,
    };

    OSStatus status = AudioHardwareCreateAggregateDevice((__bridge CFDictionaryRef)description, &_aggregateDeviceID);
    if (status != noErr) {
        if (error != nullptr) {
            *error = MakeStatusError(status, @"Failed to create the aggregate device used for system audio capture.");
        }
        return NO;
    }

    // Give HAL a moment to publish the new private aggregate before mutating its lists.
    usleep(100000);

    if (![self addUID:defaultOutputUID
        toArrayProperty:kAudioAggregateDevicePropertyFullSubDeviceList
              onObject:_aggregateDeviceID
                 error:error]) {
        return NO;
    }

    if (![self setMainSubDeviceUID:defaultOutputUID error:error]) {
        return NO;
    }

    if (![self addUID:tapUID
        toArrayProperty:kAudioAggregateDevicePropertyTapList
              onObject:_aggregateDeviceID
                 error:error]) {
        return NO;
    }

    return YES;
}

- (nullable NSString *)tapUID:(NSError * _Nullable * _Nullable)error {
    if (_tapID == kAudioObjectUnknown) {
        if (error != nullptr) {
            *error = [NSError errorWithDomain:SystemAudioTapRecorderErrorDomain
                                         code:-2
                                     userInfo:@{NSLocalizedDescriptionKey: @"Process tap was not created."}];
        }
        return nil;
    }

    AudioObjectPropertyAddress address = PropertyAddress(kAudioTapPropertyUID);
    UInt32 size = sizeof(CFStringRef);
    CFStringRef tapUIDRef = nullptr;
    OSStatus status = AudioObjectGetPropertyData(_tapID, &address, 0, nullptr, &size, &tapUIDRef);
    if (status != noErr || tapUIDRef == nullptr) {
        if (error != nullptr) {
            *error = MakeStatusError(status, @"Failed to read the tap UID.");
        }
        if (tapUIDRef != nullptr) {
            CFRelease(tapUIDRef);
        }
        return nil;
    }

    return CFBridgingRelease(tapUIDRef);
}

- (nullable NSString *)defaultOutputDeviceUID:(NSError * _Nullable * _Nullable)error {
    AudioObjectID deviceID = kAudioObjectUnknown;
    AudioObjectPropertyAddress address = PropertyAddress(kAudioHardwarePropertyDefaultOutputDevice);
    UInt32 size = sizeof(deviceID);
    OSStatus status = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &address,
        0,
        nullptr,
        &size,
        &deviceID
    );
    if (status != noErr || deviceID == kAudioObjectUnknown) {
        if (error != nullptr) {
            *error = MakeStatusError(status, @"Failed to resolve the default output device.");
        }
        return nil;
    }

    address = PropertyAddress(kAudioDevicePropertyDeviceUID);
    size = sizeof(CFStringRef);
    CFStringRef uidRef = nullptr;
    status = AudioObjectGetPropertyData(deviceID, &address, 0, nullptr, &size, &uidRef);
    if (status != noErr || uidRef == nullptr) {
        if (error != nullptr) {
            *error = MakeStatusError(status, @"Failed to read the default output device UID.");
        }
        if (uidRef != nullptr) {
            CFRelease(uidRef);
        }
        return nil;
    }

    return CFBridgingRelease(uidRef);
}

- (BOOL)addUID:(NSString *)uid
toArrayProperty:(AudioObjectPropertySelector)selector
      onObject:(AudioObjectID)objectID
         error:(NSError * _Nullable * _Nullable)error {
    AudioObjectPropertyAddress address = PropertyAddress(selector);
    UInt32 size = 0;
    OSStatus status = AudioObjectGetPropertyDataSize(objectID, &address, 0, nullptr, &size);
    if (status != noErr) {
        if (error != nullptr) {
            *error = MakeStatusError(status, @"Failed to inspect aggregate device list size.");
        }
        return NO;
    }

    CFArrayRef listRef = nullptr;
    if (size > 0) {
        status = AudioObjectGetPropertyData(objectID, &address, 0, nullptr, &size, &listRef);
        if (status != noErr) {
            if (error != nullptr) {
                *error = MakeStatusError(status, @"Failed to load aggregate device list.");
            }
            if (listRef != nullptr) {
                CFRelease(listRef);
            }
            return NO;
        }
    }

    NSMutableArray<NSString *> *uids = listRef != nullptr
        ? [CFBridgingRelease(listRef) mutableCopy]
        : [NSMutableArray array];

    if (![uids containsObject:uid]) {
        [uids addObject:uid];
    }

    CFArrayRef updatedList = (__bridge CFArrayRef)uids;
    size = sizeof(updatedList);
    status = AudioObjectSetPropertyData(objectID, &address, 0, nullptr, size, &updatedList);
    if (status != noErr) {
        if (error != nullptr) {
            *error = MakeStatusError(status, @"Failed to update aggregate device membership.");
        }
        return NO;
    }

    return YES;
}

- (BOOL)setMainSubDeviceUID:(NSString *)uid error:(NSError * _Nullable * _Nullable)error {
    AudioObjectPropertyAddress address = PropertyAddress(kAudioAggregateDevicePropertyMainSubDevice);
    CFStringRef uidRef = (__bridge CFStringRef)uid;
    UInt32 size = sizeof(uidRef);
    OSStatus status = AudioObjectSetPropertyData(_aggregateDeviceID, &address, 0, nullptr, size, &uidRef);
    if (status != noErr) {
        if (error != nullptr) {
            *error = MakeStatusError(status, @"Failed to set the aggregate device time base.");
        }
        return NO;
    }

    return YES;
}

- (BOOL)waitForInputStreamFormat:(NSError * _Nullable * _Nullable)error {
    constexpr useconds_t waitStepUs = 50000;
    constexpr int maxAttempts = 20;

    for (int attempt = 0; attempt < maxAttempts; ++attempt) {
        if ([self catalogInputStreamFormat]) {
            return YES;
        }
        usleep(waitStepUs);
    }

    if (error != nullptr) {
        *error = [NSError errorWithDomain:SystemAudioTapRecorderErrorDomain
                                     code:-3
                                 userInfo:@{NSLocalizedDescriptionKey: @"Aggregate device did not expose a readable input stream for the tap."}];
    }
    return NO;
}

- (BOOL)catalogInputStreamFormat {
    _hasInputStreamFormat = NO;
    memset(&_inputStreamFormat, 0, sizeof(_inputStreamFormat));

    if (_aggregateDeviceID == kAudioObjectUnknown) {
        return NO;
    }

    AudioObjectPropertyAddress address = PropertyAddress(kAudioDevicePropertyStreams);
    UInt32 size = 0;
    OSStatus status = AudioObjectGetPropertyDataSize(_aggregateDeviceID, &address, 0, nullptr, &size);
    if (status != noErr || size == 0) {
        return NO;
    }

    std::vector<AudioObjectID> streamList(size / sizeof(AudioObjectID));
    status = AudioObjectGetPropertyData(_aggregateDeviceID, &address, 0, nullptr, &size, streamList.data());
    if (status != noErr) {
        return NO;
    }

    for (const AudioObjectID streamID : streamList) {
        AudioStreamBasicDescription format = {};
        address = PropertyAddress(kAudioStreamPropertyVirtualFormat);
        size = sizeof(format);
        status = AudioObjectGetPropertyData(streamID, &address, 0, nullptr, &size, &format);
        if (status != noErr) {
            continue;
        }

        UInt32 directionRaw = 0;
        address = PropertyAddress(kAudioStreamPropertyDirection);
        size = sizeof(directionRaw);
        status = AudioObjectGetPropertyData(streamID, &address, 0, nullptr, &size, &directionRaw);
        if (status != noErr) {
            continue;
        }

        if (static_cast<StreamDirection>(directionRaw) == StreamDirection::input) {
            _inputStreamFormat = format;
            _hasInputStreamFormat = YES;
            return YES;
        }
    }

    return NO;
}

- (BOOL)openRecordingFile:(NSError * _Nullable * _Nullable)error {
    if (self.outputURL == nil) {
        if (error != nullptr) {
            *error = [NSError errorWithDomain:SystemAudioTapRecorderErrorDomain
                                         code:-4
                                     userInfo:@{NSLocalizedDescriptionKey: @"No output URL was configured for system audio capture."}];
        }
        return NO;
    }

    if (!_hasInputStreamFormat) {
        if (error != nullptr) {
            *error = [NSError errorWithDomain:SystemAudioTapRecorderErrorDomain
                                         code:-5
                                     userInfo:@{NSLocalizedDescriptionKey: @"Input stream format is missing for the aggregate device."}];
        }
        return NO;
    }

    [self closeRecordingFile];

    if ([[NSFileManager defaultManager] fileExistsAtPath:self.outputURL.path]) {
        [[NSFileManager defaultManager] removeItemAtURL:self.outputURL error:nil];
    }

    OSStatus status = ExtAudioFileCreateWithURL(
        (__bridge CFURLRef)self.outputURL,
        kAudioFileCAFType,
        &_inputStreamFormat,
        nullptr,
        kAudioFileFlags_EraseFile,
        &_recordingFile
    );
    if (status != noErr) {
        if (error != nullptr) {
            *error = MakeStatusError(status, @"Failed to open the destination file for system audio capture.");
        }
        _recordingFile = nullptr;
        return NO;
    }

    return YES;
}

- (void)closeRecordingFile {
    if (_recordingFile != nullptr) {
        ExtAudioFileDispose(_recordingFile);
        _recordingFile = nullptr;
    }
}

- (void)destroyAggregateDevice {
    if (_aggregateDeviceID != kAudioObjectUnknown) {
        AudioHardwareDestroyAggregateDevice(_aggregateDeviceID);
        _aggregateDeviceID = kAudioObjectUnknown;
    }
}

- (void)destroyTap {
    if (_tapID != kAudioObjectUnknown) {
        AudioHardwareDestroyProcessTap(_tapID);
        _tapID = kAudioObjectUnknown;
    }
}

- (OSStatus)handleIOProcInputData:(const AudioBufferList *)inInputData {
    const float level = _hasInputStreamFormat
        ? NormalizedMeterLevelFromBufferList(inInputData, _inputStreamFormat)
        : 0.0f;

    _meterLevelAtomic.store(level);

    if (!_recordingFlag.load() || _pausedFlag.load()) {
        return noErr;
    }

    if (inInputData == nullptr || inInputData->mNumberBuffers == 0 || _recordingFile == nullptr) {
        return noErr;
    }

    UInt32 bytesPerFrame = _inputStreamFormat.mBytesPerFrame;
    if (bytesPerFrame == 0 && _inputStreamFormat.mBitsPerChannel > 0) {
        const UInt32 channels = std::max<UInt32>(1, _inputStreamFormat.mChannelsPerFrame);
        bytesPerFrame = channels * (_inputStreamFormat.mBitsPerChannel / 8);
    }

    if (bytesPerFrame == 0) {
        return noErr;
    }

    const AudioBuffer &firstBuffer = inInputData->mBuffers[0];
    const UInt32 frameCount = firstBuffer.mDataByteSize / bytesPerFrame;
    if (frameCount == 0) {
        return noErr;
    }

    ExtAudioFileWriteAsync(_recordingFile, frameCount, inInputData);
    return noErr;
}

@end

namespace {

static OSStatus SystemAudioTapIOProc(AudioObjectID,
                                     const AudioTimeStamp *,
                                     const AudioBufferList *inInputData,
                                     const AudioTimeStamp *,
                                     AudioBufferList *,
                                     const AudioTimeStamp *,
                                     void *inClientData) noexcept {
    auto *recorder = (__bridge SystemAudioTapRecorder *)inClientData;
    if (recorder == nil) {
        return noErr;
    }
    return [recorder handleIOProcInputData:inInputData];
}

} // namespace
