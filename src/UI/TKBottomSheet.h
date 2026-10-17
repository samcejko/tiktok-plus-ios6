#import <UIKit/UIKit.h>

// A panel that slides up from the bottom over part of the screen, as TikTok shows its comments: a grabber, a title
// and a close button over the content. Dragging the top down, a tap above the panel or the button closes it. The
// screen behind stays live (the video plays on above it).
@interface TKBottomSheet : UIView
@property (nonatomic, copy) NSString *title;
@property (nonatomic, strong, readonly) UIView *contentView;   // the content goes in here
@property (nonatomic) CGFloat heightFraction;                   // of the host's height (default 0.68)
@property (nonatomic, copy) dispatch_block_t onClose;           // once it has gone
- (void)showInView:(UIView *)host;
- (void)close;
@end
