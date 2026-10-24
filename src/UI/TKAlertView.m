#import "TKAlertView.h"
#import "TKTheme.h"
#import "TKModern.h"
#import <QuartzCore/QuartzCore.h>

@interface TKAlertView ()
@property (nonatomic) BOOL classicVisible;
@property (nonatomic) BOOL closing;
@property (nonatomic) UIAlertViewStyle classicStyle;
@property (nonatomic, strong) NSMutableArray *fields;
@property (nonatomic, strong) NSMutableArray *buttons;
@property (nonatomic, strong) UIView *dialog;
@property (nonatomic, strong) CAGradientLayer *gradient;
@property (nonatomic, strong) UILabel *heading;
@property (nonatomic, strong) UILabel *bodyLabel;
@property (nonatomic, strong) UIScrollView *body;
@property (nonatomic) CGRect keyboard;
@end
@implementation TKAlertView
- (BOOL)isVisible { return TKModernIOS() ? self.classicVisible : [super isVisible]; }
- (UIAlertViewStyle)alertViewStyle { return TKModernIOS() ? self.classicStyle : [super alertViewStyle]; }
- (void)setAlertViewStyle:(UIAlertViewStyle)style
{
    if(!TKModernIOS()) { [super setAlertViewStyle:style]; return; }
    self.classicStyle=style; self.fields=nil;
}
- (UITextField *)textFieldAtIndex:(NSInteger)index
{
    if(!TKModernIOS())return [super textFieldAtIndex:index];
    if(!self.fields) {
        self.fields=[NSMutableArray array]; NSUInteger count=self.classicStyle==UIAlertViewStyleDefault ? 0 : (self.classicStyle==UIAlertViewStyleLoginAndPasswordInput ? 2 : 1);
        for(NSUInteger i=0;i<count;i++) {
            UITextField *field=[[UITextField alloc] initWithFrame:CGRectZero]; field.borderStyle=UITextBorderStyleRoundedRect;
            field.backgroundColor=[UIColor whiteColor]; field.textColor=[UIColor blackColor]; field.font=[UIFont systemFontOfSize:15]; field.contentVerticalAlignment=UIControlContentVerticalAlignmentCenter;
            field.autocorrectionType=UITextAutocorrectionTypeNo; field.autocapitalizationType=UITextAutocapitalizationTypeNone;
            field.secureTextEntry=self.classicStyle==UIAlertViewStyleSecureTextInput || (self.classicStyle==UIAlertViewStyleLoginAndPasswordInput && i==1);
            [self.fields addObject:field];
        }
    }
    return index>=0 && index<(NSInteger)self.fields.count ? self.fields[(NSUInteger)index] : nil;
}
- (void)show
{
    if(!TKModernIOS()) { [super show]; return; }
    if(self.classicVisible)return;
    UIWindow *host=nil; for(UIWindow *w in [UIApplication sharedApplication].windows) if(!w.hidden && w.windowLevel==UIWindowLevelNormal)host=w;
    if(!host)host=[UIApplication sharedApplication].keyWindow; if(!host)return;
    for(UIView *sub in [self.subviews copy])[sub removeFromSuperview];
    self.frame=host.bounds; self.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight; self.backgroundColor=[UIColor colorWithWhite:0 alpha:0.5]; self.classicVisible=YES; self.closing=NO; self.accessibilityViewIsModal=YES;
    self.dialog=[[UIView alloc] initWithFrame:CGRectZero]; self.dialog.backgroundColor=[UIColor colorWithWhite:0.16 alpha:1]; self.dialog.layer.cornerRadius=10; self.dialog.layer.borderWidth=1; self.dialog.layer.borderColor=[UIColor colorWithWhite:0.75 alpha:1].CGColor; self.dialog.layer.shadowOpacity=0.7; self.dialog.layer.shadowRadius=8; [self addSubview:self.dialog];
    self.gradient=[CAGradientLayer layer]; self.gradient.colors=@[(id)[UIColor colorWithWhite:0.4 alpha:1].CGColor,(id)[UIColor colorWithWhite:0.14 alpha:1].CGColor]; self.gradient.cornerRadius=10; [self.dialog.layer addSublayer:self.gradient];
    self.heading=[[UILabel alloc] initWithFrame:CGRectZero]; self.heading.text=self.title; self.heading.font=[UIFont boldSystemFontOfSize:18]; self.heading.textColor=[UIColor whiteColor]; self.heading.textAlignment=NSTextAlignmentCenter; self.heading.numberOfLines=0; self.heading.backgroundColor=[UIColor clearColor]; [self.dialog addSubview:self.heading];
    self.body=[[UIScrollView alloc] initWithFrame:CGRectZero]; self.body.bounces=NO; [self.dialog addSubview:self.body];
    self.bodyLabel=[[UILabel alloc] initWithFrame:CGRectZero]; self.bodyLabel.text=self.message; self.bodyLabel.textColor=[UIColor whiteColor]; self.bodyLabel.font=[UIFont systemFontOfSize:14]; self.bodyLabel.textAlignment=NSTextAlignmentCenter; self.bodyLabel.numberOfLines=0; self.bodyLabel.backgroundColor=[UIColor clearColor]; [self.body addSubview:self.bodyLabel];
    [self textFieldAtIndex:0]; for(UITextField *field in self.fields)[self.body addSubview:field];
    self.buttons=[NSMutableArray array]; TKTheme *theme=[TKTheme shared];
    for(NSInteger i=0;i<self.numberOfButtons;i++) {
        UIButton *b=[UIButton buttonWithType:UIButtonTypeCustom]; b.tag=i; [b setTitle:[self buttonTitleAtIndex:i] forState:UIControlStateNormal]; b.titleLabel.font=[UIFont boldSystemFontOfSize:16]; b.titleLabel.adjustsFontSizeToFitWidth=YES; b.contentEdgeInsets=UIEdgeInsetsMake(0,6,0,6);
        [b setTitleColor:[theme primaryTextColor] forState:UIControlStateNormal]; [b setBackgroundImage:[theme buttonImageHighlighted:NO] forState:UIControlStateNormal]; [b setBackgroundImage:[theme buttonImageHighlighted:YES] forState:UIControlStateHighlighted]; [b addTarget:self action:@selector(chose:) forControlEvents:UIControlEventTouchUpInside]; [self.buttons addObject:b]; [self.dialog addSubview:b];
    }
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillChangeFrameNotification object:nil];
    [host addSubview:self]; [self setNeedsLayout]; [self layoutIfNeeded];
    self.alpha=0; [UIView animateWithDuration:0.18 animations:^{ self.alpha=1; }];
    UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification,self.heading);
    if(self.fields.count)[self.fields[0] becomeFirstResponder];
}
- (void)keyboardChanged:(NSNotification *)note
{
    self.keyboard=[note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue]; [self setNeedsLayout]; [self layoutIfNeeded];
}
- (void)layoutSubviews
{
    if(!TKModernIOS()) { [super layoutSubviews]; return; }
    if(!self.dialog)return;
    UIEdgeInsets safe=TKSafeAreaInsets(self.superview ?: self); CGFloat width=MIN(340,self.bounds.size.width-safe.left-safe.right-32), inner=width-28;
    CGFloat titleH=self.title.length ? ceilf([self.title sizeWithFont:self.heading.font constrainedToSize:CGSizeMake(inner,120) lineBreakMode:NSLineBreakByWordWrapping].height) : 0;
    CGFloat textH=self.message.length ? ceilf([self.message sizeWithFont:self.bodyLabel.font constrainedToSize:CGSizeMake(inner,CGFLOAT_MAX) lineBreakMode:NSLineBreakByWordWrapping].height) : 0;
    CGFloat bodyH=textH+(textH && self.fields.count ? 12 : 0)+self.fields.count*42;
    CGFloat buttonH=self.buttons.count<=2 ? 44 : self.buttons.count*48;
    CGRect keyboard=[self convertRect:self.keyboard fromView:nil]; CGFloat overlap=self.keyboard.size.height>0 ? MAX(0,self.bounds.size.height-keyboard.origin.y) : 0;
    CGFloat available=MAX(160,self.bounds.size.height-safe.top-MAX(safe.bottom,overlap)-24);
    CGFloat height=MIN(available,16+titleH+10+bodyH+14+buttonH+12); CGFloat visibleBody=MAX(20,height-titleH-buttonH-52);
    self.dialog.frame=CGRectMake((self.bounds.size.width-width)/2,safe.top+12+MAX(0,(available-height)/2),width,height); self.gradient.frame=self.dialog.bounds;
    self.heading.frame=CGRectMake(14,16,inner,titleH); self.body.frame=CGRectMake(14,26+titleH,inner,visibleBody); self.body.contentSize=CGSizeMake(inner,bodyH); self.bodyLabel.frame=CGRectMake(0,0,inner,textH);
    CGFloat y=textH+(textH && self.fields.count ? 12 : 0); for(UITextField *field in self.fields) { field.frame=CGRectMake(0,y,inner,34); y+=42; }
    for(UIButton *b in self.buttons) {
        if(self.buttons.count<=2) { CGFloat bw=(width-24-(self.buttons.count-1)*8)/MAX((NSUInteger)1,self.buttons.count); b.frame=CGRectMake(12+b.tag*(bw+8),height-56,bw,44); }
        else b.frame=CGRectMake(12,height-12-buttonH+b.tag*48,width-24,40);
    }
}
- (void)chose:(UIButton *)button
{
    if(self.closing)return;
    if([self.delegate respondsToSelector:@selector(alertView:clickedButtonAtIndex:)])[self.delegate alertView:self clickedButtonAtIndex:button.tag];
    [self dismissWithClickedButtonIndex:button.tag animated:YES];
}
- (void)dismissWithClickedButtonIndex:(NSInteger)index animated:(BOOL)animated
{
    if(!TKModernIOS()) { [super dismissWithClickedButtonIndex:index animated:animated]; return; }
    if(!self.classicVisible || self.closing)return;
    self.closing=YES; [self endEditing:YES]; [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillChangeFrameNotification object:nil];
    if([self.delegate respondsToSelector:@selector(alertView:willDismissWithButtonIndex:)])[self.delegate alertView:self willDismissWithButtonIndex:index];
    void(^finished)(BOOL)=^(BOOL done){ self.classicVisible=NO; [self removeFromSuperview]; if([self.delegate respondsToSelector:@selector(alertView:didDismissWithButtonIndex:)])[self.delegate alertView:self didDismissWithButtonIndex:index]; };
    if(animated)[UIView animateWithDuration:0.16 animations:^{ self.alpha=0; } completion:finished]; else finished(YES);
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
@end
