#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudio.h>

NS_ASSUME_NONNULL_BEGIN

@interface SystemAudioTapRecorder : NSObject

@property (atomic, readonly, getter=isRecording) BOOL recording;
@property (atomic, getter=isPaused) BOOL paused;
@property (atomic, readonly) float meterLevel;
@property (nonatomic, readonly, nullable) NSURL *outputURL;

- (BOOL)prepareRecordingAtURL:(NSURL *)outputURL
             excludedBundleID:(nullable NSString *)excludedBundleID
                        error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(prepareRecording(at:excludedBundleID:));

- (BOOL)startRecordingAndReturnError:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(startRecording());

- (void)stopRecording;
- (void)invalidate;

@end

NS_ASSUME_NONNULL_END
