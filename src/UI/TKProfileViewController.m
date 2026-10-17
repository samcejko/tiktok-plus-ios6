#import "TKProfileViewController.h"
#import "TKLinkRouter.h"
#import "TKLinkLabel.h"
#import "TKTikTok.h"
#import "TKModels.h"
#import "TKSession.h"
#import "TKSettings.h"
#import "TKImageLoader.h"
#import "TKTheme.h"
#import "TKUtils.h"
#import "TKCommon.h"

static const CGFloat TKAvatarSize = 100;
static const CGFloat TKStatsHeight = 52;

#pragma mark - Header

// iOS 6: the avatar in a white frame on a grained surface, the counts on a glossy card, glossy buttons
@interface TKProfileHeaderView : TKPageHeaderView
@property (nonatomic, strong) TKProfile *profile;
@property (nonatomic, strong) TKFramedImageView *avatar;
@property (nonatomic, strong) UILabel *handleLabel;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UIImageView *statsCard;
@property (nonatomic, strong) NSArray *valueLabels;       // following, followers, likes
@property (nonatomic, strong) NSArray *captionLabels;
@property (nonatomic, strong) NSArray *dividers;          // etched: a dark and a light line each
@property (nonatomic, strong) UIButton *liveButton;
@property (nonatomic, strong) UIButton *followButton;
@property (nonatomic, strong) TKLinkLabel *bioLabel;      // (the web links in the bio open on a tap)
@property (nonatomic, strong) UIButton *linkButton;
- (CGFloat)layoutForWidth:(CGFloat)width apply:(BOOL)apply;
@end

@implementation TKProfileHeaderView

- (UILabel *)label:(UIFont *)font color:(UIColor *)color in:(UIView *)parent
{
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectZero];
    l.font = font;
    l.textColor = color;
    l.textAlignment = NSTextAlignmentCenter;
    l.backgroundColor = [UIColor clearColor];
    [parent addSubview:l];
    return l;
}

- (instancetype)initWithFrame:(CGRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        TKTheme *theme = [TKTheme shared];
        _avatar = [[TKFramedImageView alloc] initWithSize:TKAvatarSize round:YES];
        [self addSubview:_avatar];
        _handleLabel = [self label:[UIFont boldSystemFontOfSize:19] color:[theme embossTextColor] in:self];
        [theme embossLabel:_handleLabel];
        _nameLabel = [self label:[UIFont systemFontOfSize:14] color:[theme secondaryTextColor] in:self];
        [theme embossLabel:_nameLabel];

        _statsCard = [[UIImageView alloc] initWithImage:[theme cardBackgroundImage]];
        [self addSubview:_statsCard];
        NSMutableArray *values = [NSMutableArray array], *captions = [NSMutableArray array], *dividers = [NSMutableArray array];
        for (NSString *caption in @[ L(@"Following"), L(@"Followers"), L(@"Likes") ]) {
            UILabel *v = [self label:[UIFont boldSystemFontOfSize:17] color:[theme primaryTextColor] in:_statsCard];
            [theme embossLabel:v];
            [values addObject:v];
            UILabel *c = [self label:[UIFont boldSystemFontOfSize:11] color:[theme secondaryTextColor] in:_statsCard];
            c.text = [caption uppercaseString];
            [theme embossLabel:c];
            [captions addObject:c];
        }
        for (int i = 0; i < 4; i++) {
            UIView *d = [[UIView alloc] initWithFrame:CGRectZero];
            d.backgroundColor = (i % 2 == 0) ? [UIColor colorWithWhite:0 alpha:theme.isDark ? 0.55 : 0.18]
                                             : [UIColor colorWithWhite:1 alpha:theme.isDark ? 0.07 : 0.8];
            [_statsCard addSubview:d];
            [dividers addObject:d];
        }
        _valueLabels = values;
        _captionLabels = captions;
        _dividers = dividers;

        _liveButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _liveButton.titleLabel.font = [UIFont boldSystemFontOfSize:15];
        [_liveButton setBackgroundImage:[theme redButtonImageHighlighted:NO] forState:UIControlStateNormal];
        [_liveButton setBackgroundImage:[theme redButtonImageHighlighted:YES] forState:UIControlStateHighlighted];
        [_liveButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [_liveButton setTitleShadowColor:[UIColor colorWithWhite:0 alpha:0.45] forState:UIControlStateNormal];
        _liveButton.titleLabel.shadowOffset = CGSizeMake(0, -1);
        [_liveButton setTitle:[@"●  " stringByAppendingString:L(@"Watch live")] forState:UIControlStateNormal];
        [self addSubview:_liveButton];

        _followButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _followButton.titleLabel.font = [UIFont boldSystemFontOfSize:15];
        [_followButton setBackgroundImage:[theme buttonImageHighlighted:NO] forState:UIControlStateNormal];
        [_followButton setBackgroundImage:[theme buttonImageHighlighted:YES] forState:UIControlStateHighlighted];
        [_followButton setTitleColor:[theme primaryTextColor] forState:UIControlStateNormal];
        [theme embossButton:_followButton];
        [_followButton setTitle:L(@"Follow") forState:UIControlStateNormal];
        _followButton.hidden = YES;
        [self addSubview:_followButton];

        _bioLabel = [[TKLinkLabel alloc] initWithFrame:CGRectZero];
        _bioLabel.font = [UIFont systemFontOfSize:14];
        _bioLabel.textColor = [theme embossTextColor];
        _bioLabel.textAlignment = NSTextAlignmentCenter;
        _bioLabel.backgroundColor = [UIColor clearColor];
        _bioLabel.numberOfLines = 6;
        [theme embossLabel:_bioLabel];
        [self addSubview:_bioLabel];

        _linkButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _linkButton.titleLabel.font = [UIFont boldSystemFontOfSize:13];
        _linkButton.titleLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        _linkButton.contentEdgeInsets = UIEdgeInsetsMake(0, 12, 0, 12);
        [_linkButton setBackgroundImage:[theme buttonImageHighlighted:NO] forState:UIControlStateNormal];
        [_linkButton setBackgroundImage:[theme buttonImageHighlighted:YES] forState:UIControlStateHighlighted];
        [_linkButton setTitleColor:[theme embossTextColor] forState:UIControlStateNormal];
        [theme embossButton:_linkButton];
        [self addSubview:_linkButton];
    }
    return self;
}

- (void)setProfile:(TKProfile *)p
{
    _profile = p;
    TKImageView *picture = self.avatar.imageView;
    [picture setImageURL:p.avatarURL placeholder:nil];
    self.avatar.backgroundColor = p.liveRoom.length ? [[TKTheme shared] liveColor] : [UIColor whiteColor];   // (a red frame: live)
    NSString *handle = [@"@" stringByAppendingString:p.handle ?: @""];
    self.handleLabel.text = p.verified ? [handle stringByAppendingString:@" ✓"] : handle;
    self.nameLabel.text = p.name.length ? [TKUtils displayText:p.name] : @"";
    NSArray *counts = @[ @(p.following), @(p.followers), @(p.likes) ];
    for (NSUInteger i = 0; i < 3; i++) [self.valueLabels[i] setText:[TKUtils formatBigCount:[counts[i] longLongValue]]];
    self.liveButton.hidden = !p.liveRoom.length;
    BOOL isMe = [TKSession sharedSession].signedIn && [p.handle isEqualToString:[TKSession sharedSession].handle];
    self.followButton.hidden = ![TKSession sharedSession].signedIn || isMe;
    self.bioLabel.text = p.bio.length ? [TKUtils displayText:p.bio] : @"";
    NSString *link = [p.link stringByReplacingOccurrencesOfString:@"https://" withString:@""];
    link = [link stringByReplacingOccurrencesOfString:@"http://" withString:@""];
    [self.linkButton setTitle:link.length ? [@"🔗 " stringByAppendingString:link] : nil forState:UIControlStateNormal];
    self.linkButton.hidden = !link.length;
    [self setNeedsLayout];
}

// The same arithmetic measures and places, so the grid's header is exactly as tall as what is drawn
- (CGFloat)layoutForWidth:(CGFloat)w apply:(BOOL)apply
{
    CGFloat y = 20;
    if (apply) self.avatar.frame = CGRectMake(floorf((w - TKAvatarSize) / 2), y, TKAvatarSize, TKAvatarSize);
    y += TKAvatarSize + 12;
    if (apply) self.handleLabel.frame = CGRectMake(16, y, w - 32, 24);
    y += 25;
    if (self.nameLabel.text.length) {
        if (apply) self.nameLabel.frame = CGRectMake(16, y, w - 32, 18);
        y += 20;
    }
    y += 12;
    CGFloat cardW = MIN(w - 32, 360), colW = floorf(cardW / 3);
    if (apply) {
        self.statsCard.frame = CGRectMake(floorf((w - cardW) / 2), y, cardW, TKStatsHeight);
        for (NSUInteger i = 0; i < 3; i++) {
            [self.valueLabels[i] setFrame:CGRectMake(colW * i, 8, colW, 21)];
            [self.captionLabels[i] setFrame:CGRectMake(colW * i, 29, colW, 14)];
        }
        for (NSUInteger i = 0; i < 2; i++) {
            [self.dividers[i * 2] setFrame:CGRectMake(colW * (i + 1), 9, 1, TKStatsHeight - 18)];
            [self.dividers[i * 2 + 1] setFrame:CGRectMake(colW * (i + 1) + 1, 9, 1, TKStatsHeight - 18)];
        }
    }
    y += TKStatsHeight + 14;
    BOOL showLive = !self.liveButton.hidden;
    BOOL showFollow = !self.followButton.hidden;
    if (showLive && showFollow) {
        CGFloat bw = 135;
        CGFloat startX = floorf((w - (bw * 2 + 12)) / 2);
        if (apply) {
            self.followButton.frame = CGRectMake(startX, y, bw, 38);
            self.liveButton.frame = CGRectMake(startX + bw + 12, y, bw, 38);
        }
        y += 38 + 12;
    } else if (showLive) {
        if (apply) self.liveButton.frame = CGRectMake(floorf((w - 220) / 2), y, 220, 38);
        y += 38 + 12;
    } else if (showFollow) {
        if (apply) self.followButton.frame = CGRectMake(floorf((w - 220) / 2), y, 220, 38);
        y += 38 + 12;
    }
    if (self.bioLabel.text.length) {
        CGFloat bw = MIN(w - 40, 520);
        CGSize s = [self.bioLabel.text sizeWithFont:self.bioLabel.font constrainedToSize:CGSizeMake(bw, 6 * 18) lineBreakMode:NSLineBreakByWordWrapping];
        if (apply) self.bioLabel.frame = CGRectMake(floorf((w - bw) / 2), y, bw, ceilf(s.height));
        y += ceilf(s.height) + 10;
    }
    if (!self.linkButton.hidden) {
        CGSize t = [[self.linkButton titleForState:UIControlStateNormal] ?: @"" sizeWithFont:self.linkButton.titleLabel.font];
        CGFloat lw = MIN(w - 40, ceilf(t.width) + 26);
        if (apply) self.linkButton.frame = CGRectMake(floorf((w - lw) / 2), y, lw, 30);
        y += 30 + 8;
    }
    return y + 10;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    [self layoutForWidth:self.bounds.size.width apply:YES];
}

@end

#pragma mark - Controller

@interface TKProfileViewController ()
@property (nonatomic, copy) NSString *handle;
@property (nonatomic, strong) TKProfile *profile;
@property (nonatomic, strong) TKProfileHeaderView *header;
@property (nonatomic) long long cursor;
@end

@implementation TKProfileViewController

- (instancetype)initWithHandle:(NSString *)handle
{
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _handle = [handle hasPrefix:@"@"] ? [handle substringFromIndex:1] : (handle ?: @"");
    }
    return self;
}

- (void)viewDidLoad
{
    self.title = [@"@" stringByAppendingString:self.handle];
    [super viewDidLoad];
}

- (TKHTTPTask *)fetchPageAfterFirst:(BOOL)more completion:(void (^)(NSArray *, BOOL, NSError *))completion
{
    if (more) {
        return [TKTikTok postsOf:self.profile cursor:self.cursor completion:^(TKVideoPage *page, NSError *error) {
            if (page) self.cursor = page.cursor;
            completion(page.videos, page.hasMore && page.cursor > 0, error);
        }];
    }
    return [TKTikTok profileForUser:self.handle completion:^(TKProfile *profile, NSError *error) {
        if (!profile) { completion(nil, NO, error ?: TKMakeError(TKErrorBadResponse, L(@"This profile could not be loaded."))); return; }
        self.profile = profile;
        self.cursor = profile.postsCursor;
        if (profile.name.length) self.title = [TKUtils displayText:profile.name];
        self.header.profile = profile;
        completion(profile.videos, profile.hasMorePosts && profile.secUid.length > 0, nil);
    }];
}

- (UIView *)headerView
{
    if (!self.profile) return nil;
    if (!self.header) {
        self.header = [[TKProfileHeaderView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 300)];
        [self.header.liveButton addTarget:self action:@selector(openLive) forControlEvents:UIControlEventTouchUpInside];
        [self.header.followButton addTarget:self action:@selector(toggleFollow) forControlEvents:UIControlEventTouchUpInside];
        [self.header.linkButton addTarget:self action:@selector(openBioLink) forControlEvents:UIControlEventTouchUpInside];
        self.header.profile = self.profile;
    }
    return self.header;
}

- (void)toggleFollow
{
    if (![TKSettings allowAccountWrites]) {
        [TKUtils alertWithTitle:L(@"Actions disabled") message:L(@"Enable 'Allow actions on account' in Settings to follow creators.")];
        return;
    }
    BOOL isFollowing = [self.header.followButton.currentTitle isEqualToString:L(@"Following")];
    NSInteger type = isFollowing ? 2 : 1;
    self.header.followButton.enabled = NO;
    [TKTikTok followUserId:self.profile.userId secUid:self.profile.secUid type:type completion:^(BOOL ok, NSError *error) {
        self.header.followButton.enabled = YES;
        if (ok) {
            [self.header.followButton setTitle:isFollowing ? L(@"Follow") : L(@"Following") forState:UIControlStateNormal];
        } else {
            [TKUtils alertWithTitle:L(@"Failed") message:error.localizedDescription ?: L(@"Could not update follow status.")];
        }
    }];
}

- (CGFloat)headerHeightForWidth:(CGFloat)width { return [(TKProfileHeaderView *)[self headerView] layoutForWidth:width apply:NO]; }

- (NSString *)emptyMessage { return self.profile.isPrivate ? L(@"This account is private.") : L(@"No public posts to show."); }
- (NSString *)feedTitle { return [@"@" stringByAppendingString:self.profile.handle.length ? self.profile.handle : self.handle]; }

- (void)openLive
{
    if (self.profile.liveRoom.length) [TKLinkRouter openLiveRoom:self.profile.liveRoom];
}

// The link field: a TikTok link opens here, the rest where it leads (a sister app, a browser - iOS 6 asks which)
- (void)openBioLink
{
    if (self.profile.link.length) [TKLinkRouter openWebLink:self.profile.link from:self anchor:self.header.linkButton];
}

@end
