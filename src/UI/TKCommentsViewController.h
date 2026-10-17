#import <UIKit/UIKit.h>
@class TKVideo;

// Read-only comments for one video (from the Pi helper, best effort): the commenter's picture and name (both open
// their profile), the text, when, and the likes; a comment's replies come on a tap. Three forms: a sheet with a Done
// button, the content of the bottom sheet over the feed, and the side panel of the feed on a landscape iPad (that
// one follows the page on screen).
@interface TKCommentsViewController : UITableViewController
- (instancetype)initWithVideo:(TKVideo *)video;
- (instancetype)initForBottomSheetWithVideo:(TKVideo *)video;
- (instancetype)initAsPanel;
- (void)showVideo:(TKVideo *)video;          // (the panel) switch to another video's comments
@end
