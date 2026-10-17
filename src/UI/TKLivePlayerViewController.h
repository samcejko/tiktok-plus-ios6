#import <UIKit/UIKit.h>

// Posted on the main thread with userInfo @{@"playing": @YES} when a live stream comes on screen and @NO when its
// screen closes: the feed under it pauses meanwhile (a sheet between them hides the feed from UIKit's callbacks).
extern NSString * const TKLivePlaybackNotification;

// A TikTok LIVE room, full screen. TikTok hands a visitor FLV only, which the player of iOS 6 cannot open: the media
// proxy repacks it on the device into a live HLS playlist (TKLiveRemux); an HLS address goes to the player as it is.
// The room is checked again every half minute (viewers, and whether the stream is still on). A stream that breaks
// off is started again a few times while the room is still live.
@interface TKLivePlayerViewController : UIViewController

- (instancetype)initWithRoomId:(NSString *)roomId;

// For the debug "stats" command: what the screen is doing ("playing 41 s, hd 720x1280 FLV", "waiting", ...)
+ (NSString *)debugState;

@end
