#import <UIKit/UIKit.h>
@interface TKCollectionsViewController : UITableViewController
- (void)showActionsForRow:(NSUInteger)row;
@end
@interface TKCollectionPicker : NSObject
+ (void)addVideo:(NSDictionary *)video inView:(UIView *)view completion:(void (^)(BOOL saved))completion;
@end
