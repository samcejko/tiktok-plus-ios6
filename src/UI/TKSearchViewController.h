#import <UIKit/UIKit.h>

// Search: TikTok's suggestions while typing and the recent searches, then the results in four tabs - videos (a grid
// that pages on), creators, hashtags and sounds (what TikTok names first, the exact match, and what the videos
// found carry). "#name" opens a hashtag and "@name" a creator straight away.
@interface TKSearchViewController : UIViewController
- (instancetype)initWithQuery:(NSString *)query;     // nil: an empty search, the keyboard comes up
- (void)searchFor:(NSString *)query;
@end
