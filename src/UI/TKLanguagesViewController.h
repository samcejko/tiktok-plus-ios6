#import <UIKit/UIKit.h>

// Which caption languages the feed shows: a checklist (all on by default). TikTok guesses a video's language from its
// caption; videos without a caption have a row of their own, and so do all the languages not in the list.
@interface TKLanguagesViewController : UITableViewController
+ (NSString *)nameOfLanguage:(NSString *)code;      // "čeština" / "No caption" / "Other languages"
@end
