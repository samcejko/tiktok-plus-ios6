#import <UIKit/UIKit.h>

// The videos you saved for yourself. Tap one to watch; swipe to remove.
@interface TKSavedViewController : UITableViewController
- (instancetype)initWithHistory:(BOOL)history;
@end
