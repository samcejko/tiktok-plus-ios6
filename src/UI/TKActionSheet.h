#import <UIKit/UIKit.h>

// Native iOS 6 popovers; the same delegate/index contract with classic artwork on newer iOS.
@interface TKActionSheet : UIActionSheet
+ (void)options:(NSArray *)options title:(NSString *)title inView:(UIView *)view selection:(void (^)(NSInteger index))selection;
@end
