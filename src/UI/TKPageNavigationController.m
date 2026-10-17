#import "TKPageNavigationController.h"
#import <QuartzCore/QuartzCore.h>
#import "TKFeedViewController.h"
#import "TKLinkRouter.h"
#import "TKTheme.h"
#import "TKModern.h"
#import "TKCommon.h"

// Stands under the first page so that the bar draws a real (arrow-shaped) back button there; it is never shown
@interface TKStackBottom : UIViewController
@end

@implementation TKStackBottom
- (void)viewDidLoad { [super viewDidLoad]; self.view.backgroundColor = [UIColor blackColor]; }
@end

@interface TKPageNavigationController () <UINavigationControllerDelegate, UINavigationBarDelegate>
@property (nonatomic) BOOL closing;
@end

@implementation TKPageNavigationController

+ (TKPageNavigationController *)visibleStack
{
    UIViewController *top = [TKLinkRouter topController];
    return [top isKindOfClass:[TKPageNavigationController class]] ? (TKPageNavigationController *)top : nil;
}

// The slide of a push, for a modal presentation (iOS 6 has none): the window's next picture comes in from the side
+ (void)slideWindow:(UIWindow *)window fromRight:(BOOL)fromRight
{
    if (!window) return;
    CATransition *t = [CATransition animation];
    t.type = kCATransitionPush;
    t.subtype = fromRight ? kCATransitionFromRight : kCATransitionFromLeft;
    t.duration = 0.3;
    t.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [window.layer addAnimation:t forKey:@"TKPageSlide"];
}

+ (void)showPage:(UIViewController *)page
{
    if (!page) return;
    TKPageNavigationController *stack = [self visibleStack];
    if (stack) { [stack pushViewController:page animated:YES]; return; }
    UIViewController *top = [TKLinkRouter topController];
    TKStackBottom *bottom = [[TKStackBottom alloc] init];
    bottom.navigationItem.backBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:L(@"Back") style:UIBarButtonItemStyleBordered target:nil action:NULL];
    TKPageNavigationController *nav = [[TKPageNavigationController alloc] initWithRootViewController:bottom];
    [nav pushViewController:page animated:NO];
    [self slideWindow:top.view.window fromRight:YES];
    [top presentViewController:nav animated:NO completion:nil];
}

- (instancetype)initWithRootViewController:(UIViewController *)root
{
    if ((self = [super initWithRootViewController:root])) {
        self.delegate = self;
        self.wantsFullScreenLayout = YES;
        self.modalPresentationStyle = UIModalPresentationFullScreen;
        [[TKTheme shared] applyToNavigationBar:self.navigationBar];
        // (Back has logic of its own below; the swipe of iOS 7+ would pop past the first page onto the black bottom)
        TKModernDisableSwipeBack(self);
    }
    return self;
}

- (void)closeAnimated:(BOOL)animated
{
    if (self.closing) return;
    self.closing = YES;
    UIViewController *presenter = self.presentingViewController;
    if (animated) [TKPageNavigationController slideWindow:self.view.window fromRight:NO];
    [presenter dismissViewControllerAnimated:NO completion:nil];
}

- (void)goBack
{
    if (self.viewControllers.count <= 2) [self closeAnimated:YES];
    else [self popViewControllerAnimated:YES];
}

// The bar's back button. (A pop made in code has already taken the page off when the bar asks: then it just goes.)
- (BOOL)navigationBar:(UINavigationBar *)bar shouldPopItem:(UINavigationItem *)item
{
    if (self.viewControllers.count < bar.items.count) return YES;
    [self goBack];
    return NO;
}

// A video list fills the screen without the bar
- (void)navigationController:(UINavigationController *)nav willShowViewController:(UIViewController *)vc animated:(BOOL)animated
{
    BOOL bare = [vc isKindOfClass:[TKFeedViewController class]] || [vc isKindOfClass:[TKStackBottom class]];
    if (self.navigationBarHidden != bare) [self setNavigationBarHidden:bare animated:animated];
}

- (BOOL)shouldAutorotate { return self.topViewController ? [self.topViewController shouldAutorotate] : YES; }

- (NSUInteger)supportedInterfaceOrientations
{
    return self.topViewController ? [self.topViewController supportedInterfaceOrientations] : UIInterfaceOrientationMaskAll;
}

@end
