#import <UIKit/UIKit.h>
#import "TKModels.h"

@class TKVideoCell;

@protocol TKVideoCellDelegate <NSObject>
- (void)videoCellDidTapSave:(TKVideoCell *)cell;
- (void)videoCellDidTapComments:(TKVideoCell *)cell;
- (void)videoCellDidReachEnd:(TKVideoCell *)cell;        // one loop finished (for auto-advance / completion)
- (void)videoCellDidDoubleTap:(TKVideoCell *)cell;       // double tap = save (the cell shows the star burst itself)
- (void)videoCell:(TKVideoCell *)cell didLongPressAt:(CGPoint)point;   // hold = the video's menu
@optional
- (void)videoCellWasTouched:(TKVideoCell *)cell;        // pause/play or seeking: someone is watching
- (void)videoCellDidTapAuthor:(TKVideoCell *)cell;      // the name, the avatar or a swipe to the left: the profile
- (void)videoCellDidTapLive:(TKVideoCell *)cell;        // the avatar while the creator is live: their stream
- (void)videoCell:(TKVideoCell *)cell didTapLink:(NSString *)link;   // in the caption: "tag:<name>", "user:<handle>", "url:<link>"
- (void)videoCellDidTapSound:(TKVideoCell *)cell;       // the music line or the spinning disc: the sound's page
@end

// One full-screen video page: AVPlayer behind, cover art until the first frame, the author/caption overlay (its
// #hashtags and @mentions open their pages, its web links open where they lead), TikTok's captions, the right-hand
// buttons with the sound's disc and a scrubber along the bottom edge. Gestures: tap = pause/play, double tap = save, hold = menu, swipe left = the
// creator's profile, drag sideways along the bottom = seek. The feed controller owns resolve; the cell just plays.
@interface TKVideoCell : UIView
@property (nonatomic, weak) id<TKVideoCellDelegate> delegate;
@property (nonatomic, readonly) TKVideo *video;
@property (nonatomic, readonly) BOOL playing;
@property (nonatomic, readonly) NSTimeInterval playedSeconds;   // furthest position reached
@property (nonatomic, readonly) NSTimeInterval duration;        // the item's length, else the video's listed one
@property (nonatomic, readonly) NSTimeInterval currentTime;     // the player's position
@property (nonatomic, readonly) BOOL fastPlayback;

- (void)showVideo:(TKVideo *)video;         // labels + cover; no network yet
- (void)preparePlayback;                    // off screen: buffers the start (no picture yet) so the swipe starts at once
- (void)startPlaybackMuted:(BOOL)muted;     // needs video.playURL; plays (reusing the prepared player), looping
- (void)setActive:(BOOL)active;             // the visible page plays; others pause (and go back to the start)
- (void)setActive:(BOOL)active rewind:(BOOL)rewind;   // covered by a page or a stream: it waits where it is
- (void)wakeUp;                             // the app is in front again: a page that should play, plays
- (void)setMuted:(BOOL)muted;
@property (nonatomic, readonly) BOOL hasCaptions;     // TikTok made captions for this video
- (void)captionsSettingChanged;
- (BOOL)setFastPlayback:(BOOL)fast;         // 2x speed; NO when this video cannot play faster
- (NSTimeInterval)takeWatchedSeconds;       // real viewing time since the last call (loops add up, seeks do not)
- (void)updateSavedState:(BOOL)saved;
- (void)showError:(NSString *)message;
- (void)showToast:(NSString *)message;      // a short note in the middle that fades
- (UIView *)linkAnchorView;                 // the caption: where a sheet for a link of this page points on the iPad
- (void)teardown;

// For the debug URL commands: the gestures' actions without a finger
- (void)simulateDoubleTap;
- (void)simulateLongPress;
- (void)simulateScrubTo:(CGFloat)fraction;
- (float)playerRate;
- (NSString *)debugPhotoState;
@end
