#import "TKBottomSheet.h"
#import <QuartzCore/QuartzCore.h>
#import "TKTheme.h"
#import "TKCommon.h"

static const CGFloat TKSheetBarHeight = 44;

@interface TKBottomSheet ()
@property (nonatomic, strong) UIView *dimView;
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UINavigationBar *bar;       // the iOS 6 bar: the title and a Close button
@property (nonatomic, strong) UINavigationItem *barItem;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) CAShapeLayer *corners;
@property (nonatomic) BOOL shown;          // up (not coming or going)
@property (nonatomic) BOOL dragging;
@property (nonatomic) BOOL closing;
@end

@implementation TKBottomSheet

- (instancetype)initWithFrame:(CGRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        TKTheme *theme = [TKTheme shared];
        _heightFraction = 0.68;
        self.backgroundColor = [UIColor clearColor];
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

        _dimView = [[UIView alloc] initWithFrame:self.bounds];
        _dimView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _dimView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.25];
        _dimView.alpha = 0;
        [_dimView addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(close)]];
        [self addSubview:_dimView];

        // the panel casts a shadow up onto the video; its top corners are rounded like an iOS 6 sheet
        _panel = [[UIView alloc] initWithFrame:CGRectZero];
        _panel.backgroundColor = [UIColor clearColor];
        _panel.layer.shadowColor = [UIColor blackColor].CGColor;
        _panel.layer.shadowOpacity = 0.6;
        _panel.layer.shadowRadius = 6;
        _panel.layer.shadowOffset = CGSizeMake(0, -2);
        [self addSubview:_panel];
        UIView *clip = [[UIView alloc] initWithFrame:CGRectZero];
        clip.tag = 1;
        clip.backgroundColor = [theme cardColor];
        _corners = [CAShapeLayer layer];
        clip.layer.mask = _corners;
        [_panel addSubview:clip];

        _bar = [[UINavigationBar alloc] initWithFrame:CGRectZero];
        [theme applyToNavigationBar:_bar];
        _barItem = [[UINavigationItem alloc] initWithTitle:@""];
        _barItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:L(@"Close") style:UIBarButtonItemStyleBordered target:self action:@selector(close)];
        [_bar pushNavigationItem:_barItem animated:NO];
        [clip addSubview:_bar];

        _contentView = [[UIView alloc] initWithFrame:CGRectZero];
        _contentView.backgroundColor = [theme cardColor];
        _contentView.clipsToBounds = YES;
        [clip addSubview:_contentView];

        [_bar addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panned:)]];
    }
    return self;
}

- (void)setTitle:(NSString *)title
{
    _title = [title copy];
    self.barItem.title = title;
}

- (CGFloat)panelHeight { return floorf(self.bounds.size.height * self.heightFraction); }
- (CGFloat)restY { return self.bounds.size.height - [self panelHeight]; }

- (void)layoutSubviews
{
    [super layoutSubviews];
    CGSize s = self.bounds.size;
    CGFloat h = [self panelHeight];
    CGFloat y = self.dragging ? self.panel.frame.origin.y : (self.shown ? [self restY] : s.height);
    self.panel.frame = CGRectMake(0, y, s.width, h);
    UIView *clip = [self.panel viewWithTag:1];
    clip.frame = self.panel.bounds;
    self.bar.frame = CGRectMake(0, 0, s.width, TKSheetBarHeight);
    self.contentView.frame = CGRectMake(0, TKSheetBarHeight, s.width, h - TKSheetBarHeight);
    UIBezierPath *shape = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, s.width, h) byRoundingCorners:UIRectCornerTopLeft | UIRectCornerTopRight
                                                      cornerRadii:CGSizeMake(8, 8)];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.corners.path = shape.CGPath;
    self.panel.layer.shadowPath = shape.CGPath;
    [CATransaction commit];
}

- (void)showInView:(UIView *)host
{
    self.frame = host.bounds;
    [host addSubview:self];
    self.shown = NO;
    [self layoutIfNeeded];
    self.shown = YES;
    [UIView animateWithDuration:0.28 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.dimView.alpha = 1;
        [self layoutSubviews];
    } completion:nil];
}

- (void)close
{
    if (self.closing) return;
    self.closing = YES;
    self.shown = NO;
    self.dragging = NO;
    [UIView animateWithDuration:0.24 delay:0 options:UIViewAnimationOptionCurveEaseIn | UIViewAnimationOptionBeginFromCurrentState animations:^{
        self.dimView.alpha = 0;
        [self layoutSubviews];
    } completion:^(BOOL finished) {
        [self removeFromSuperview];
        if (self.onClose) self.onClose();
        self.onClose = nil;
    }];
}

// Drag the bar down to put the sheet away
- (void)panned:(UIPanGestureRecognizer *)g
{
    if (self.closing) return;
    CGFloat h = [self panelHeight], rest = [self restY];
    CGFloat dy = MAX(0, [g translationInView:self].y);
    if (g.state == UIGestureRecognizerStateBegan || g.state == UIGestureRecognizerStateChanged) {
        self.dragging = YES;
        CGRect f = self.panel.frame;
        f.origin.y = rest + dy;
        self.panel.frame = f;
        self.dimView.alpha = 1 - MIN(1, dy / h);
        return;
    }
    self.dragging = NO;
    if (dy > h * 0.3 || [g velocityInView:self].y > 700) { [self close]; return; }
    [UIView animateWithDuration:0.2 animations:^{
        self.dimView.alpha = 1;
        [self layoutSubviews];
    }];
}

@end
