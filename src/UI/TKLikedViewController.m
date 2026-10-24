#import "TKLikedViewController.h"
#import "TKTikTok.h"
#import "TKCommon.h"
#import "TKSession.h"

@implementation TKLikedViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = L(@"Liked videos");
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reload) name:TKSessionDidChangeNotification object:nil];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (NSString *)feedTitle { return L(@"Liked"); }
- (NSString *)emptyMessage { return L(@"No liked videos."); }

- (TKHTTPTask *)fetchPageAfterFirst:(BOOL)more completion:(void (^)(NSArray *, BOOL, NSError *))completion
{
    return [TKTikTok likedVideosWithCount:30 completion:^(NSArray *videos, NSError *error) {
        completion(videos, NO, error);
    }];
}

@end
