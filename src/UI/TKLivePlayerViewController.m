#import "TKLivePlayerViewController.h"
#import <AVFoundation/AVFoundation.h>
#import "TKLinkRouter.h"
#import "TKProfileViewController.h"
#import "TKMediaProxy.h"
#import "TKTikTok.h"
#import "TKModels.h"
#import "TKImageLoader.h"
#import "TKTheme.h"
#import "TKUtils.h"
#import "TKModern.h"
#import "TKCommon.h"

NSString * const TKLivePlaybackNotification = @"TKLivePlaybackNotification";

static const NSTimeInterval TKLiveRoomCheckEvery = 30;   // viewers, and whether the stream is still on
static const NSTimeInterval TKLiveStallLimit = 30;       // no picture for this long: the stream is opened again
static const NSTimeInterval TKLiveSteadyAfter = 60;      // playing this long forgives the earlier restarts
static const NSInteger TKLiveMaxRestarts = 3;

static __weak TKLivePlayerViewController *TKCurrentLive;

// The longer side of a stream's picture ("720x1280" -> 1280); by its quality name when TikTok does not say
static NSInteger TKStreamLongSide(NSDictionary *s)
{
    NSArray *wh = [TKStr(s[@"resolution"]) componentsSeparatedByString:@"x"];
    if (wh.count == 2) {
        NSInteger a = [wh[0] integerValue], b = [wh[1] integerValue];
        if (a > 0 && b > 0) return MAX(a, b);
    }
    NSDictionary *byName = @{ @"ld": @640, @"sd": @960, @"hd": @1280, @"uhd": @1920, @"origin": @2000 };
    NSInteger side = [byName[TKStr(s[@"quality"]) ?: @""] integerValue];
    return side ?: 1280;
}

@interface TKLivePlayerViewController ()
@property (nonatomic, copy) NSString *roomId;
@property (nonatomic, strong) TKLiveRoom *room;
@property (nonatomic, copy) NSString *streamDescription;    // "hd 720x1280 FLV"
@property (nonatomic) BOOL repacked;                       // the FLV repacked by the media proxy (not an HLS address)
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVPlayerLayer *playerLayer;
@property (nonatomic, strong) NSTimer *ticker;
@property (nonatomic) BOOL onScreen;
@property (nonatomic) BOOL checkingRoom;
@property (nonatomic) BOOL playWhenChecked;              // the room check under way opens the stream when it is on
@property (nonatomic) NSTimeInterval lastRoomCheck;
@property (nonatomic) double lastPosition;               // the player's position at the last tick (-1 = none)
@property (nonatomic) NSTimeInterval playingSince;       // when the picture last started moving (0 = it does not)
@property (nonatomic) NSTimeInterval lastProgress;        // when the picture last moved (or the stream was opened)
@property (nonatomic) NSInteger restarts;
@property (nonatomic) BOOL ended;
@property (nonatomic) BOOL overlayHidden;
@property (nonatomic) BOOL idleTimerWasDisabled;
@property (nonatomic, strong) TKImageView *coverView;
@property (nonatomic, strong) UIView *videoView;
@property (nonatomic, strong) UIImageView *topShade;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *messageLabel;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UIButton *ownerButton;
@property (nonatomic, strong) TKImageView *ownerAvatar;
@property (nonatomic, strong) UILabel *ownerLabel;
@property (nonatomic, strong) UILabel *livePill;
@property (nonatomic, strong) UILabel *viewersLabel;
@property (nonatomic, strong) UILabel *titleLabel;
@end

@implementation TKLivePlayerViewController

- (instancetype)initWithRoomId:(NSString *)roomId
{
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _roomId = [roomId copy] ?: @"";
        _lastPosition = -1;
        self.wantsFullScreenLayout = YES;
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (UILabel *)overlayLabel:(UIFont *)font
{
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectZero];
    l.font = font;
    l.textColor = [UIColor whiteColor];
    l.backgroundColor = [UIColor clearColor];
    l.layer.shadowOpacity = 0.7;
    l.layer.shadowRadius = 2;
    l.layer.shadowOffset = CGSizeMake(0, 1);
    [self.view addSubview:l];
    return l;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    UIViewAutoresizing fill = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    // the room's picture, dimmed, until the stream's first frames move
    self.coverView = [[TKImageView alloc] initWithFrame:self.view.bounds];
    self.coverView.autoresizingMask = fill;
    self.coverView.contentMode = UIViewContentModeScaleAspectFit;
    self.coverView.alpha = 0.45;
    [self.view addSubview:self.coverView];

    self.videoView = [[UIView alloc] initWithFrame:self.view.bounds];
    self.videoView.autoresizingMask = fill;
    self.videoView.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.videoView];

    self.topShade = [[UIImageView alloc] initWithImage:[[TKTheme shared] controlsGradientImageTop:YES]];
    [self.view addSubview:self.topShade];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    self.spinner.hidesWhenStopped = YES;
    [self.view addSubview:self.spinner];

    self.messageLabel = [self overlayLabel:[UIFont systemFontOfSize:16]];
    self.messageLabel.textColor = [UIColor colorWithWhite:0.92 alpha:1];
    self.messageLabel.numberOfLines = 0;
    self.messageLabel.textAlignment = NSTextAlignmentCenter;
    self.messageLabel.hidden = YES;

    self.closeButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.closeButton setImage:[[TKTheme shared] closeIconWhite] forState:UIControlStateNormal];
    self.closeButton.accessibilityLabel = L(@"Close");
    self.closeButton.layer.shadowOpacity = 0.7;
    [self.closeButton addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.closeButton];

    self.ownerAvatar = [[TKImageView alloc] initWithFrame:CGRectMake(0, 0, 36, 36)];
    self.ownerAvatar.contentMode = UIViewContentModeScaleAspectFill;
    self.ownerAvatar.clipsToBounds = YES;
    self.ownerAvatar.layer.cornerRadius = 18;
    self.ownerAvatar.layer.borderWidth = 2;
    self.ownerAvatar.layer.borderColor = [[TKTheme shared] liveColor].CGColor;
    self.ownerAvatar.backgroundColor = [UIColor colorWithWhite:0.25 alpha:1];
    [self.view addSubview:self.ownerAvatar];
    self.ownerLabel = [self overlayLabel:[UIFont boldSystemFontOfSize:15]];
    self.livePill = [self overlayLabel:[UIFont boldSystemFontOfSize:11]];
    self.livePill.text = @"LIVE";   // (TikTok's own word for it, in every language)
    self.livePill.textAlignment = NSTextAlignmentCenter;
    self.livePill.backgroundColor = [[TKTheme shared] liveColor];
    self.livePill.layer.shadowOpacity = 0;
    self.livePill.layer.cornerRadius = 3;
    self.livePill.layer.masksToBounds = YES;
    self.livePill.hidden = YES;
    self.viewersLabel = [self overlayLabel:[UIFont boldSystemFontOfSize:13]];
    self.titleLabel = [self overlayLabel:[UIFont systemFontOfSize:14]];
    self.titleLabel.numberOfLines = 2;
    self.ownerButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.ownerButton.accessibilityLabel = L(@"Profile");
    [self.ownerButton addTarget:self action:@selector(openOwner) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.ownerButton];

    // a tap hides the labels (and shows them again)
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleOverlay)];
    [self.videoView addGestureRecognizer:tap];
}

- (void)viewWillLayoutSubviews
{
    [super viewWillLayoutSubviews];
    CGSize s = self.view.bounds.size;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.playerLayer.frame = self.videoView.bounds;
    [CATransaction commit];
    // the status bar (20 on iOS 6, where the view lies under it), the notch on iOS 11+ (the status bar is hidden
    // from iOS 7 on, so 0 elsewhere)
    CGFloat top = TKModernTopInset(self.view, 20);
    self.topShade.frame = CGRectMake(0, 0, s.width, top + 110);
    self.closeButton.frame = CGRectMake(8, top + 4, 40, 40);
    self.ownerAvatar.frame = CGRectMake(54, top + 6, 36, 36);
    CGFloat textX = 98, textW = MAX(60, s.width - textX - 16);
    self.ownerLabel.frame = CGRectMake(textX, top + 5, textW, 19);
    CGSize pill = [self.livePill.text sizeWithFont:self.livePill.font];
    self.livePill.frame = CGRectMake(textX, top + 27, ceilf(pill.width) + 10, 15);
    CGFloat viewersX = self.livePill.hidden ? textX : CGRectGetMaxX(self.livePill.frame) + 7;
    self.viewersLabel.frame = CGRectMake(viewersX, top + 25, MAX(40, textX + textW - viewersX), 18);
    CGSize name = [self.ownerLabel.text ?: @"" sizeWithFont:self.ownerLabel.font];
    self.ownerButton.frame = CGRectMake(50, top, MIN(textW, MAX(ceilf(name.width), 90)) + 52, 48);
    CGSize title = [self.titleLabel.text ?: @"" sizeWithFont:self.titleLabel.font constrainedToSize:CGSizeMake(s.width - 32, 40) lineBreakMode:NSLineBreakByTruncatingTail];
    self.titleLabel.frame = CGRectMake(16, top + 54, s.width - 32, ceilf(title.height));
    self.spinner.center = CGPointMake(s.width / 2, s.height / 2);
    self.messageLabel.frame = CGRectMake(30, s.height / 2 - 60, s.width - 60, 120);
}

- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)shouldAutorotate { return YES; }
- (NSUInteger)supportedInterfaceOrientations { return TKIsPad() ? UIInterfaceOrientationMaskAll : UIInterfaceOrientationMaskPortrait; }

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    if (self.onScreen) return;
    self.onScreen = YES;
    TKCurrentLive = self;
    [[NSNotificationCenter defaultCenter] postNotificationName:TKLivePlaybackNotification object:self userInfo:@{ @"playing": @YES }];
    self.idleTimerWasDisabled = [UIApplication sharedApplication].idleTimerDisabled;
    [UIApplication sharedApplication].idleTimerDisabled = YES;   // (nobody touches the screen while watching)
    self.ticker = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(tick) userInfo:nil repeats:YES];
    if (!self.ended) {
        [self.spinner startAnimating];
        self.playWhenChecked = YES;
        [self checkRoom];
    }
}

// Covered or closed: the stream stops (it would go on reading from TikTok otherwise); coming back opens it again
- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    if (!self.onScreen) return;
    self.onScreen = NO;
    [self.ticker invalidate];
    self.ticker = nil;
    [self stopStream];
    [UIApplication sharedApplication].idleTimerDisabled = self.idleTimerWasDisabled;
    [[NSNotificationCenter defaultCenter] postNotificationName:TKLivePlaybackNotification object:self userInfo:@{ @"playing": @NO }];
}

- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }

// The streamer's profile. The live screen closes first; when it was opened from that very profile, that is all.
- (void)openOwner
{
    NSString *handle = self.room.ownerHandle;
    if (!handle.length) return;
    UIViewController *under = self.presentingViewController;
    if ([under isKindOfClass:[UINavigationController class]]) under = [(UINavigationController *)under topViewController];
    BOOL fromThatProfile = [under isKindOfClass:[TKProfileViewController class]] &&
                           [[(TKProfileViewController *)under handle] caseInsensitiveCompare:handle] == NSOrderedSame;
    [self dismissViewControllerAnimated:YES completion:^{
        if (!fromThatProfile) [TKLinkRouter openProfile:handle];
    }];
}

- (void)toggleOverlay
{
    self.overlayHidden = !self.overlayHidden;
    CGFloat alpha = self.overlayHidden ? 0 : 1;
    [UIView animateWithDuration:0.25 animations:^{
        for (UIView *v in @[ self.topShade, self.closeButton, self.ownerAvatar, self.ownerLabel, self.livePill, self.viewersLabel, self.titleLabel ]) v.alpha = alpha;
    }];
    self.ownerButton.userInteractionEnabled = !self.overlayHidden;
    self.closeButton.userInteractionEnabled = !self.overlayHidden;
}

#pragma mark - The room

- (void)checkRoom
{
    if (self.checkingRoom) return;
    self.checkingRoom = YES;
    self.lastRoomCheck = [NSDate timeIntervalSinceReferenceDate];
    __weak TKLivePlayerViewController *weakSelf = self;
    [TKTikTok liveRoom:self.roomId completion:^(TKLiveRoom *room, NSError *error) {
        TKLivePlayerViewController *me = weakSelf;
        if (!me) return;
        me.checkingRoom = NO;
        if (!me.onScreen) return;
        BOOL play = me.playWhenChecked;
        me.playWhenChecked = NO;
        if (!room) {
            if (play) [me showMessage:error.localizedDescription ?: L(@"This live stream could not be loaded.")];
            return;
        }
        me.room = room;
        [me showRoom];
        if (!room.live) { [me showEnded]; return; }
        if (play) [me startStream];
    }];
}

- (void)showRoom
{
    TKLiveRoom *r = self.room;
    NSString *handle = r.ownerHandle.length ? [@"@" stringByAppendingString:r.ownerHandle] : @"";
    self.ownerLabel.text = r.ownerName.length ? [TKUtils displayText:r.ownerName] : handle;
    [self.ownerAvatar setImageURL:r.ownerAvatarURL placeholder:nil];
    self.viewersLabel.text = r.viewers > 0 ? [TKUtils formatViewers:r.viewers] : @"";
    self.titleLabel.text = r.title.length ? [TKUtils displayText:r.title] : @"";
    if (!self.coverView.imageURL.length && r.coverURL.length) [self.coverView setImageURL:r.coverURL placeholder:nil];
    self.livePill.hidden = !r.live;
    self.ownerButton.enabled = r.ownerHandle.length > 0;
    [self.view setNeedsLayout];
}

- (void)showMessage:(NSString *)message
{
    [self.spinner stopAnimating];
    self.messageLabel.text = message;
    self.messageLabel.hidden = message.length == 0;
}

- (void)showEnded
{
    TKLog(@"live: room %@ is not live (any more)", self.roomId);
    self.ended = YES;
    [self stopStream];
    self.livePill.hidden = YES;
    self.coverView.alpha = 0.45;
    [self showMessage:L(@"This live stream has ended.")];
    [self.view setNeedsLayout];
}

#pragma mark - The stream

// The largest H.264 picture up to the screen (at least 720p); else the smallest there is. HEVC streams (bytevc1)
// have no decoder on these devices, "ao" is the sound alone.
- (NSDictionary *)pickStream
{
    CGSize screen = [UIScreen mainScreen].bounds.size;
    NSInteger limit = MAX((NSInteger)1280, (NSInteger)(MAX(screen.width, screen.height) * [UIScreen mainScreen].scale));
    NSDictionary *best = nil, *smallest = nil;
    NSInteger bestSide = 0, smallestSide = NSIntegerMax;
    for (NSDictionary *s in self.room.streams) {
        NSString *codec = [TKStr(s[@"vcodec"]) lowercaseString] ?: @"";
        if ([TKStr(s[@"quality"]) isEqualToString:@"ao"]) continue;
        if (codec.length && [codec rangeOfString:@"264"].location == NSNotFound) continue;
        if (!TKStr(s[@"flv"]).length && !TKStr(s[@"hls"]).length) continue;
        NSInteger side = TKStreamLongSide(s);
        if (side <= limit && side > bestSide) { best = s; bestSide = side; }
        if (side < smallestSide) { smallest = s; smallestSide = side; }
    }
    return best ?: smallest;
}

- (void)startStream
{
    [self stopStream];
    NSDictionary *s = [self pickStream];
    if (!s) { [self showMessage:L(@"This live stream cannot be played on this device.")]; return; }
    TKMediaProxy *proxy = [TKMediaProxy shared];
    [proxy ensureRunning];
    NSString *hls = TKStr(s[@"hls"]), *flv = TKStr(s[@"flv"]);
    NSURL *source = [NSURL URLWithString:hls.length ? hls : (flv ?: @"")];
    NSString *url = !source ? nil : hls.length ? [proxy proxyURLForURL:source upstreamHeaders:self.room.headers]
                                               : [proxy proxyURLForLiveFLV:source headers:self.room.headers];
    if (!url) { [self showMessage:L(@"This live stream could not be loaded.")]; return; }
    self.repacked = hls.length == 0;
    self.streamDescription =[NSString stringWithFormat:@"%@ %@ %@", TKStr(s[@"quality"]) ?: @"?", TKStr(s[@"resolution"]) ?: @"", hls.length ? @"HLS" : @"FLV"];
    TKLog(@"live: room %@ (@%@): %@", self.roomId, self.room.ownerHandle, self.streamDescription);
    self.messageLabel.hidden = YES;
    [self.spinner startAnimating];
    self.player = [AVPlayer playerWithURL:[NSURL URLWithString:url]];
    self.playerLayer = [AVPlayerLayer playerLayerWithPlayer:self.player];
    self.playerLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    self.playerLayer.frame = self.videoView.bounds;
    [self.videoView.layer addSublayer:self.playerLayer];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(streamRanOut:) name:AVPlayerItemDidPlayToEndTimeNotification object:self.player.currentItem];
    [self.player play];
    self.lastPosition = -1;
    self.playingSince = 0;
    self.lastProgress = [NSDate timeIntervalSinceReferenceDate];
}

- (void)stopStream
{
    if (self.player) {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:nil];
        [self.player pause];
        [self.playerLayer removeFromSuperlayer];
        self.playerLayer = nil;
        self.player = nil;
    }
    [[TKMediaProxy shared] stopLiveStreams];
    self.playingSince = 0;
}

// The repacked stream stopped (TikTok's CDN let go, or nobody asked for a while): the room says whether to go on
- (void)streamRanOut:(NSNotification *)note
{
    if (!self.onScreen || self.ended) return;
    TKLog(@"live: the stream ran out");
    [self startAgainOrGiveUp:nil];
}

- (void)startAgainOrGiveUp:(NSString *)why
{
    [self stopStream];
    if (self.restarts >= TKLiveMaxRestarts) {
        [self showMessage:why.length ? why : L(@"The live stream keeps breaking off.")];
        return;
    }
    self.restarts++;
    self.messageLabel.hidden = YES;
    [self.spinner startAnimating];
    self.playWhenChecked = YES;
    self.checkingRoom = NO;   // (an answer still on its way is for the old stream; this one decides)
    [self checkRoom];
}

- (void)tick
{
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (!self.ended && now - self.lastRoomCheck > TKLiveRoomCheckEvery) [self checkRoom];
    AVPlayer *p = self.player;
    if (!p) return;
    AVPlayerItem *item = p.currentItem;
    if (item.status == AVPlayerItemStatusFailed) {
        TKLog(@"live: the player failed: %@", item.error.localizedDescription);
        [self startAgainOrGiveUp:L(@"This live stream cannot be played on this device.")];
        return;
    }
    double position = CMTimeGetSeconds(p.currentTime);
    BOOL known = isfinite(position);
    BOOL moving = item.status == AVPlayerItemStatusReadyToPlay && known && self.lastPosition >= 0 && position > self.lastPosition + 0.2;
    self.lastPosition = known ? position : -1;
    if (moving) {
        self.lastProgress = now;
        if (!self.playingSince) {
            self.playingSince = now;
            [self.spinner stopAnimating];
            [UIView animateWithDuration:0.3 animations:^{ self.coverView.alpha = 0; }];
        }
        if (now - self.playingSince > TKLiveSteadyAfter) self.restarts = 0;
        return;
    }
    if (self.playingSince) {
        self.playingSince = 0;
        [self.spinner startAnimating];
    }
    // after a stall the player of iOS 6 stays paused: it is asked again once it has enough
    if (p.rate == 0 && item.status == AVPlayerItemStatusReadyToPlay && item.playbackLikelyToKeepUp) [p play];
    // the repacking gave up (TikTok's CDN stopped answering): no use waiting for the player to notice
    if (self.repacked && now - self.lastProgress > 3 && ![[TKMediaProxy shared] liveStreamRunning]) {
        TKLog(@"live: the repacked stream stopped, opening it again");
        [self startAgainOrGiveUp:nil];
        return;
    }
    if (now - self.lastProgress > TKLiveStallLimit) {
        TKLog(@"live: no picture for %.0f s, opening the stream again", now - self.lastProgress);
        [self startAgainOrGiveUp:nil];
    }
}

+ (NSString *)debugState
{
    TKLivePlayerViewController *me = TKCurrentLive;
    if (!me || !me.onScreen) return @"no live screen";
    if (me.ended) return [NSString stringWithFormat:@"room %@ ended", me.roomId];
    if (!me.player) return me.messageLabel.hidden ? [NSString stringWithFormat:@"room %@ starting", me.roomId] : [NSString stringWithFormat:@"room %@: %@", me.roomId, me.messageLabel.text];
    AVPlayerItem *item = me.player.currentItem;
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    return [NSString stringWithFormat:@"room %@ @%@: %@, %@ at %.1f s, rate %.1f, item status %ld, restarts %ld%@",
            me.roomId, me.room.ownerHandle, me.playingSince ? [NSString stringWithFormat:@"playing %.0f s", now - me.playingSince] : @"waiting",
            me.streamDescription, CMTimeGetSeconds(me.player.currentTime), me.player.rate, (long)item.status, (long)me.restarts,
            item.error ? [NSString stringWithFormat:@", error %@", item.error.localizedDescription] : @""];
}

@end
