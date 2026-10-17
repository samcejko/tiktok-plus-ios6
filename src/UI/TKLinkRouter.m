#import "TKLinkRouter.h"
#import "TKFeedViewController.h"
#import "TKProfileViewController.h"
#import "TKHashtagViewController.h"
#import "TKSoundViewController.h"
#import "TKSearchViewController.h"
#import "TKPageNavigationController.h"
#import "TKLivePlayerViewController.h"
#import "TKExternalOpen.h"
#import "TKTikTok.h"
#import "TKModels.h"
#import "TKTheme.h"
#import "TKUtils.h"
#import "TKCommon.h"

#pragma mark - The sheet that lists the links of a text

// Its delegate: UIActionSheet does not retain it, so it keeps itself in g_choices until the sheet is gone. The chosen
// link opens once the sheet has gone (what it opens may be a sheet itself), not under it.
@interface TKLinkChoice : NSObject <UIActionSheetDelegate>
@property (nonatomic, strong) NSArray *links;
@property (nonatomic, weak) UIViewController *controller;
@property (nonatomic, weak) UIView *anchor;
@property (nonatomic) NSInteger chosen;        // -1: none
@end

static NSMutableArray *g_choices;

@implementation TKLinkChoice

- (instancetype)init
{
    if ((self = [super init])) _chosen = -1;
    return self;
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index
{
    self.chosen = (index >= 0 && index != sheet.cancelButtonIndex && index < (NSInteger)self.links.count) ? index : -1;
}

- (void)actionSheet:(UIActionSheet *)sheet didDismissWithButtonIndex:(NSInteger)index
{
    sheet.delegate = nil;
    if (self.chosen >= 0) [TKLinkRouter openWebLink:self.links[(NSUInteger)self.chosen] from:self.controller anchor:self.anchor];
    TKLinkChoice *me = self;
    dispatch_async(dispatch_get_main_queue(), ^{ [g_choices removeObject:me]; });
}

@end

@implementation TKLinkRouter

+ (UIViewController *)topController
{
    UIViewController *top = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    return top;
}

+ (void)presentInNavigation:(UIViewController *)controller
{
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:controller];
    [[TKTheme shared] applyToNavigationBar:nav.navigationBar];
    if (TKIsPad()) nav.modalPresentationStyle = UIModalPresentationFormSheet;
    [[self topController] presentViewController:nav animated:YES completion:nil];
}

+ (void)busy:(BOOL)busy { [UIApplication sharedApplication].networkActivityIndicatorVisible = busy; }

// The digits that follow `marker` in `s` ("/video/123..." -> "123..."), nil when there are none
+ (NSString *)digitsAfter:(NSString *)marker in:(NSString *)s
{
    NSRange r = [s rangeOfString:marker];
    if (r.location == NSNotFound) return nil;
    NSMutableString *d = [NSMutableString string];
    for (NSUInteger i = r.location + r.length; i < s.length; i++) {
        unichar c = [s characterAtIndex:i];
        if (c < '0' || c > '9') break;
        [d appendFormat:@"%C", c];
    }
    return d.length >= 6 ? d : nil;
}

// "@handle" in a path ("/@name/video/1" -> "name")
+ (NSString *)handleIn:(NSString *)path
{
    NSRange at = [path rangeOfString:@"/@"];
    if (at.location == NSNotFound) return nil;
    NSString *rest = [path substringFromIndex:at.location + 2];
    NSString *handle = [[rest componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/?#"]] firstObject];
    return handle.length ? handle : nil;
}

+ (BOOL)openLink:(NSString *)link { return [self openLink:link expanded:NO]; }

+ (BOOL)openLink:(NSString *)link expanded:(BOOL)expanded
{
    NSString *s = [link stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
    if (!s.length) return NO;
    // a bare video id
    NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    if (s.length >= 6 && [s rangeOfCharacterFromSet:nonDigits].location == NSNotFound) { [self openVideoId:s author:nil]; return YES; }
    if ([[s lowercaseString] rangeOfString:@"tiktok.com"].location == NSNotFound) return NO;
    if (![[s lowercaseString] hasPrefix:@"http"]) s = [@"https://" stringByAppendingString:s];
    NSURL *url = [NSURL URLWithString:s];
    NSString *host = [url.host lowercaseString] ?: @"";
    NSString *path = url.path ?: @"";
    if (![host isEqualToString:@"tiktok.com"] && ![host hasSuffix:@".tiktok.com"]) return NO;

    // short links lead somewhere else: ask the helper where (once)
    BOOL shortLink = [host hasPrefix:@"vm."] || [host hasPrefix:@"vt."] || [path hasPrefix:@"/t/"];
    if (shortLink && !expanded) {
        [self busy:YES];
        [TKTikTok expandLink:s completion:^(NSString *target, NSError *error) {
            [self busy:NO];
            if (!target.length || ![self openLink:target expanded:YES])
                [TKUtils alertWithTitle:L(@"Open a link") message:error.localizedDescription ?: L(@"That does not look like a TikTok link.")];
        }];
        return YES;
    }
    NSString *handle = [self handleIn:path];
    NSString *vid = [self digitsAfter:@"/video/" in:path] ?: [self digitsAfter:@"/photo/" in:path];
    if (vid) { [self openVideoId:vid author:handle]; return YES; }
    // tiktok.com/tag/<name>, /music/<title>-<id>, /search?q=
    NSArray *parts = [[path stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]] componentsSeparatedByString:@"/"];
    if (parts.count >= 2 && [[parts[0] lowercaseString] isEqualToString:@"tag"] && [parts[1] length]) {
        [self openHashtag:[parts[1] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding] ?: parts[1]];
        return YES;
    }
    if (parts.count >= 2 && [[parts[0] lowercaseString] isEqualToString:@"music"]) {
        NSString *slug = parts[1];
        NSRange dash = [slug rangeOfString:@"-" options:NSBackwardsSearch];
        NSString *soundId = dash.location != NSNotFound ? [slug substringFromIndex:dash.location + 1] : slug;
        if ([soundId rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location == NSNotFound && soundId.length >= 6) {
            [self openSound:soundId title:nil];
            return YES;
        }
    }
    if (parts.count >= 1 && [[parts[0] lowercaseString] isEqualToString:@"search"]) {
        [self openSearch:TKStr([TKUtils parseQuery:url.query ?: @""][@"q"])];
        return YES;
    }
    if (handle && [[[path lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]] hasSuffix:@"/live"]) {
        [self openLiveOf:handle];
        return YES;
    }
    if (handle) { [self openProfile:handle]; return YES; }
    return NO;
}

// "tiktok.com/@name/live": the room comes from their profile; when they are not live, the profile itself
+ (void)openLiveOf:(NSString *)handle
{
    [self busy:YES];
    [TKTikTok profileForUser:handle completion:^(TKProfile *profile, NSError *error) {
        [self busy:NO];
        if (profile.liveRoom.length) { [self openLiveRoom:profile.liveRoom]; return; }
        [self openProfile:handle];
        if (profile) [TKUtils alertWithTitle:L(@"Live now") message:[NSString stringWithFormat:L(@"@%@ is not live right now."), profile.handle.length ? profile.handle : handle]];
    }];
}

+ (void)openVideoId:(NSString *)videoId author:(NSString *)author
{
    [self busy:YES];
    [TKTikTok resolveId:videoId author:author completion:^(TKVideo *resolved, NSError *error) {
        [self busy:NO];
        if (!resolved) { [TKUtils alertWithTitle:L(@"Open a link") message:error.localizedDescription ?: L(@"This video could not be loaded.")]; return; }
        [self openVideos:@[ resolved ] startIndex:0 title:resolved.author.length ? [@"@" stringByAppendingString:resolved.author] : L(@"Video") loadMore:nil];
    }];
}

+ (void)openVideos:(NSArray *)videos startIndex:(NSInteger)index title:(NSString *)title loadMore:(void (^)(NSUInteger, void (^)(NSArray *)))loadMore
{
    if (!videos.count) return;
    TKFeedViewController *feed = [[TKFeedViewController alloc] initWithVideos:videos startIndex:index title:title];
    feed.loadMore = loadMore;
    [TKPageNavigationController showPage:feed];
}

+ (void)openProfile:(NSString *)handle
{
    if ([handle hasPrefix:@"@"]) handle = [handle substringFromIndex:1];
    if (!handle.length) return;
    // from that very creator's page (their video opened from it): back to the page rather than a second copy
    TKPageNavigationController *stack = [TKPageNavigationController visibleStack];
    NSArray *pages = stack.viewControllers;
    if (pages.count >= 2) {
        UIViewController *below = pages[pages.count - 2];
        if ([below isKindOfClass:[TKProfileViewController class]] &&
            [[(TKProfileViewController *)below handle] caseInsensitiveCompare:handle] == NSOrderedSame) {
            [stack popViewControllerAnimated:YES];
            return;
        }
    }
    [TKPageNavigationController showPage:[[TKProfileViewController alloc] initWithHandle:handle]];
}

+ (void)openHashtag:(NSString *)name
{
    NSString *tag = [[name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"#"]];
    if (!tag.length) return;
    [TKPageNavigationController showPage:[[TKHashtagViewController alloc] initWithName:tag]];
}

+ (void)openSound:(NSString *)soundId title:(NSString *)title
{
    if (!soundId.length) return;
    [TKPageNavigationController showPage:[[TKSoundViewController alloc] initWithSoundId:soundId title:title]];
}

+ (void)openSearch:(NSString *)query
{
    TKPageNavigationController *stack = [TKPageNavigationController visibleStack];
    if ([stack.topViewController isKindOfClass:[TKSearchViewController class]]) {   // (already searching: search again)
        if (query.length) [(TKSearchViewController *)stack.topViewController searchFor:query];
        return;
    }
    [TKPageNavigationController showPage:[[TKSearchViewController alloc] initWithQuery:query]];
}

+ (void)openLiveRoom:(NSString *)roomId
{
    NSString *digits = [[roomId componentsSeparatedByCharactersInSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]] componentsJoinedByString:@""];
    if (!digits.length) return;
    TKLivePlayerViewController *live = [[TKLivePlayerViewController alloc] initWithRoomId:digits];
    live.modalPresentationStyle = UIModalPresentationFullScreen;
    UIViewController *top = [self topController];
    if ([top isKindOfClass:[TKLivePlayerViewController class]]) {
        // another stream on screen (a link from another app): this one takes its place
        UIViewController *under = top.presentingViewController;
        [under dismissViewControllerAnimated:NO completion:^{ [under presentViewController:live animated:YES completion:nil]; }];
        return;
    }
    [top presentViewController:live animated:YES completion:nil];
}

#pragma mark - Web links in texts

// The link as text, with a scheme ("linktr.ee/name" -> "https://linktr.ee/name"); nil when there is nothing
+ (NSString *)webLinkString:(id)link
{
    NSString *s = [link isKindOfClass:[NSURL class]] ? [(NSURL *)link absoluteString] : [link isKindOfClass:[NSString class]] ? link : nil;
    s = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!s.length) return nil;
    if ([s rangeOfString:@"://"].location == NSNotFound) s = [@"https://" stringByAppendingString:s];
    return s;
}

+ (void)openWebLink:(id)link from:(UIViewController *)controller anchor:(UIView *)anchor
{
    NSString *s = [self webLinkString:link];
    if (!s) return;
    // a TikTok link: inside the app (a video, a photo post, a profile, a hashtag, a sound, a live stream); one the
    // router does not know (tiktok.com/about…) goes on to a browser like any other
    if ([self openLink:s]) return;
    NSURL *url = [NSURL URLWithString:s] ?: [NSURL URLWithString:[s stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding] ?: @""];
    if (!url) return;
    [TKExternalOpen presentOpenInForURL:url from:controller ?: [self topController] anchor:anchor];
}

+ (void)openWebLinks:(NSArray *)links from:(UIViewController *)controller anchor:(UIView *)anchor
{
    if (!links.count) return;
    if (links.count == 1) { [self openWebLink:links[0] from:controller anchor:anchor]; return; }
    TKLinkChoice *choice = [[TKLinkChoice alloc] init];
    choice.links = links;
    choice.controller = controller;
    choice.anchor = anchor;
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:L(@"Open a link") delegate:choice cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil];
    for (id link in links) [sheet addButtonWithTitle:[TKUtils linkTitle:link length:60]];
    sheet.cancelButtonIndex = [sheet addButtonWithTitle:L(@"Cancel")];
    if (!g_choices) g_choices = [NSMutableArray array];
    [g_choices addObject:choice];
    [TKExternalOpen showSheet:sheet from:controller ?: [self topController] anchor:anchor];
}

@end
