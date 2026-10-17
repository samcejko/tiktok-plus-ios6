#import <UIKit/UIKit.h>

// Opens what a TikTok link points to: a video or photo post (resolved, then shown full screen), a creator's profile,
// a live room. Short links (vm.tiktok.com, vt.tiktok.com, /t/...) are expanded by the helper first. Used by the
// "Open a link" menu, the tikie: URL scheme and links handed over by other apps (Surfari).
@interface TKLinkRouter : NSObject

+ (BOOL)openLink:(NSString *)link;                                  // NO when it is not a TikTok link at all
+ (void)openVideoId:(NSString *)videoId author:(NSString *)author;
+ (void)openLiveRoom:(NSString *)roomId;

// A web link tapped in a text (a caption, a comment, a bio; NSString or NSURL): a TikTok link opens inside the app,
// one to YouTube, Twitch or Kick is offered to the sister app, anything else goes to a browser - iOS 6 asks which
// (TKExternalOpen). `controller` and `anchor` are where a sheet is shown (nil: the screen on top). The debug command
// tikie:link?url= runs this very path.
+ (void)openWebLink:(id)link from:(UIViewController *)controller anchor:(UIView *)anchor;
// The links of one text: a single one opens at once, several are listed in a sheet first
+ (void)openWebLinks:(NSArray *)links from:(UIViewController *)controller anchor:(UIView *)anchor;

// Pages (they slide in over the feed, one stack: see TKPageNavigationController)
+ (void)openProfile:(NSString *)handle;
+ (void)openHashtag:(NSString *)name;
+ (void)openSound:(NSString *)soundId title:(NSString *)title;
+ (void)openSearch:(NSString *)query;                               // nil: the empty search page
// A list of videos full screen, starting at one of them; loadMore (may be nil) brings what follows the `have`
// videos the list has, near its end (done(nil): nothing more)
+ (void)openVideos:(NSArray *)videos startIndex:(NSInteger)index title:(NSString *)title
          loadMore:(void (^)(NSUInteger have, void (^done)(NSArray *more)))loadMore;

+ (UIViewController *)topController;                               // what is on screen (the one to present from)
+ (void)presentInNavigation:(UIViewController *)controller;         // a sheet (form sheet on the iPad) with a bar

@end
