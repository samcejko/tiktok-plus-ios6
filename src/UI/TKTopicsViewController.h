#import <UIKit/UIKit.h>

// "What do you enjoy?": TikTok's topics as buttons to pick a few of, so the feed hits the mark from the first
// videos; it goes on learning from how you watch. Shown once at the first start, and from the settings.
@interface TKTopicsViewController : UIViewController
@property (nonatomic, copy) dispatch_block_t onPicked;      // after topics were picked (not after "Skip")
@end
