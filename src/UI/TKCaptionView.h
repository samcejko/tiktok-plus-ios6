#import <UIKit/UIKit.h>

// The caption under a video: white text with its #hashtags, @mentions and web links in bold, drawn with CoreText so
// that a tap can tell which of them it hit (a UILabel cannot). At most maxLines lines; the last one ends in "…" when
// there is more. It takes no touches itself: the page asks -linkAtPoint: on its own tap.
@interface TKCaptionView : UIView
@property (nonatomic, copy) NSString *text;
@property (nonatomic, strong) UIFont *font;
@property (nonatomic) NSUInteger maxLines;        // 0 = no limit
- (CGSize)sizeThatFits:(CGSize)size;
- (NSString *)linkAtPoint:(CGPoint)point;         // "tag:<name>", "user:<handle>" or "url:<link>", nil when the point hits none
@end
