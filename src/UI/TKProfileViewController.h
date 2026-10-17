#import "TKGridViewController.h"

// A creator's page: avatar, name, counts (following, followers, likes), bio and link, then a grid of their posts
// that pages on as you scroll (tap one: they play full screen, and you can swipe on through the rest). While they
// are live, a button opens the stream. Supports follow/unfollow when signed in with writes enabled.
@interface TKProfileViewController : TKGridViewController
- (instancetype)initWithHandle:(NSString *)handle;
@property (nonatomic, copy, readonly) NSString *handle;
@end
