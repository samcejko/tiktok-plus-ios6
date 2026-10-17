#import <Foundation/Foundation.h>

// TikTok's captions of a video: which of its tracks to show (the device's language, else what is spoken, else
// English), the WebVTT file read into cues, and the line for a moment of the video. Loaded tracks are kept a while.
@interface TKSubtitles : NSObject
+ (NSDictionary *)bestTrackOf:(NSArray *)tracks;          // one of TKVideo.subtitles; nil when there are none
+ (void)loadTrack:(NSDictionary *)track completion:(void (^)(TKSubtitles *subtitles))completion;   // nil on failure
+ (TKSubtitles *)subtitlesFromWebVTT:(NSString *)text;
- (NSString *)textAt:(NSTimeInterval)seconds;             // nil between lines
@property (nonatomic, readonly) NSUInteger count;
@end
