#import "TKTopicsViewController.h"
#import "TKTaste.h"
#import "TKSettings.h"
#import "TKTheme.h"
#import "TKCommon.h"

static const CGFloat TKChipHeight = 38;
static const CGFloat TKChipGap = 10;

@interface TKTopicsViewController ()
@property (nonatomic, strong) UIImageView *backdrop;
@property (nonatomic, strong) UIView *grain;
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) NSArray *chips;            // UIButton, tag = topic id
@property (nonatomic, strong) NSMutableSet *picked;      // NSNumber topic ids
@property (nonatomic, strong) UIButton *continueButton;
@property (nonatomic, strong) UIButton *skipButton;
@end

@implementation TKTopicsViewController

- (BOOL)pushed { return self.navigationController.viewControllers.count > 1; }

- (void)viewDidLoad
{
    [super viewDidLoad];
    TKTheme *theme = [TKTheme shared];
    self.title = L(@"Topics");
    self.view.backgroundColor = [theme backgroundColor];
    self.picked = [NSMutableSet set];

    // a shaded, finely grained surface (iOS 6)
    self.backdrop = [[UIImageView alloc] initWithImage:[theme pageBackgroundImage]];
    self.backdrop.frame = self.view.bounds;
    self.backdrop.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.backdrop];
    self.grain = [[UIView alloc] initWithFrame:self.view.bounds];
    self.grain.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.grain.backgroundColor = [theme grainColor];
    self.grain.userInteractionEnabled = NO;
    [self.view addSubview:self.grain];

    self.scroll = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.scroll.backgroundColor = [UIColor clearColor];
    self.scroll.alwaysBounceVertical = YES;
    [self.view addSubview:self.scroll];

    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.titleLabel.text = L(@"What do you enjoy?");
    self.titleLabel.font = [UIFont boldSystemFontOfSize:TKIsPad() ? 30 : 25];
    self.titleLabel.textColor = [theme embossTextColor];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.backgroundColor = [UIColor clearColor];
    [theme embossLabel:self.titleLabel];
    [self.scroll addSubview:self.titleLabel];

    self.subtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.subtitleLabel.text = L(@"Pick a few topics so the feed hits the mark from the start. It goes on learning from how you watch.");
    self.subtitleLabel.font = [UIFont systemFontOfSize:15];
    self.subtitleLabel.textColor = [theme secondaryTextColor];
    self.subtitleLabel.textAlignment = NSTextAlignmentCenter;
    self.subtitleLabel.numberOfLines = 0;
    self.subtitleLabel.backgroundColor = [UIColor clearColor];
    [theme embossLabel:self.subtitleLabel];
    [self.scroll addSubview:self.subtitleLabel];

    NSMutableArray *chips = [NSMutableArray array];
    for (NSNumber *t in [TKTaste topicIds]) {
        UIButton *chip = [UIButton buttonWithType:UIButtonTypeCustom];
        chip.tag = t.integerValue;
        chip.titleLabel.font = [UIFont boldSystemFontOfSize:15];
        [chip setTitle:[TKTaste localizedTopicName:t.integerValue] forState:UIControlStateNormal];
        chip.adjustsImageWhenHighlighted = NO;
        [chip addTarget:self action:@selector(chipTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.scroll addSubview:chip];
        [chips addObject:chip];
    }
    self.chips = chips;

    self.continueButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.continueButton.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    [self.continueButton setBackgroundImage:[theme accentButtonImageHighlighted:NO disabled:NO] forState:UIControlStateNormal];
    [self.continueButton setBackgroundImage:[theme accentButtonImageHighlighted:YES disabled:NO] forState:UIControlStateHighlighted];
    [self.continueButton setBackgroundImage:[theme accentButtonImageHighlighted:NO disabled:YES] forState:UIControlStateDisabled];
    [self.continueButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [self.continueButton setTitleColor:[UIColor colorWithWhite:1 alpha:0.75] forState:UIControlStateDisabled];
    [self.continueButton setTitleShadowColor:[UIColor colorWithWhite:0 alpha:0.45] forState:UIControlStateNormal];
    self.continueButton.titleLabel.shadowOffset = CGSizeMake(0, -1);
    [self.continueButton addTarget:self action:@selector(confirm) forControlEvents:UIControlEventTouchUpInside];
    [self.scroll addSubview:self.continueButton];

    self.skipButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.skipButton.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [self.skipButton setTitle:L(@"Skip") forState:UIControlStateNormal];
    [self.skipButton setTitleColor:[theme secondaryTextColor] forState:UIControlStateNormal];
    [self.skipButton setTitleColor:[theme embossTextColor] forState:UIControlStateHighlighted];
    [theme embossButton:self.skipButton];
    [self.skipButton addTarget:self action:@selector(skip) forControlEvents:UIControlEventTouchUpInside];
    [self.scroll addSubview:self.skipButton];

    [self refreshChips];
}

- (BOOL)shouldAutorotate { return YES; }
- (NSUInteger)supportedInterfaceOrientations { return TKIsPad() ? UIInterfaceOrientationMaskAll : UIInterfaceOrientationMaskPortrait; }

- (void)viewWillLayoutSubviews
{
    [super viewWillLayoutSubviews];
    CGFloat w = self.view.bounds.size.width, h = self.view.bounds.size.height;
    CGFloat height = [self layoutFromY:0 apply:NO];
    CGFloat top = MAX([self pushed] ? 22 : 30, floorf((h - height) * 0.42));    // (centred a little above the middle)
    self.scroll.contentSize = CGSizeMake(w, [self layoutFromY:top apply:YES] + 24);
}

// Everything top to bottom from y; returns where it ends
- (CGFloat)layoutFromY:(CGFloat)y apply:(BOOL)apply
{
    CGFloat w = self.view.bounds.size.width, inner = MIN(w - 32, 620), left = floorf((w - inner) / 2);
    if (apply) self.titleLabel.frame = CGRectMake(left, y, inner, 36);
    y += 46;
    CGSize s = [self.subtitleLabel.text sizeWithFont:self.subtitleLabel.font constrainedToSize:CGSizeMake(MIN(inner, 520), 200) lineBreakMode:NSLineBreakByWordWrapping];
    if (apply) self.subtitleLabel.frame = CGRectMake(floorf((w - MIN(inner, 520)) / 2), y, MIN(inner, 520), ceilf(s.height));
    y += ceilf(s.height) + 28;
    // the capsules flow in centred rows
    NSMutableArray *row = [NSMutableArray array];
    CGFloat rowW = 0;
    for (UIButton *chip in self.chips) {
        CGFloat cw = ceilf([[chip titleForState:UIControlStateNormal] sizeWithFont:chip.titleLabel.font].width) + 34;
        chip.bounds = CGRectMake(0, 0, cw, TKChipHeight);
        CGFloat need = row.count ? rowW + TKChipGap + cw : cw;
        if (row.count && need > inner) {
            if (apply) [self placeRow:row width:rowW left:left inner:inner y:y];
            y += TKChipHeight + TKChipGap;
            [row removeAllObjects];
            need = cw;
        }
        [row addObject:chip];
        rowW = need;
    }
    if (row.count) {
        if (apply) [self placeRow:row width:rowW left:left inner:inner y:y];
        y += TKChipHeight;
    }
    y += 32;
    CGFloat bw = MIN(inner, 320);
    if (apply) self.continueButton.frame = CGRectMake(floorf((w - bw) / 2), y, bw, 46);
    y += 46 + 10;
    self.skipButton.hidden = [self pushed];
    if (!self.skipButton.hidden) {
        if (apply) self.skipButton.frame = CGRectMake(floorf((w - 200) / 2), y, 200, 36);
        y += 36;
    }
    return y;
}

- (void)placeRow:(NSArray *)row width:(CGFloat)rowW left:(CGFloat)left inner:(CGFloat)inner y:(CGFloat)y
{
    CGFloat x = left + floorf((inner - rowW) / 2);
    for (UIButton *b in row) {
        b.frame = CGRectMake(x, y, b.bounds.size.width, b.bounds.size.height);
        x += b.bounds.size.width + TKChipGap;
    }
}

- (void)chipTapped:(UIButton *)chip
{
    NSNumber *t = @(chip.tag);
    if ([self.picked containsObject:t]) [self.picked removeObject:t]; else [self.picked addObject:t];
    [self refreshChips];
}

// Chosen capsules turn glossy pink with white text; the others stay glossy grey
- (void)refreshChips
{
    TKTheme *theme = [TKTheme shared];
    for (UIButton *chip in self.chips) {
        BOOL on = [self.picked containsObject:@(chip.tag)];
        [chip setBackgroundImage:[theme capsuleImageSelected:on highlighted:NO height:TKChipHeight] forState:UIControlStateNormal];
        [chip setBackgroundImage:[theme capsuleImageSelected:on highlighted:YES height:TKChipHeight] forState:UIControlStateHighlighted];
        [chip setTitleColor:on ? [UIColor whiteColor] : [theme embossTextColor] forState:UIControlStateNormal];
        if (on) {
            [chip setTitleShadowColor:[UIColor colorWithRed:0.4 green:0 blue:0.1 alpha:0.6] forState:UIControlStateNormal];
            chip.titleLabel.shadowOffset = CGSizeMake(0, -1);
        } else {
            [theme embossButton:chip];
        }
    }
    NSUInteger n = self.picked.count;
    self.continueButton.enabled = n > 0;
    [self.continueButton setTitle:n ? [NSString stringWithFormat:L(@"Continue (%lu)"), (unsigned long)n] : L(@"Continue")
                         forState:UIControlStateNormal];
}

- (void)confirm
{
    if (!self.picked.count) return;
    NSArray *ids = [[self.picked allObjects] sortedArrayUsingSelector:@selector(compare:)];
    [[TKTaste shared] seedTopics:ids];
    [TKSettings setTopicsChosen:YES];
    [TKSettings save];
    dispatch_block_t picked = self.onPicked;
    [self leave];
    if (picked) picked();
}

- (void)skip
{
    [TKSettings setTopicsChosen:YES];
    [TKSettings save];
    [self leave];
}

- (void)leave
{
    if ([self pushed]) [self.navigationController popViewControllerAnimated:YES];
    else [self dismissViewControllerAnimated:YES completion:nil];
}

@end
