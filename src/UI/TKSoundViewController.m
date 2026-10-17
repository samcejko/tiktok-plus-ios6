#import "TKSoundViewController.h"
#import <AVFoundation/AVFoundation.h>
#import "TKLinkRouter.h"
#import "TKMediaProxy.h"
#import "TKTikTok.h"
#import "TKModels.h"
#import "TKImageLoader.h"
#import "TKTheme.h"
#import "TKUtils.h"
#import "TKCommon.h"

static const CGFloat TKCoverSize = 100;
static const CGFloat TKPlaySize = 46;

// iOS 6: the cover in a white frame with a glossy round play button on it, on the grained surface of the pages
@interface TKSoundHeaderView : TKPageHeaderView
@property (nonatomic, strong) TKFramedImageView *cover;
@property (nonatomic, strong) UIButton *playButton;       // over the cover: hear the sound
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIButton *authorButton;
@property (nonatomic, strong) UILabel *countsLabel;
- (void)showSound:(TKSound *)sound;
- (void)showPlaying:(BOOL)playing;
- (CGFloat)layoutForWidth:(CGFloat)width apply:(BOOL)apply;
@end

@implementation TKSoundHeaderView

- (instancetype)initWithFrame:(CGRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        TKTheme *theme = [TKTheme shared];
        _cover = [[TKFramedImageView alloc] initWithSize:TKCoverSize round:NO];
        _cover.userInteractionEnabled = NO;
        [self addSubview:_cover];
        _playButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _playButton.accessibilityLabel = L(@"Play");
        [_playButton setBackgroundImage:[theme roundButtonImageWithSize:TKPlaySize] forState:UIControlStateNormal];
        [self addSubview:_playButton];
        [self showPlaying:NO];
        _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleLabel.font = [UIFont boldSystemFontOfSize:19];
        _titleLabel.textColor = [theme embossTextColor];
        _titleLabel.backgroundColor = [UIColor clearColor];
        _titleLabel.numberOfLines = 2;
        [theme embossLabel:_titleLabel];
        [self addSubview:_titleLabel];
        _authorButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _authorButton.titleLabel.font = [UIFont boldSystemFontOfSize:15];
        _authorButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        [_authorButton setTitleColor:[theme linkColor] forState:UIControlStateNormal];
        [_authorButton setTitleColor:[theme secondaryTextColor] forState:UIControlStateHighlighted];
        [_authorButton setTitleColor:[theme secondaryTextColor] forState:UIControlStateDisabled];
        [theme embossButton:_authorButton];
        [self addSubview:_authorButton];
        _countsLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _countsLabel.font = [UIFont systemFontOfSize:14];
        _countsLabel.textColor = [theme secondaryTextColor];
        _countsLabel.backgroundColor = [UIColor clearColor];
        [theme embossLabel:_countsLabel];
        [self addSubview:_countsLabel];
    }
    return self;
}

- (void)showPlaying:(BOOL)playing
{
    [self.playButton setImage:playing ? [[TKTheme shared] pauseIcon] : [[TKTheme shared] playIcon] forState:UIControlStateNormal];
    self.playButton.imageEdgeInsets = playing ? UIEdgeInsetsZero : UIEdgeInsetsMake(0, 3, 0, 0);   // (a play sign looks centred a little right)
    self.playButton.accessibilityLabel = playing ? L(@"Pause") : L(@"Play");
}

- (void)showSound:(TKSound *)s
{
    [(TKImageView *)self.cover.imageView setImageURL:s.coverURL placeholder:nil];
    self.titleLabel.text = s.title.length ? [TKUtils displayText:s.title] : L(@"Sound");
    NSString *author = s.authorHandle.length ? [@"@" stringByAppendingString:s.authorHandle] : (s.author ?: @"");
    [self.authorButton setTitle:[TKUtils displayText:author] forState:UIControlStateNormal];
    self.authorButton.enabled = s.authorHandle.length > 0;
    NSMutableArray *parts = [NSMutableArray array];
    if (s.videoCount) [parts addObject:[NSString stringWithFormat:L(@"%@ videos"), [TKUtils formatBigCount:s.videoCount]]];
    if (s.original) [parts addObject:L(@"Original sound")];
    if (s.durationSeconds) [parts addObject:[TKUtils formatDuration:s.durationSeconds]];
    self.countsLabel.text = [parts componentsJoinedByString:@"  ·  "];
    self.playButton.hidden = !s.playURL.length;
    [self setNeedsLayout];
}

- (CGFloat)layoutForWidth:(CGFloat)w apply:(BOOL)apply
{
    CGFloat x = 18 + TKCoverSize + 16, textW = w - x - 16, y = 20;
    if (apply) {
        self.cover.frame = CGRectMake(18, y, TKCoverSize, TKCoverSize);
        self.playButton.frame = CGRectMake(CGRectGetMidX(self.cover.frame) - TKPlaySize / 2, CGRectGetMidY(self.cover.frame) - TKPlaySize / 2, TKPlaySize, TKPlaySize);
        CGSize t = [self.titleLabel.text ?: @"" sizeWithFont:self.titleLabel.font constrainedToSize:CGSizeMake(textW, 46) lineBreakMode:NSLineBreakByWordWrapping];
        CGFloat th = MAX(24, ceilf(t.height));
        self.titleLabel.frame = CGRectMake(x, y + 4, textW, th);
        self.authorButton.frame = CGRectMake(x, y + 6 + th, textW, 24);
        self.countsLabel.frame = CGRectMake(x, y + 32 + th, textW, 20);
    }
    return y + TKCoverSize + 20;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    [self layoutForWidth:self.bounds.size.width apply:YES];
}

@end

@interface TKSoundViewController ()
@property (nonatomic, copy) NSString *soundId;
@property (nonatomic, copy) NSString *givenTitle;
@property (nonatomic, strong) TKSound *sound;
@property (nonatomic, strong) TKSoundHeaderView *header;
@property (nonatomic) long long cursor;
@property (nonatomic, strong) AVPlayer *player;          // the sound itself, while it is heard
@end

@implementation TKSoundViewController

- (instancetype)initWithSoundId:(NSString *)soundId title:(NSString *)title
{
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _soundId = [soundId copy] ?: @"";
        _givenTitle = [title copy];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_player pause];
}

- (void)viewDidLoad
{
    self.title = self.givenTitle.length ? [TKUtils displayText:self.givenTitle] : L(@"Sound");
    [super viewDidLoad];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [self stopSound];      // (a video opened from the grid has its own sound)
}

- (TKHTTPTask *)fetchPageAfterFirst:(BOOL)more completion:(void (^)(NSArray *, BOOL, NSError *))completion
{
    return [TKTikTok sound:self.soundId cursor:more ? self.cursor : 0 completion:^(TKVideoPage *page, NSError *error) {
        if (!page) { completion(nil, NO, error); return; }
        if (!more && page.sound) {
            self.sound = page.sound;
            if (page.sound.title.length) self.title = [TKUtils displayText:page.sound.title];
            [self.header showSound:page.sound];
        }
        self.cursor = page.cursor;
        completion(page.videos, page.hasMore, nil);
    }];
}

- (UIView *)headerView
{
    if (!self.sound) return nil;
    if (!self.header) {
        self.header = [[TKSoundHeaderView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 130)];
        [self.header.playButton addTarget:self action:@selector(togglePlay) forControlEvents:UIControlEventTouchUpInside];
        [self.header.authorButton addTarget:self action:@selector(openAuthor) forControlEvents:UIControlEventTouchUpInside];
        [self.header showSound:self.sound];
    }
    return self.header;
}

- (CGFloat)headerHeightForWidth:(CGFloat)width { return [(TKSoundHeaderView *)[self headerView] layoutForWidth:width apply:NO]; }
- (NSString *)emptyMessage { return self.sound ? L(@"No videos to show.") : L(@"This sound was not found."); }
- (NSString *)feedTitle { return self.title; }

- (void)openAuthor
{
    if (self.sound.authorHandle.length) [TKLinkRouter openProfile:self.sound.authorHandle];
}

#pragma mark - Hearing it

- (void)togglePlay
{
    if (self.player) { [self stopSound]; return; }
    if (!self.sound.playURL.length) return;
    TKMediaProxy *proxy = [TKMediaProxy shared];
    [proxy ensureRunning];
    NSString *local = [proxy proxyURLForURL:[NSURL URLWithString:self.sound.playURL] upstreamHeaders:self.sound.headers];
    if (!local) return;
    self.player = [AVPlayer playerWithURL:[NSURL URLWithString:local]];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(soundEnded:) name:AVPlayerItemDidPlayToEndTimeNotification object:self.player.currentItem];
    [self.player play];
    [self.header showPlaying:YES];
}

- (void)soundEnded:(NSNotification *)note
{
    if (note.object == self.player.currentItem) [self stopSound];
}

- (void)stopSound
{
    if (!self.player) return;
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:nil];
    [self.player pause];
    self.player = nil;
    [self.header showPlaying:NO];
}

@end
