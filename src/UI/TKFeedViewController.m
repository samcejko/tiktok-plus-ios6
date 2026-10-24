#import "TKFeedViewController.h"
#import "TKVideoCell.h"
#import "TKFeed.h"
#import "TKFeedSource.h"
#import "TKPersonalFeed.h"
#import "TKSession.h"
#import "TKTikTok.h"
#import "TKModels.h"
#import "TKSettings.h"
#import "TKTasteViewController.h"
#import "TKLinkRouter.h"
#import "TKSavedViewController.h"
#import "TKSettingsViewController.h"
#import "TKCommentsViewController.h"
#import "TKNotificationsViewController.h"
#import "TKLikedViewController.h"
#import "TKProfileViewController.h"
#import "TKLivePlayerViewController.h"
#import "TKLivesViewController.h"
#import "TKTopicsViewController.h"
#import "TKPageNavigationController.h"
#import "TKBottomSheet.h"
#import "TKExternalOpen.h"
#import "TKTheme.h"
#import "TKUtils.h"
#import "TKModern.h"
#import "TKCommon.h"

enum { TKSheetMenu = 1, TKSheetVideo = 2 };
// The video's hold menu: what each of its buttons does (which buttons there are depends on the iOS and on what is
// installed, so the sheet keeps a list of these in button order)
enum { TKVideoMenuSpeed, TKVideoMenuNotInterested, TKVideoMenuLike, TKVideoMenuCopyLink, TKVideoMenuSafari, TKVideoMenuSurfari, TKVideoMenuShare, TKVideoMenuCaptions };
enum { TKMenuMute, TKMenuSwitchFeed, TKMenuNotifications, TKMenuLiked, TKMenuProfile, TKMenuSaved, TKMenuLive, TKMenuTaste, TKMenuLink, TKMenuRefresh, TKMenuSettings };

// Auto-advance without anyone touching the screen: the first few moves still teach (mildly), later ones are
// probably an unattended iPad and teach nothing, and after a few more the feed stops moving on and just loops.
static const NSInteger TKAutoAdvancesThatTeach = 2;
static const NSInteger TKAutoAdvancesMax = 5;

// The feed pages vertically only: a sideways drag belongs to the video under it (its scrubber).
@interface TKPagerScrollView : UIScrollView
@end

@implementation TKPagerScrollView
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g
{
    if (g == self.panGestureRecognizer) {
        CGPoint v = [self.panGestureRecognizer velocityInView:self];
        if (fabs(v.x) > fabs(v.y)) return NO;
    }
    return [super gestureRecognizerShouldBegin:g];
}
@end

@interface TKFeedViewController () <UIScrollViewDelegate, TKVideoCellDelegate, UIActionSheetDelegate, UIAlertViewDelegate>
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) id<TKFeedSource> feed;      // live mode
@property (nonatomic) NSInteger feedMode; // 0 Explore, 1 account For You, 2 Following
@property (nonatomic, strong) NSArray *menuActions;
@property (nonatomic, strong) NSArray *fixedVideos;      // fixed mode (saved / single link)
@property (nonatomic, strong) NSMutableDictionary *cells;   // index -> TKVideoCell
@property (nonatomic) NSInteger currentIndex;
@property (nonatomic) BOOL fixedMode;
@property (nonatomic, strong) UILabel *messageLabel;
@property (nonatomic, strong) UIButton *messageButton;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIButton *menuButton;
@property (nonatomic, strong) UIButton *closeButton;     // (fixed lists only)
@property (nonatomic, strong) UIButton *searchButton;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) TKBottomSheet *commentsSheet;
@property (nonatomic, strong) TKCommentsViewController *sheetComments;
@property (nonatomic) BOOL loadingMore;                   // (a growing fixed list) the next videos are on their way
@property (nonatomic) BOOL noMore;
@property (nonatomic) BOOL muted;
@property (nonatomic) BOOL appeared;
@property (nonatomic) BOOL visible;        // on screen (not covered by a full-screen controller)
@property (nonatomic) NSInteger liveScreens;          // live streams on screen over it
@property (nonatomic, readonly) BOOL pausedForLive;   // (one or more)
@property (nonatomic, weak) TKVideoCell *menuCell;       // the page whose menu (hold) is open
@property (nonatomic, weak) UIActionSheet *videoMenu;     // that menu while it is up
@property (nonatomic, strong) NSArray *videoMenuActions;  // NSNumber (TKVideoMenu…) per button of that menu
@property (nonatomic) BOOL shareWhenMenuGone;             // "Share" chosen: the share sheet comes once the menu has gone
@property (nonatomic) NSInteger autoAdvanceStreak;        // moves on by itself since the viewer last did anything
@property (nonatomic) BOOL autoAdvancing;                 // the page change under way is one of those
@property (nonatomic) BOOL pageAnimating;                 // advance's scroll is under way
@property (nonatomic) CGSize pageSize;                    // the pages' size at the last layout
@property (nonatomic, strong) UINavigationController *panelNav;   // landscape iPad: comments beside the feed
@property (nonatomic, strong) TKCommentsViewController *panel;
@end

@implementation TKFeedViewController

- (instancetype)init
{
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _feed = [[TKFeed alloc] init];
        _cells = [NSMutableDictionary dictionary];
        _muted = [TKSettings startMuted];
    }
    return self;
}

- (instancetype)initWithVideos:(NSArray *)videos startIndex:(NSInteger)startIndex title:(NSString *)title
{
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _fixedMode = YES;
        _fixedVideos = videos ?: @[];
        _currentIndex = startIndex;
        _cells = [NSMutableDictionary dictionary];
        _muted = [TKSettings startMuted];
        self.title = title;
    }
    return self;
}

- (NSInteger)count { return self.fixedMode ? (NSInteger)self.fixedVideos.count : (NSInteger)self.feed.videos.count; }
- (TKVideo *)videoAt:(NSInteger)i { NSArray *a = self.fixedMode ? self.fixedVideos : self.feed.videos; return (i >= 0 && i < (NSInteger)a.count) ? a[(NSUInteger)i] : nil; }

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    self.wantsFullScreenLayout = YES;

    self.scroll = [[TKPagerScrollView alloc] initWithFrame:self.view.bounds];
    self.scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.scroll.pagingEnabled = YES;
    self.scroll.showsVerticalScrollIndicator = NO;
    self.scroll.showsHorizontalScrollIndicator = NO;
    self.scroll.delegate = self;
    self.scroll.backgroundColor = [UIColor blackColor];
    TKModernKeepScrollViewInsets(self.scroll);   // (iOS 11+ would add the notch to the pages' insets and break the paging)
    [self.view addSubview:self.scroll];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    self.spinner.hidesWhenStopped = YES;
    [self.view addSubview:self.spinner];

    self.messageLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.messageLabel.textColor = [UIColor colorWithWhite:0.9 alpha:1];
    self.messageLabel.font = [UIFont systemFontOfSize:16];
    self.messageLabel.numberOfLines = 0;
    self.messageLabel.textAlignment = NSTextAlignmentCenter;
    self.messageLabel.backgroundColor = [UIColor clearColor];
    self.messageLabel.hidden = YES;
    [self.view addSubview:self.messageLabel];

    self.messageButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [self.messageButton setTitle:L(@"Set up") forState:UIControlStateNormal];
    [self.messageButton addTarget:self action:@selector(openSettings) forControlEvents:UIControlEventTouchUpInside];
    self.messageButton.hidden = YES;
    [self.view addSubview:self.messageButton];

    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.titleLabel.textColor = [UIColor whiteColor];
    self.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.backgroundColor = [UIColor clearColor];
    self.titleLabel.text = self.title ?: [self currentFeedTitle];
    self.titleLabel.layer.shadowOpacity = 0.7;
    self.titleLabel.layer.shadowRadius = 2;
    [self.view addSubview:self.titleLabel];

    self.menuButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.menuButton setImage:[[TKTheme shared] gearIconWhite] forState:UIControlStateNormal];
    self.menuButton.accessibilityLabel = self.fixedMode ? L(@"Mute") : L(@"Menu");   // (icon only: for VoiceOver)
    self.menuButton.layer.shadowOpacity = 0.7;
    [self.menuButton addTarget:self action:@selector(openMenu) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.menuButton];

    if (self.fixedMode) {
        // (opened from a page: back to it; on its own: closes)
        UIButton *close = [UIButton buttonWithType:UIButtonTypeCustom];
        BOOL back = [self.navigationController isKindOfClass:[TKPageNavigationController class]];
        [close setImage:back ? [[TKTheme shared] backChevronWhite] : [[TKTheme shared] closeIconWhite] forState:UIControlStateNormal];
        close.accessibilityLabel = back ? L(@"Back") : L(@"Close");
        close.frame = CGRectMake(8, 24, 40, 40);
        close.layer.shadowOpacity = 0.7;
        [close addTarget:self action:@selector(closeFixed) forControlEvents:UIControlEventTouchUpInside];
        [self.view addSubview:close];
        self.closeButton = close;
    } else {
        self.searchButton = [UIButton buttonWithType:UIButtonTypeCustom];
        [self.searchButton setImage:[[TKTheme shared] searchIconWhite] forState:UIControlStateNormal];
        self.searchButton.accessibilityLabel = L(@"Search");
        self.searchButton.layer.shadowOpacity = 0.7;
        [self.searchButton addTarget:self action:@selector(openSearch) forControlEvents:UIControlEventTouchUpInside];
        [self.view addSubview:self.searchButton];
    }

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(libraryChanged) name:TKLibraryDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(settingsChanged) name:TKSettingsDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(livePlaybackChanged:) name:TKLivePlaybackNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appBecameActive) name:UIApplicationDidBecomeActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionChanged) name:TKSessionDidChangeNotification object:nil];
}

- (NSString *)currentFeedTitle
{
    return self.feedMode == 2 ? L(@"Following") : (self.feedMode == 1 ? L(@"For You") : L(@"Explore"));
}

- (void)sessionChanged
{
    if (self.fixedMode) return;
    [self removeAllCells];
    self.feedMode = 0;
    self.feed = [[TKFeed alloc] init];
    self.titleLabel.text = self.title ?: [self currentFeedTitle];
    if (self.appeared) [self loadFeed];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

// A landscape iPad shows the comments of the page on screen in a panel beside the feed
- (BOOL)wantsPanel { return TKIsPad() && self.view.bounds.size.width > self.view.bounds.size.height; }

- (void)ensurePanel
{
    if (self.panel) return;
    self.panel = [[TKCommentsViewController alloc] initAsPanel];
    self.panelNav = [[UINavigationController alloc] initWithRootViewController:self.panel];
    [[TKTheme shared] applyToNavigationBar:self.panelNav.navigationBar];
    [self addChildViewController:self.panelNav];
    [self.view addSubview:self.panelNav.view];
    [self.panelNav didMoveToParentViewController:self];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    CGRect all = self.view.bounds;
    CGRect pager = all;
    // the status bar (20 on iOS 6, where the view lies under it), the notch on iOS 11+ (the status bar is hidden
    // from iOS 7 on, so 0 elsewhere)
    CGFloat top = TKModernTopInset(self.view, 20);
    if ([self wantsPanel] && self.commentsSheet) [self closeComments];   // (the panel shows them on the side)
    if ([self wantsPanel]) {
        pager.size.width = floorf(all.size.width * 0.58f);
        [self ensurePanel];
        self.panelNav.view.frame = CGRectMake(CGRectGetMaxX(pager), top, all.size.width - pager.size.width, all.size.height - top);
        self.panelNav.view.hidden = NO;
        [self.panel showVideo:[self videoAt:self.currentIndex]];
    } else {
        self.panelNav.view.hidden = YES;
    }
    self.scroll.frame = pager;
    CGSize s = pager.size;
    self.scroll.contentSize = CGSizeMake(s.width, s.height * MAX(1, [self count]));
    for (NSNumber *k in self.cells) {
        TKVideoCell *cell = self.cells[k];
        cell.frame = CGRectMake(0, s.height * k.integerValue, s.width, s.height);
    }
    // Not while the pages move (a finger, or an advance): the feed growing mid-swipe threw the page back
    BOOL moving = self.scroll.dragging || self.scroll.decelerating || self.pageAnimating;
    if (!moving || !CGSizeEqualToSize(s, self.pageSize)) self.scroll.contentOffset = CGPointMake(0, s.height * self.currentIndex);
    self.pageSize = s;
    self.spinner.center = CGPointMake(s.width / 2, s.height / 2);
    self.messageLabel.frame = CGRectMake(30, s.height / 2 - 70, s.width - 60, 90);
    self.messageButton.frame = CGRectMake(s.width / 2 - 80, s.height / 2 + 30, 160, 40);
    self.titleLabel.frame = CGRectMake(s.width / 2 - 100, top + 6, 200, 20);
    self.menuButton.frame = CGRectMake(s.width - 48, top + 4, 40, 40);
    self.searchButton.frame = CGRectMake(8, top + 4, 40, 40);
    self.closeButton.frame = CGRectMake(8, top + 4, 40, 40);
}

- (BOOL)prefersStatusBarHidden { return YES; }
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 110000
// iOS 11 and newer: the scrubbing strip at the bottom of a page must not be taken for the home gesture (it needs a
// second swipe then), and the home indicator fades away
- (UIRectEdge)preferredScreenEdgesDeferringSystemGestures { return UIRectEdgeBottom; }
- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }
#endif
// Every orientation on the iPad (on its side the comments sit beside the video); a phone stays upright
- (BOOL)shouldAutorotate { return YES; }
- (NSUInteger)supportedInterfaceOrientations
{
    return TKIsPad() ? UIInterfaceOrientationMaskAll : UIInterfaceOrientationMaskPortrait;
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    self.visible = YES;
    if (self.appeared) { if (!self.pausedForLive) [self setActiveIndex:self.currentIndex]; return; }
    self.appeared = YES;
    if (self.fixedMode) {
        [self.view setNeedsLayout];
        [self refreshWindow];
        [self setActiveIndex:self.currentIndex];
        [self growFixedIfNearEnd];
    } else if (![TKSettings topicsChosen] && [TKTikTok configured]) {
        [self askForTopics];     // (the first start: the feed loads once they are picked or skipped)
    } else {
        [self loadFeed];
    }
}

// Covered (a page, a sheet over everything, a stream): the video waits where it is
- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    self.visible = NO;
    [[self cellAt:self.currentIndex] setActive:NO rewind:NO];
}

- (void)askForTopics
{
    TKTopicsViewController *topics = [[TKTopicsViewController alloc] init];
    topics.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:topics animated:YES completion:nil];
    self.appeared = NO;      // (it marks the topics chosen, picked or skipped; viewDidAppear after it then loads the feed)
}

- (void)appBecameActive
{
    if (self.visible && !self.pausedForLive) [[self cellAt:self.currentIndex] wakeUp];
}

- (TKVideoCell *)currentCell { return [self cellAt:self.currentIndex]; }

#pragma mark - Live feed loading

- (void)loadFeed
{
    if (self.fixedMode) return;
    if (![TKTikTok configured]) {
        [self showMessage:L(@"Set your server address to start.\nSettings are behind the gear.") button:L(@"Open Settings") action:@selector(openSettings)];
        return;
    }
    [self showMessage:nil button:nil action:nil];
    [self.spinner startAnimating];
    id<TKFeedSource> requestedFeed = self.feed;
    [requestedFeed reloadWithCompletion:^(NSError *error) {
        if (self.feed != requestedFeed) return;
        [self.spinner stopAnimating];
        if (error) {
            if ([self count] == 0) [self showMessage:error.localizedDescription button:L(@"Try again") action:@selector(loadFeed)];
            return;
        }
        // a fresh list: the pages on screen belong to the old one
        [self removeAllCells];
        self.currentIndex = 0;
        [self.view setNeedsLayout];
        [self.view layoutIfNeeded];
        self.scroll.contentOffset = CGPointZero;   // (the layout leaves the offset alone while the pages move)
        [self refreshWindow];
        // A video link opened while the feed was loading covers it: playing now would sound under that video.
        // viewDidAppear starts the page once the feed is on screen again.
        if (self.visible && !self.pausedForLive) [self setActiveIndex:0];
    }];
}

- (void)showMessage:(NSString *)message button:(NSString *)button action:(SEL)action
{
    self.messageLabel.text = message;
    self.messageLabel.hidden = message == nil;
    self.messageButton.hidden = button == nil;
    if (button) {
        [self.messageButton setTitle:button forState:UIControlStateNormal];
        [self.messageButton removeTarget:self action:NULL forControlEvents:UIControlEventTouchUpInside];
        [self.messageButton addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    }
}

- (void)libraryChanged
{
    if (!self.fixedMode && self.appeared && [self count] == 0 && !self.feed.loading) [self loadFeed];
}

// the server address was just set: the empty feed can start now; captions turned on or off
- (void)settingsChanged
{
    for (NSNumber *k in self.cells) [self.cells[k] captionsSettingChanged];
    if (!self.fixedMode && self.appeared && [self count] == 0 && !self.feed.loading && [TKTikTok configured]) [self loadFeed];
}

#pragma mark - Cell window

- (TKVideoCell *)cellAt:(NSInteger)index { return self.cells[@(index)]; }

- (TKVideoCell *)ensureCellAt:(NSInteger)index
{
    if (index < 0 || index >= [self count]) return nil;
    TKVideoCell *cell = self.cells[@(index)];
    if (cell) return cell;
    CGSize s = self.scroll.bounds.size;
    cell = [[TKVideoCell alloc] initWithFrame:CGRectMake(0, s.height * index, s.width, s.height)];
    cell.delegate = self;
    [cell showVideo:[self videoAt:index]];
    [self.scroll addSubview:cell];
    self.cells[@(index)] = cell;
    return cell;
}

- (void)removeAllCells
{
    for (NSNumber *k in [self.cells allKeys]) { [self.cells[k] teardown]; [self.cells[k] removeFromSuperview]; }
    [self.cells removeAllObjects];
}

// keep cells for [current-1 .. current+1], tear down the rest
- (void)refreshWindow
{
    NSInteger lo = self.currentIndex - 1, hi = self.currentIndex + 1;
    for (NSNumber *k in [self.cells allKeys]) {
        NSInteger i = k.integerValue;
        if (i < lo || i > hi) { [self.cells[k] teardown]; [self.cells[k] removeFromSuperview]; [self.cells removeObjectForKey:k]; }
    }
    for (NSInteger i = lo; i <= hi; i++) [self ensureCellAt:i];
}

- (void)setActiveIndex:(NSInteger)index
{
    for (NSNumber *k in self.cells) [self.cells[k] setActive:(k.integerValue == index)];
    [self prepareIndex:index play:YES];
    [self prepareIndex:index + 1 play:NO];   // buffer the next one, so the swipe starts at once
    if (self.panel && !self.panelNav.view.hidden) [self.panel showVideo:[self videoAt:index]];
}

// resolve the direct URL if needed, then play (or prepare: buffer without a picture)
- (void)prepareIndex:(NSInteger)index play:(BOOL)play
{
    TKVideo *video = [self videoAt:index];
    TKVideoCell *cell = [self cellAt:index];
    if (!video || !cell) return;
    if (video.playable) {
        if (play || index == self.currentIndex) [cell startPlaybackMuted:self.muted];
        else [cell preparePlayback];
        return;
    }
    id expectedFeed = self.feed;
    [TKTikTok resolveVideo:video completion:^(TKVideo *resolved, NSError *error) {
        if (expectedFeed != self.feed || [self videoAt:index] != video || [self cellAt:index] != cell) return;
        if (error || !resolved.playable) {
            if (index == self.currentIndex) [cell showError:error.localizedDescription ?: L(@"This video could not be loaded.")];
            return;
        }
        TKVideoCell *stillThere = [self cellAt:index];
        if (!stillThere) return;
        if (index == self.currentIndex && self.visible) [stillThere startPlaybackMuted:self.muted];
        else [stillThere preparePlayback];
    }];
}

#pragma mark - Scroll paging

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView { self.pageAnimating = NO; [self viewerIsHere]; }   // (a finger stops an advance)
- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView { [self pageSettled]; }
- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView { [self pageSettled]; }

- (void)viewerIsHere { self.autoAdvanceStreak = 0; }

- (void)pageSettled
{
    self.pageAnimating = NO;
    CGFloat h = self.scroll.bounds.size.height;
    NSInteger page = h > 0 ? (NSInteger)(self.scroll.contentOffset.y / h + 0.5) : 0;
    if (page < 0) page = 0;
    if (page >= [self count]) page = [self count] - 1;
    if (page == self.currentIndex) return;

    // the lesson: how long the page we leave was really watched (an unattended feed teaches nothing)
    BOOL passive = self.autoAdvancing;
    self.autoAdvancing = NO;
    TKVideo *leaving = [self videoAt:self.currentIndex];
    TKVideoCell *leavingCell = [self cellAt:self.currentIndex];
    if (leaving && leavingCell) {
        NSTimeInterval watched = [leavingCell takeWatchedSeconds];
        if (!self.fixedMode && !(passive && self.autoAdvanceStreak > TKAutoAdvancesThatTeach)) {
            if ([self.feed respondsToSelector:@selector(noteWatched:seconds:duration:passive:)]) {
                [(id)self.feed noteWatched:leaving seconds:watched duration:leavingCell.duration passive:passive];
            }
        }
        [TKSettings markVideoSeen:leaving.videoId];
    }

    self.currentIndex = page;
    [self refreshWindow];
    [self setActiveIndex:page];

    if (!self.fixedMode && page >= [self count] - 4) {
        [self.feed ensureAhead:page by:8 completion:^(BOOL added) {
            if (!added) return;
            [self grew];
        }];
    }
    [self growFixedIfNearEnd];
}

// A growing fixed list (a hashtag's videos...) asks for its next ones a few pages before its end
- (void)growFixedIfNearEnd
{
    if (!self.fixedMode || !self.loadMore || self.loadingMore || self.noMore || self.currentIndex < [self count] - 4) return;
    self.loadingMore = YES;
    __weak TKFeedViewController *weakSelf = self;
    self.loadMore(self.fixedVideos.count, ^(NSArray *more) {
        TKFeedViewController *me = weakSelf;
        if (!me) return;
        me.loadingMore = NO;
        if (!more.count) { me.noMore = YES; return; }
        me.fixedVideos = [me.fixedVideos arrayByAddingObjectsFromArray:more];
        [me grew];
    });
}

// More videos joined the list: room for them, and the next one buffers
- (void)grew
{
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
    [self refreshWindow];
    [self prepareIndex:self.currentIndex + 1 play:NO];
}

- (void)advance
{
    NSInteger next = self.currentIndex + 1;
    if (next >= [self count] || self.scroll.dragging) return;
    self.pageAnimating = YES;
    [self.scroll setContentOffset:CGPointMake(0, self.scroll.bounds.size.height * next) animated:YES];
}

#pragma mark - Cell delegate

- (void)saveVideoOf:(TKVideoCell *)cell
{
    TKVideo *v = cell.video;
    if (!v || [TKSettings isSaved:v.videoId]) return;
    [TKSettings saveVideoJSON:[v toJSON]];
    [cell updateSavedState:YES];
    if (!self.fixedMode && [self.feed respondsToSelector:@selector(noteSaved:)]) [(id)self.feed noteSaved:v];
}

- (void)videoCellWasTouched:(TKVideoCell *)cell { [self viewerIsHere]; }

- (void)videoCellDidTapAuthor:(TKVideoCell *)cell
{
    [self viewerIsHere];
    if (cell.video.author.length) [TKLinkRouter openProfile:cell.video.author];
}

- (void)videoCellDidTapLive:(TKVideoCell *)cell
{
    [self viewerIsHere];
    [TKLinkRouter openLiveRoom:cell.video.authorLiveRoom];
}

// A #hashtag, @mention or web link in the caption (a TikTok link opens here, others where they lead: TKLinkRouter)
- (void)videoCell:(TKVideoCell *)cell didTapLink:(NSString *)link
{
    [self viewerIsHere];
    if ([link hasPrefix:@"tag:"]) [TKLinkRouter openHashtag:[link substringFromIndex:4]];
    else if ([link hasPrefix:@"user:"]) [TKLinkRouter openProfile:[link substringFromIndex:5]];
    else if ([link hasPrefix:@"url:"]) [TKLinkRouter openWebLink:[link substringFromIndex:4] from:self anchor:[cell linkAnchorView]];
}

- (void)videoCellDidTapSound:(TKVideoCell *)cell
{
    [self viewerIsHere];
    if (cell.video.musicId.length) [TKLinkRouter openSound:cell.video.musicId title:cell.video.music];
}

- (void)openSearch
{
    [self viewerIsHere];
    [TKLinkRouter openSearch:nil];
}

// A live stream on screen (over a sheet, where UIKit does not tell the feed it is covered): the page waits. Counted:
// when one stream takes another's place, the new one may come before the old one has gone.
- (void)livePlaybackChanged:(NSNotification *)note
{
    self.liveScreens = MAX(0, self.liveScreens + ([note.userInfo[@"playing"] boolValue] ? 1 : -1));
    if (self.pausedForLive) [[self cellAt:self.currentIndex] setActive:NO rewind:NO];
    else if (self.visible) [self setActiveIndex:self.currentIndex];
}

- (BOOL)pausedForLive { return self.liveScreens > 0; }

- (void)videoCellDidTapSave:(TKVideoCell *)cell
{
    [self viewerIsHere];
    TKVideo *v = cell.video;
    if ([TKSettings isSaved:v.videoId]) {
        [TKSettings unsaveVideo:v.videoId];
        [cell updateSavedState:NO];
    } else {
        [self saveVideoOf:cell];
    }
}

// double tap saves, and if signed in with writes enabled, also likes on TikTok
- (void)videoCellDidDoubleTap:(TKVideoCell *)cell
{
    [self viewerIsHere];
    [self saveVideoOf:cell];
    if ([TKSession sharedSession].signedIn && [TKSettings allowAccountWrites] && cell.video.videoId.length) {
        [TKTikTok diggVideoId:cell.video.videoId type:1 completion:^(BOOL ok, NSError *error) {
            if (ok) [cell showToast:L(@"Liked on TikTok")];
        }];
    }
}

- (void)videoCellDidTapComments:(TKVideoCell *)cell
{
    [self viewerIsHere];
    if (!self.fixedMode && [self.feed respondsToSelector:@selector(noteEngaged:weight:)]) [(id)self.feed noteEngaged:cell.video weight:0.4];
    if (self.panel && !self.panelNav.view.hidden) return;   // (landscape: they are already beside the video)
    [self showCommentsOf:cell.video];
}

// The comments slide up from the bottom over the lower part of the page; the video plays on above them
- (void)showCommentsOf:(TKVideo *)video
{
    if (self.commentsSheet || !video) return;
    TKCommentsViewController *comments = [[TKCommentsViewController alloc] initForBottomSheetWithVideo:video];
    TKBottomSheet *sheet = [[TKBottomSheet alloc] initWithFrame:self.view.bounds];
    sheet.title = video.commentCount ? [NSString stringWithFormat:L(@"Comments (%@)"), [TKUtils formatCount:video.commentCount]] : L(@"Comments");
    [self addChildViewController:comments];
    comments.view.frame = sheet.contentView.bounds;
    comments.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [sheet.contentView addSubview:comments.view];
    [comments didMoveToParentViewController:self];
    __weak TKFeedViewController *weakSelf = self;
    __weak TKCommentsViewController *weakComments = comments;
    sheet.onClose = ^{
        TKCommentsViewController *c = weakComments;
        [c willMoveToParentViewController:nil];
        [c.view removeFromSuperview];
        [c removeFromParentViewController];
        weakSelf.commentsSheet = nil;
        weakSelf.sheetComments = nil;
    };
    self.commentsSheet = sheet;
    self.sheetComments = comments;
    [sheet showInView:self.view];
}

// A page change or a turn to landscape (the panel shows them there) takes the sheet away
- (void)closeComments
{
    [self.commentsSheet close];
}

- (void)videoCellDidReachEnd:(TKVideoCell *)cell
{
    if (cell != [self cellAt:self.currentIndex]) return;
    if (![TKSettings autoAdvance]) return;
    if (self.videoMenu.visible || self.commentsSheet) return;  // its menu or comments are open: stay (it loops)
    if (self.autoAdvanceStreak >= TKAutoAdvancesMax) {         // nobody seems to be watching: loop instead
        if (self.autoAdvanceStreak == TKAutoAdvancesMax) { [cell showToast:L(@"Auto-advance paused")]; self.autoAdvanceStreak++; }   // (said once)
        return;
    }
    self.autoAdvanceStreak++;
    self.autoAdvancing = YES;
    [self advance];
}

// hold = the video's menu
- (void)videoCell:(TKVideoCell *)cell didLongPressAt:(CGPoint)point
{
    [self viewerIsHere];
    if (cell != [self cellAt:self.currentIndex] || !cell.video || self.videoMenu.visible) return;
    self.menuCell = cell;
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil];
    sheet.tag = TKSheetVideo;
    self.videoMenu = sheet;
    NSMutableArray *actions = [NSMutableArray array];
    [sheet addButtonWithTitle:cell.fastPlayback ? L(@"Play at normal speed") : L(@"Play at 2× speed")];
    [actions addObject:@(TKVideoMenuSpeed)];
    if ([TKSession sharedSession].signedIn && [TKSettings allowAccountWrites]) {
        [sheet addButtonWithTitle:L(@"Like on TikTok")];
        [actions addObject:@(TKVideoMenuLike)];
    }
    [sheet addButtonWithTitle:L(@"Not interested")];
    [actions addObject:@(TKVideoMenuNotInterested)];
    [sheet addButtonWithTitle:L(@"Copy link")];
    [actions addObject:@(TKVideoMenuCopyLink)];
    [sheet addButtonWithTitle:L(@"Open in Safari")];
    [actions addObject:@(TKVideoMenuSafari)];
    // iOS 6: Surfari too, when it is installed (the browsers side by side, no second sheet); iOS 7 and newer: the
    // system's share sheet instead
    if (!TKModernIOS() && [TKExternalOpen surfariAvailable]) {
        [sheet addButtonWithTitle:L(@"Open in Surfari")];
        [actions addObject:@(TKVideoMenuSurfari)];
    }
    if (TKModernIOS()) {
        [sheet addButtonWithTitle:L(@"Share")];
        [actions addObject:@(TKVideoMenuShare)];
    }
    if (cell.hasCaptions) {
        [sheet addButtonWithTitle:[TKSettings showCaptions] ? L(@"Hide captions") : L(@"Show captions")];
        [actions addObject:@(TKVideoMenuCaptions)];
    }
    sheet.cancelButtonIndex = [sheet addButtonWithTitle:L(@"Cancel")];
    self.videoMenuActions = actions;
    self.shareWhenMenuGone = NO;
    if (TKIsPad()) [sheet showFromRect:CGRectMake(point.x - 1, point.y - 1, 2, 2) inView:cell animated:YES];
    else [sheet showInView:self.view];
}

- (void)videoMenuChose:(NSInteger)index
{
    TKVideoCell *cell = self.menuCell;
    TKVideo *v = cell.video;
    if (!cell || !v || index < 0 || index >= (NSInteger)self.videoMenuActions.count) return;
    NSURL *link = [NSURL URLWithString:[v shareURL]];
    switch ([self.videoMenuActions[(NSUInteger)index] integerValue]) {
        case TKVideoMenuSpeed: {
            BOOL fast = !cell.fastPlayback;
            if ([cell setFastPlayback:fast]) [cell showToast:fast ? L(@"2× speed") : L(@"Normal speed")];
            else [cell showToast:L(@"This video cannot play faster.")];
            break;
        }
        case TKVideoMenuLike:
            if (![TKSettings allowAccountWrites]) {
                [TKUtils alertWithTitle:L(@"Actions disabled") message:L(@"Enable 'Allow actions on account' in Settings to like videos directly on TikTok.")];
            } else {
                [TKTikTok diggVideoId:v.videoId type:1 completion:^(BOOL ok, NSError *error) {
                    [cell showToast:ok ? L(@"Liked on TikTok") : L(@"Failed to like")];
                }];
            }
            break;
        case TKVideoMenuNotInterested:
            if (!self.fixedMode && [self.feed respondsToSelector:@selector(noteNotInterested:)]) [(id)self.feed noteNotInterested:v];
            [TKSettings markVideoSeen:v.videoId];
            [cell showToast:L(@"Got it, fewer like this")];
            [self performSelector:@selector(advance) withObject:nil afterDelay:0.6];
            break;
        case TKVideoMenuCopyLink:
            [UIPasteboard generalPasteboard].string = [v shareURL];
            [cell showToast:L(@"Link copied")];
            if (!self.fixedMode && [self.feed respondsToSelector:@selector(noteEngaged:weight:)]) [(id)self.feed noteEngaged:v weight:0.5];
            break;
        case TKVideoMenuSafari:
            if (!self.fixedMode && [self.feed respondsToSelector:@selector(noteEngaged:weight:)]) [(id)self.feed noteEngaged:v weight:0.5];
            [TKExternalOpen openInSafari:link];
            break;
        case TKVideoMenuSurfari:
            if (!self.fixedMode && [self.feed respondsToSelector:@selector(noteEngaged:weight:)]) [(id)self.feed noteEngaged:v weight:0.5];
            [TKExternalOpen openInSurfari:link];
            break;
        case TKVideoMenuShare:
            if (!self.fixedMode && [self.feed respondsToSelector:@selector(noteEngaged:weight:)]) [(id)self.feed noteEngaged:v weight:0.5];
            self.shareWhenMenuGone = YES;    // (not over a sheet still on its way out: see didDismiss)
            break;
        case TKVideoMenuCaptions: {
            BOOL show = ![TKSettings showCaptions];
            [TKSettings setShowCaptions:show];
            [cell showToast:show ? L(@"Captions on") : L(@"Captions off")];
            break;
        }
    }
}

// The hold menu has gone: the share sheet it asked for (iOS 7 and newer) comes now
- (void)actionSheet:(UIActionSheet *)sheet didDismissWithButtonIndex:(NSInteger)index
{
    if (sheet.tag != TKSheetVideo || !self.shareWhenMenuGone) return;
    self.shareWhenMenuGone = NO;
    TKVideoCell *cell = self.menuCell;
    if (cell.video) [TKExternalOpen presentShareSheetForURL:[NSURL URLWithString:[cell.video shareURL]] from:self anchor:[cell linkAnchorView]];
}

#pragma mark - Menu

- (void)openMenu
{
    if (self.fixedMode) { [self toggleMute]; return; }
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil];
    sheet.tag = TKSheetMenu;
    NSMutableArray *actions = [NSMutableArray array];

    [sheet addButtonWithTitle:self.muted ? L(@"Unmute") : L(@"Mute")];
    [actions addObject:@(TKMenuMute)];

    if ([TKSession sharedSession].signedIn) {
        [sheet addButtonWithTitle:self.feedMode == 0 ? L(@"Feed: For You") : (self.feedMode == 1 ? L(@"Feed: Following") : L(@"Feed: Explore"))];
        [actions addObject:@(TKMenuSwitchFeed)];

        [sheet addButtonWithTitle:L(@"Liked videos")];
        [actions addObject:@(TKMenuLiked)];

        [sheet addButtonWithTitle:L(@"My profile")];
        [actions addObject:@(TKMenuProfile)];
    }

    [sheet addButtonWithTitle:L(@"Saved")];
    [actions addObject:@(TKMenuSaved)];

    [sheet addButtonWithTitle:L(@"Live now")];
    [actions addObject:@(TKMenuLive)];

    [sheet addButtonWithTitle:L(@"What it learned")];
    [actions addObject:@(TKMenuTaste)];

    [sheet addButtonWithTitle:L(@"Open a link")];
    [actions addObject:@(TKMenuLink)];

    [sheet addButtonWithTitle:L(@"Refresh feed")];
    [actions addObject:@(TKMenuRefresh)];

    [sheet addButtonWithTitle:L(@"Settings")];
    [actions addObject:@(TKMenuSettings)];

    sheet.cancelButtonIndex = [sheet addButtonWithTitle:L(@"Cancel")];
    self.menuActions = actions;
    [sheet showInView:self.view];
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index
{
    if (index < 0 || index == sheet.cancelButtonIndex) return;
    if (sheet.tag == TKSheetVideo) { [self videoMenuChose:index]; return; }
    if (sheet.tag == TKSheetMenu) {
        if (index >= (NSInteger)self.menuActions.count) return;
        NSInteger action = [self.menuActions[(NSUInteger)index] integerValue];
        switch (action) {
            case TKMenuMute: [self toggleMute]; break;
            case TKMenuSwitchFeed: {
                self.feedMode = (self.feedMode + 1) % 3;
                [self removeAllCells];
                self.titleLabel.text = self.title ?: [self currentFeedTitle];
                self.feed = self.feedMode == 0 ? (id)[[TKFeed alloc] init] : [[TKPersonalFeed alloc] initWithFollowingMode:self.feedMode == 2];
                [self loadFeed];
                break;
            }
            case TKMenuNotifications:
                [self present:[[TKNotificationsViewController alloc] init]];
                break;
            case TKMenuLiked:
                [self present:[[TKLikedViewController alloc] init]];
                break;
            case TKMenuProfile:
                if ([TKSession sharedSession].handle.length) {
                    [TKLinkRouter openProfile:[TKSession sharedSession].handle];
                }
                break;
            case TKMenuSaved: [self openSaved]; break;
            case TKMenuLive: [self present:[[TKLivesViewController alloc] init]]; break;
            case TKMenuTaste: [self present:[[TKTasteViewController alloc] init]]; break;
            case TKMenuLink: [self askForLink]; break;
            case TKMenuRefresh: [self loadFeed]; break;
            case TKMenuSettings: [self openSettings]; break;
        }
    }
}

- (void)askForLink
{
    UIAlertView *a = [[UIAlertView alloc] initWithTitle:L(@"Open a link") message:L(@"Paste a TikTok link: a video, a profile or a live stream.")
                                               delegate:self cancelButtonTitle:L(@"Cancel") otherButtonTitles:L(@"Open"), nil];
    a.alertViewStyle = UIAlertViewStylePlainTextInput;
    [a textFieldAtIndex:0].text = [UIPasteboard generalPasteboard].string ?: @"";
    [a show];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex == alertView.cancelButtonIndex) return;
    NSString *link = [alertView textFieldAtIndex:0].text;
    if (![TKLinkRouter openLink:link]) [TKUtils alertWithTitle:L(@"Open a link") message:L(@"That does not look like a TikTok link.")];
}

- (void)toggleMute
{
    self.muted = !self.muted;
    [[self cellAt:self.currentIndex] setMuted:self.muted];
}

- (void)openSaved { [self present:[[TKSavedViewController alloc] init]]; }
- (void)openSettings { [self present:[[TKSettingsViewController alloc] initWithStyle:UITableViewStyleGrouped]]; }

- (void)present:(UIViewController *)vc
{
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    [[TKTheme shared] applyToNavigationBar:nav.navigationBar];
    if (TKIsPad()) nav.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)closeFixed
{
    if ([self.navigationController isKindOfClass:[TKPageNavigationController class]]) [(TKPageNavigationController *)self.navigationController goBack];
    else [self dismissViewControllerAnimated:YES completion:nil];
}

- (NSDictionary *)diagnosticState
{
    TKVideoCell *cell=[self currentCell];
    return @{@"playback":[cell playbackDiagnostics] ?: @{},@"count":@([self count]),@"index":@(self.currentIndex),@"mode":@(self.feedMode),@"loading":@(self.feed.loading),
        @"videoId":cell.video.videoId ?: @"",@"time":@(isfinite(cell.currentTime)?cell.currentTime:0),@"duration":@(isfinite(cell.duration)?cell.duration:0),
        @"playing":@(cell.playing),@"rate":@([cell playerRate]),@"photo":@(cell.video.isPhoto),@"visible":@(self.visible),@"error":self.messageLabel.hidden ? @"" : (self.messageLabel.text ?: @"")};
}

@end
