#import "TKActionSheet.h"
#import "TKTheme.h"
#import "TKModern.h"
#import "TKCommon.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

@interface TKChoiceHandler : NSObject <UIActionSheetDelegate>
@property (nonatomic, copy) void (^selection)(NSInteger);
@end
@implementation TKChoiceHandler
- (void)actionSheet:(UIActionSheet *)sheet didDismissWithButtonIndex:(NSInteger)index
{
    if (index >= 0 && index < sheet.numberOfButtons && index != sheet.cancelButtonIndex && self.selection) self.selection(index);
    self.selection = nil;
}
@end

@interface TKActionSheet ()
@property (nonatomic) BOOL classicVisible;
@property (nonatomic) BOOL closing;
@property (nonatomic, strong) UIView *classicPanel;
@property (nonatomic, strong) UIScrollView *choices;
@property (nonatomic, strong) UILabel *heading;
@property (nonatomic, strong) CAGradientLayer *gradient;
@property (nonatomic, strong) NSMutableArray *choiceButtons;
@end

@implementation TKActionSheet
- (BOOL)usesClassicSheet { return TKModernIOS() || self.numberOfButtons > 9; }
+ (void)options:(NSArray *)options title:(NSString *)title inView:(UIView *)view selection:(void (^)(NSInteger))selection
{
    if (!options.count || !view.window) return;
    TKChoiceHandler *handler = [[TKChoiceHandler alloc] init];
    handler.selection = selection;
    TKActionSheet *sheet = [[self alloc] initWithTitle:title delegate:handler cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil];
    objc_setAssociatedObject(sheet, @selector(options:title:inView:selection:), handler, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    for (NSString *option in options) [sheet addButtonWithTitle:option];
    sheet.cancelButtonIndex = [sheet addButtonWithTitle:L(@"Cancel")];
    if (TKIsPad()) [sheet showFromRect:CGRectMake(view.bounds.size.width / 2, view.bounds.size.height / 2, 1, 1) inView:view animated:YES];
    else [sheet showInView:view];
}
- (BOOL)isVisible { return [self usesClassicSheet] ? self.classicVisible : [super isVisible]; }

- (void)showInView:(UIView *)view
{
    if (![self usesClassicSheet]) { [super showInView:view]; return; }
    if (self.classicVisible) return;
    UIView *host = TKModernIOS() ? (view.window ?: view) : view;
    for (UIView *sub in [self.subviews copy]) [sub removeFromSuperview];
    self.frame = host.bounds;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45];
    self.classicVisible = YES;
    self.closing = NO;
    self.accessibilityViewIsModal = YES;
    UIControl *backdrop = [[UIControl alloc] initWithFrame:self.bounds];
    backdrop.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [backdrop addTarget:self action:@selector(cancel) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:backdrop];
    self.classicPanel = [[UIView alloc] initWithFrame:CGRectZero];
    self.classicPanel.backgroundColor = [UIColor colorWithWhite:0.18 alpha:1];
    self.classicPanel.layer.cornerRadius = 10;
    self.classicPanel.layer.borderWidth = 1;
    self.classicPanel.layer.borderColor = [UIColor colorWithWhite:0.7 alpha:0.8].CGColor;
    self.classicPanel.layer.shadowColor = [UIColor blackColor].CGColor;
    self.classicPanel.layer.shadowOpacity = 0.7;
    self.classicPanel.layer.shadowRadius = 8;
    [self addSubview:self.classicPanel];
    self.gradient = [CAGradientLayer layer];
    self.gradient.colors = @[(id)[UIColor colorWithWhite:0.38 alpha:1].CGColor, (id)[UIColor colorWithWhite:0.13 alpha:1].CGColor];
    self.gradient.cornerRadius = 10;
    [self.classicPanel.layer addSublayer:self.gradient];
    self.choices = [[UIScrollView alloc] initWithFrame:CGRectZero];
    self.choices.bounces = NO;
    [self.classicPanel addSubview:self.choices];
    if (self.title.length) {
        self.heading = [[UILabel alloc] initWithFrame:CGRectZero];
        self.heading.text = self.title;
        self.heading.textColor = [UIColor whiteColor];
        self.heading.font = [UIFont boldSystemFontOfSize:14];
        self.heading.textAlignment = NSTextAlignmentCenter;
        self.heading.backgroundColor = [UIColor clearColor];
        self.heading.numberOfLines = 0;
        [self.choices addSubview:self.heading];
    }
    self.choiceButtons = [NSMutableArray array];
    TKTheme *theme = [TKTheme shared];
    for (NSInteger i = 0; i < self.numberOfButtons; i++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.tag = i;
        [button setTitle:[self buttonTitleAtIndex:i] forState:UIControlStateNormal];
        [button setTitleColor:[theme primaryTextColor] forState:UIControlStateNormal];
        button.titleLabel.font = [UIFont boldSystemFontOfSize:18];
        button.titleLabel.adjustsFontSizeToFitWidth = YES;
        button.contentEdgeInsets = UIEdgeInsetsMake(0, 10, 0, 10);
        [button setBackgroundImage:[theme buttonImageHighlighted:NO] forState:UIControlStateNormal];
        [button setBackgroundImage:[theme buttonImageHighlighted:YES] forState:UIControlStateHighlighted];
        [button addTarget:self action:@selector(chose:) forControlEvents:UIControlEventTouchUpInside];
        [self.choices addSubview:button];
        [self.choiceButtons addObject:button];
    }
    [host addSubview:self];
    [self setNeedsLayout]; [self layoutIfNeeded];
    self.alpha = 0;
    [UIView animateWithDuration:0.18 animations:^{ self.alpha = 1; }];
    UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, self.heading ?: TKFirst(self.choiceButtons));
}

- (void)showFromRect:(CGRect)rect inView:(UIView *)view animated:(BOOL)animated
{
    if ([self usesClassicSheet]) [self showInView:view];
    else [super showFromRect:rect inView:view animated:animated];
}

- (void)layoutSubviews
{
    if (![self usesClassicSheet]) { [super layoutSubviews]; return; }
    if (!self.classicPanel) return;
    UIEdgeInsets safe = TKSafeAreaInsets(self.superview ?: self);
    CGFloat width = MIN(TKIsPad() ? 360 : 420, self.bounds.size.width - safe.left - safe.right - 16);
    CGFloat titleHeight = self.title.length ? 38 : 0;
    CGFloat contentHeight = 16 + titleHeight + self.choiceButtons.count * 52 + (self.cancelButtonIndex >= 0 ? 8 : 0);
    CGFloat height = MIN(contentHeight, self.bounds.size.height - safe.top - safe.bottom - 24);
    CGFloat y = TKIsPad() ? (self.bounds.size.height - height) / 2 : self.bounds.size.height - safe.bottom - height - 8;
    self.classicPanel.frame = CGRectMake((self.bounds.size.width - width) / 2, y, width, height);
    self.gradient.frame = self.classicPanel.bounds;
    self.choices.frame = self.classicPanel.bounds;
    self.choices.contentSize = CGSizeMake(width, contentHeight);
    self.heading.frame = CGRectMake(12, 8, width - 24, titleHeight);
    CGFloat rowY = 8 + titleHeight;
    for (UIButton *button in self.choiceButtons) {
        if (button.tag == self.cancelButtonIndex) rowY += 8;
        button.frame = CGRectMake(8, rowY, width - 16, 44);
        rowY += 52;
    }
}

- (void)chose:(UIButton *)button
{
    if (self.closing) return;
    NSInteger index = button.tag;
    if ([self.delegate respondsToSelector:@selector(actionSheet:clickedButtonAtIndex:)]) [self.delegate actionSheet:self clickedButtonAtIndex:index];
    [self dismissWithClickedButtonIndex:index animated:YES];
}
- (void)cancel
{
    if ([self.delegate respondsToSelector:@selector(actionSheetCancel:)]) [self.delegate actionSheetCancel:self];
    [self dismissWithClickedButtonIndex:self.cancelButtonIndex animated:YES];
}
- (void)dismissWithClickedButtonIndex:(NSInteger)index animated:(BOOL)animated
{
    if (![self usesClassicSheet]) { [super dismissWithClickedButtonIndex:index animated:animated]; return; }
    if (!self.classicVisible || self.closing) return;
    self.closing = YES;
    if ([self.delegate respondsToSelector:@selector(actionSheet:willDismissWithButtonIndex:)]) [self.delegate actionSheet:self willDismissWithButtonIndex:index];
    void (^finished)(BOOL) = ^(BOOL done) {
        self.classicVisible = NO;
        [self removeFromSuperview];
        if ([self.delegate respondsToSelector:@selector(actionSheet:didDismissWithButtonIndex:)]) [self.delegate actionSheet:self didDismissWithButtonIndex:index];
        UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, nil);
    };
    if (animated) [UIView animateWithDuration:0.16 animations:^{ self.alpha = 0; } completion:finished];
    else finished(YES);
}
@end
