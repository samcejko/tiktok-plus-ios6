#import "TKGridViewController.h"

// A hashtag's page: its name and counts over a grid of its videos (TikTok's own list, paging on as you scroll)
@interface TKHashtagViewController : TKGridViewController
- (instancetype)initWithName:(NSString *)name;   // without the #
@end
