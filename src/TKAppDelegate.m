#import "TKAppDelegate.h"
#import "TKFeedViewController.h"
#import "TKPageNavigationController.h"
#import "TKLivePlayerViewController.h"
#import "TKVideoCell.h"
#import "TKTaste.h"
#import "TKLinkRouter.h"
#import "TKTikTok.h"
#import "TKModels.h"
#import "TKMediaProxy.h"
#import "TKTLSSocket.h"
#import "TKImageLoader.h"
#import "TKSettings.h"
#import "TKTheme.h"
#import "TKUtils.h"
#import "TKModern.h"
#import "TKCommon.h"
#include <dlfcn.h>
#include <signal.h>
#include <mach/mach.h>

static BOOL TKButtonMatches(UIButton *button, NSString *text)
{
    for (NSString *name in @[ button.currentTitle ?: @"", button.accessibilityLabel ?: @"" ])
        if (name.length && [name rangeOfString:text options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    return NO;
}

static BOOL TKViewContainsText(UIView *view, NSString *text)
{
    if ([view isKindOfClass:[UILabel class]]) {
        NSString *s = ((UILabel *)view).text;
        return s.length && [s rangeOfString:text options:NSCaseInsensitiveSearch].location != NSNotFound;
    }
    for (UIView *sub in view.subviews) { if ([sub isKindOfClass:[UIControl class]]) continue; if (TKViewContainsText(sub, text)) return YES; }
    return NO;
}

static BOOL TKPressView(UIView *v, NSString *text)
{
    if ([v isKindOfClass:[UIButton class]]) {
        if (!TKButtonMatches((UIButton *)v, text)) return NO;
        [(UIButton *)v sendActionsForControlEvents:UIControlEventTouchUpInside];
        return YES;
    }
    if ([v isKindOfClass:[UITableViewCell class]]) {
        UITableViewCell *cell = (UITableViewCell *)v;
        if (!TKViewContainsText(cell, text)) return NO;
        UIView *table = cell.superview;
        while (table && ![table isKindOfClass:[UITableView class]]) table = table.superview;
        NSIndexPath *ip = [(UITableView *)table indexPathForCell:cell];
        id<UITableViewDelegate> delegate = [(UITableView *)table delegate];
        if (!ip || ![delegate respondsToSelector:@selector(tableView:didSelectRowAtIndexPath:)]) return NO;
        [delegate tableView:(UITableView *)table didSelectRowAtIndexPath:ip];
        return YES;
    }
    return NO;
}

@implementation TKAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    signal(SIGPIPE, SIG_IGN);
    [TKSettings registerDefaults];
    TKLog(@"Tikie %@ starting on %@ (iOS %@)", [TKUtils appVersion], [TKUtils deviceModel], [UIDevice currentDevice].systemVersion);
    // iOS 7 and newer (the arm64 build): the iOS 6 look of the bars, full-screen modals; nothing on iOS 6
    TKModernSetUp([[TKTheme shared] barStyle]);
    [TKTLSSocket warmUp];
    [[TKImageLoader shared] pruneDisk];

    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.feed = [[TKFeedViewController alloc] init];
    self.window.rootViewController = self.feed;
    self.window.backgroundColor = [UIColor blackColor];
    [self.window makeKeyAndVisible];
    [application setStatusBarStyle:UIStatusBarStyleBlackOpaque animated:NO];
    return YES;
}

- (UIViewController *)topController
{
    UIViewController *top = self.window.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    if ([top isKindOfClass:[UINavigationController class]]) top = [(UINavigationController *)top topViewController];
    return top;
}

// tiktak:open?url=<a TikTok link> (how Surfari hands links over), tiktak:play/<id>, tiktak:user/<handle>,
// tiktak:live/<room>, tiktak:tag/<hashtag>, tiktak:sound/<id>, tiktak:search?q=, tiktak:server?url=&key=, and plain
// tiktok.com links; tikie: (the app's first name) works the same. Debug commands (need Documents/debug): snapshot,
// screen, press?title=/n=/item=, back, stats, swipe[?dir=down], saved[?clear=1], taste[?reset=1],
// gesture?type=double|hold|scrub[&f=]|pos|comments, lang?set=en|cs|system, link?url=<percent-encoded web link>.
- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation
{
    NSString *s = url.absoluteString ?: @"";
    NSString *lower = [s lowercaseString];
    if ([lower hasPrefix:@"http://"] || [lower hasPrefix:@"https://"]) return [TKLinkRouter openLink:s];
    NSString *scheme = [lower hasPrefix:@"tiktak:"] ? @"tiktak:" : [lower hasPrefix:@"tikie:"] ? @"tikie:" : nil;
    if (!scheme) return NO;
    NSString *target = [s substringFromIndex:scheme.length];
    while ([target hasPrefix:@"/"]) target = [target substringFromIndex:1];
    NSString *query = nil;
    NSRange q = [target rangeOfString:@"?"];
    if (q.location != NSNotFound) { query = [target substringFromIndex:q.location + 1]; target = [target substringToIndex:q.location]; }
    NSDictionary *params = query.length ? [TKUtils parseQuery:query] : @{};
    if ([target hasPrefix:@"play/"]) { [TKLinkRouter openVideoId:[target substringFromIndex:@"play/".length] author:nil]; return YES; }
    if ([target hasPrefix:@"user/"]) { [TKLinkRouter openProfile:[target substringFromIndex:@"user/".length]]; return YES; }
    if ([target hasPrefix:@"live/"]) { [TKLinkRouter openLiveRoom:[target substringFromIndex:@"live/".length]]; return YES; }
    if ([target hasPrefix:@"tag/"]) {
        NSString *tag = [target substringFromIndex:@"tag/".length];
        [TKLinkRouter openHashtag:[tag stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding] ?: tag];
        return YES;
    }
    if ([target hasPrefix:@"sound/"]) { [TKLinkRouter openSound:[target substringFromIndex:@"sound/".length] title:nil]; return YES; }
    if ([target isEqualToString:@"search"]) { [TKLinkRouter openSearch:params[@"q"]]; return YES; }
    if ([target isEqualToString:@"open"] && [params[@"url"] length]) {
        if (![TKLinkRouter openLink:params[@"url"]]) [TKUtils alertWithTitle:L(@"Open a link") message:L(@"That does not look like a TikTok link.")];
        return YES;
    }
    // tikie:server?url=<base>&key=<key> - set the helper address (also how you hand the app to other people)
    if ([target isEqualToString:@"server"]) {
        if ([params[@"url"] length]) [TKSettings setServerBaseURL:params[@"url"]];
        if (params[@"key"]) [TKSettings setServerKey:params[@"key"]];
        [TKUtils alertWithTitle:L(@"Settings") message:[TKSettings serverBaseURL].length ? [NSString stringWithFormat:@"%@%@", [TKSettings serverBaseURL], [TKSettings serverKey].length ? L(@" (key set)") : @""] : L(@"Not set")];
        return YES;
    }

    BOOL debug = [[NSFileManager defaultManager] fileExistsAtPath:[[TKUtils documentsPath] stringByAppendingPathComponent:@"debug"]];
    if (!debug) return YES;
    UIViewController *top = [self topController];
    if ([target isEqualToString:@"stats"]) {
        struct task_basic_info info; mach_msg_type_number_t count = TASK_BASIC_INFO_COUNT;
        if (task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t)&info, &count) == KERN_SUCCESS)
            TKLog(@"Memory: %.1f MB resident", info.resident_size / 1048576.0);
        TKLog(@"Top: %@, server %@ (%@), saved %lu, hidden languages %@, proxy %@", NSStringFromClass([top class]), [TKSettings serverBaseURL],
              [TKSettings serverKey].length ? @"keyed" : @"no key", (unsigned long)[TKSettings savedVideos].count,
              [[TKSettings hiddenLanguages] componentsJoinedByString:@","], [[TKMediaProxy shared] statsDescription]);
        TKLog(@"Live: %@", [TKLivePlayerViewController debugState]);
        return YES;
    }
    if ([target isEqualToString:@"proxylog"]) { [TKMediaProxy shared].logRequests = ![params[@"on"] isEqualToString:@"0"]; return YES; }
    // link?url=<a web link, percent-encoded>: exactly what a tap on that link in a caption, a comment or a bio does
    // (a TikTok link opens here, the rest through the chooser of TKExternalOpen), so the sheet can be snapshotted
    if ([target isEqualToString:@"link"]) {
        NSString *link = params[@"url"];
        if (link.length) [TKLinkRouter openWebLink:link from:top anchor:nil];
        TKLog(@"Link %@: %@", link ?: @"", link.length ? @"opened as a tapped link" : @"no url given");
        return YES;
    }
    // lang?set=en|cs|system: the app's own language, for checking both (the device's stays); it applies from the next
    // launch, so the app quits
    if ([target isEqualToString:@"lang"]) {
        NSString *set = params[@"set"] ?: @"system";
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        if ([set isEqualToString:@"system"]) [d removeObjectForKey:@"AppleLanguages"];
        else [d setObject:@[ set ] forKey:@"AppleLanguages"];
        [d synchronize];
        TKLog(@"Language %@ from the next launch: quitting", set);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ exit(0); });
        return YES;
    }
    if ([target isEqualToString:@"snapshot"] || [target isEqualToString:@"screen"]) {
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"screen.png"];
        BOOL ok = NO;
        if ([target isEqualToString:@"screen"]) {
            CGImageRef (*grab)(void) = (CGImageRef (*)(void))dlsym(RTLD_DEFAULT, "UIGetScreenImage");
            CGImageRef shot = grab ? grab() : NULL;
            if (shot) { ok = [UIImagePNGRepresentation([UIImage imageWithCGImage:shot]) writeToFile:path atomically:YES]; CGImageRelease(shot); }
        } else {
            CGSize size = [UIScreen mainScreen].bounds.size;
            UIGraphicsBeginImageContextWithOptions(size, YES, 1.0);
            for (UIWindow *w in [UIApplication sharedApplication].windows) if (!w.hidden && w.alpha > 0) [w.layer renderInContext:UIGraphicsGetCurrentContext()];
            ok = [UIImagePNGRepresentation(UIGraphicsGetImageFromCurrentImageContext()) writeToFile:path atomically:YES];
            UIGraphicsEndImageContext();
        }
        TKLog(@"%@ %@: %@", target, ok ? @"written" : @"failed", path);
        return YES;
    }
    if ([target isEqualToString:@"press"]) {
        NSString *byTitle = params[@"title"];
        NSInteger n = [params[@"n"] integerValue];
        BOOL gridItem = params[@"item"] != nil;   // press?item=N: the Nth post of a grid (a profile)
        if (gridItem) n = [params[@"item"] integerValue];
        // the screen on top first: a covered screen underneath can have a button with the same label
        NSMutableArray *views = [NSMutableArray array];
        UIView *topView = top.navigationController.view ?: top.view;
        if (topView) [views addObject:topView];
        for (UIWindow *w in [UIApplication sharedApplication].windows) [views addObject:w];
        BOOL pressed = NO;
        for (NSUInteger i = 0; i < views.count && !pressed; i++) {
            UIView *v = views[i];
            if (gridItem && [v isKindOfClass:[UICollectionView class]]) {
                UICollectionView *grid = (UICollectionView *)v;
                NSIndexPath *ip = [NSIndexPath indexPathForItem:n inSection:0];
                if (grid.numberOfSections > 0 && n < [grid numberOfItemsInSection:0] && [grid.delegate respondsToSelector:@selector(collectionView:didSelectItemAtIndexPath:)]) {
                    [grid.delegate collectionView:grid didSelectItemAtIndexPath:ip];
                    pressed = YES;
                }
            } else if (gridItem) {
                [views addObjectsFromArray:v.subviews];
            } else if (!byTitle.length && [v isKindOfClass:[UIActionSheet class]] && ((UIActionSheet *)v).visible) {
                UIActionSheet *sheet = (UIActionSheet *)v;
                if ([sheet.delegate respondsToSelector:@selector(actionSheet:clickedButtonAtIndex:)]) [sheet.delegate actionSheet:sheet clickedButtonAtIndex:n];
                [sheet dismissWithClickedButtonIndex:n animated:NO];
                pressed = YES;
            } else if (!byTitle.length && [v isKindOfClass:[UIAlertView class]] && ((UIAlertView *)v).visible) {
                UIAlertView *alert = (UIAlertView *)v;
                if ([alert.delegate respondsToSelector:@selector(alertView:clickedButtonAtIndex:)]) [alert.delegate alertView:alert clickedButtonAtIndex:n];
                [alert dismissWithClickedButtonIndex:n animated:NO];
                pressed = YES;
            } else if (byTitle.length && !v.hidden && TKPressView(v, byTitle)) {
                pressed = YES;
            } else {
                [views addObjectsFromArray:v.subviews];
            }
        }
        TKLog(@"Press %@: %@", query ?: @"", pressed ? @"done" : @"nothing found");
        return YES;
    }
    if ([target isEqualToString:@"swipe"]) {
        // move the feed by one page (up = next). The feed listens to its scroll view; nudge it directly.
        for (UIScrollView *sv in [self scrollViewsIn:top.view]) {
            if (sv.contentSize.height > sv.bounds.size.height + 1) {
                CGFloat dir = [params[@"dir"] isEqualToString:@"down"] ? -1 : 1;
                CGFloat y = MAX(0, MIN(sv.contentSize.height - sv.bounds.size.height, sv.contentOffset.y + dir * sv.bounds.size.height));
                [sv setContentOffset:CGPointMake(0, y) animated:YES];
                break;
            }
        }
        return YES;
    }
    if ([target isEqualToString:@"rotate"]) {
        // (debug only, for testing without turning the iPad: a private UIDevice method turns the interface)
        NSInteger o = [params[@"o"] isEqualToString:@"landscape"] ? UIInterfaceOrientationLandscapeLeft : UIInterfaceOrientationPortrait;
        SEL sel = NSSelectorFromString(@"setOrientation:");
        if ([[UIDevice currentDevice] respondsToSelector:sel]) {
            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:[UIDevice instanceMethodSignatureForSelector:sel]];
            inv.selector = sel;
            inv.target = [UIDevice currentDevice];
            [inv setArgument:&o atIndex:2];
            [inv invoke];
        }
        TKLog(@"Rotate to %@: interface now %ld", params[@"o"], (long)[UIApplication sharedApplication].statusBarOrientation);
        return YES;
    }
    if ([target isEqualToString:@"saved"]) {
        if ([params[@"clear"] isEqualToString:@"1"]) for (NSDictionary *d in [TKSettings savedVideos]) [TKSettings unsaveVideo:TKStr(d[@"id"])];
        TKLog(@"Saved videos: %lu", (unsigned long)[TKSettings savedVideos].count);
        return YES;
    }
    if ([target isEqualToString:@"taste"]) {
        if ([params[@"reset"] isEqualToString:@"1"]) [[TKTaste shared] reset];
        TKLog(@"%@", [[TKTaste shared] summary]);
        return YES;
    }
    // the gestures' actions on the page on screen: double (save), hold (menu), scrub&f=0.5 (seek to half)
    if ([target isEqualToString:@"gesture"]) {
        TKVideoCell *cell = [top isKindOfClass:[TKFeedViewController class]] ? [(TKFeedViewController *)top currentCell] : nil;
        NSString *type = params[@"type"];
        if (!cell) TKLog(@"Gesture %@: no video page on screen", type);
        else if ([type isEqualToString:@"double"]) [cell simulateDoubleTap];
        else if ([type isEqualToString:@"hold"]) [cell simulateLongPress];
        else if ([type isEqualToString:@"scrub"]) [cell simulateScrubTo:(CGFloat)[params[@"f"] doubleValue]];
        else if ([type isEqualToString:@"comments"]) [cell.delegate videoCellDidTapComments:cell];
        if (cell) TKLog(@"Gesture %@ done: %@ at %.1f / %.1f s, rate %.2f, 2x %d, saved %d | %@", type, cell.video.videoId, cell.currentTime, cell.duration,
                        [cell playerRate], cell.fastPlayback, [TKSettings isSaved:cell.video.videoId], [cell debugPhotoState]);
        return YES;
    }
    if ([target isEqualToString:@"back"]) {
        TKPageNavigationController *stack = [TKPageNavigationController visibleStack];
        if (stack) [stack goBack];
        else if (top != self.feed && [self topController].presentingViewController) [[self topController] dismissViewControllerAnimated:YES completion:nil];
        return YES;
    }
    return YES;
}

- (NSArray *)scrollViewsIn:(UIView *)view
{
    NSMutableArray *out = [NSMutableArray array];
    NSMutableArray *stack = [NSMutableArray arrayWithObject:view];
    while (stack.count) { UIView *v = stack.lastObject; [stack removeLastObject]; if ([v isKindOfClass:[UIScrollView class]]) [out addObject:v]; [stack addObjectsFromArray:v.subviews]; }
    return out;
}

- (void)applicationWillEnterForeground:(UIApplication *)application { [[TKMediaProxy shared] ensureRunning]; }
- (void)applicationDidEnterBackground:(UIApplication *)application { [TKSettings save]; }

@end
