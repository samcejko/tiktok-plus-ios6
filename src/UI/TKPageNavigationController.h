#import <UIKit/UIKit.h>

// The pages over the feed - a creator, a hashtag, a sound, search, and the videos opened from them - as one stack:
// a full-screen navigation controller that slides in from the side (iOS 6 has no such modal transition, so the
// window does the slide). Its first page gets a real back button; going back from it closes the whole stack and
// the feed goes on where it was. A video list in the stack hides the bar.
@interface TKPageNavigationController : UINavigationController

// Pushes onto the stack on screen, or opens a new stack over whatever is on screen
+ (void)showPage:(UIViewController *)page;
// The stack on screen (nil when none is on top)
+ (TKPageNavigationController *)visibleStack;

- (void)closeAnimated:(BOOL)animated;
// Back one page; from the first page the stack closes
- (void)goBack;

@end
