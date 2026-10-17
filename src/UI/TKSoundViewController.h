#import "TKGridViewController.h"

// A sound's page: its cover, title and author, a button to hear it, and a grid of the videos that use it
@interface TKSoundViewController : TKGridViewController
- (instancetype)initWithSoundId:(NSString *)soundId title:(NSString *)title;
@end
