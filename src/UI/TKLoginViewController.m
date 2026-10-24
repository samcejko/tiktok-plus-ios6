#import "TKAlertView.h"
#import "TKLoginViewController.h"
#import "TKSession.h"
#import "TKTheme.h"
#import "TKCommon.h"

@interface TKLoginViewController () <UIAlertViewDelegate>
@property (nonatomic, strong) UIImageView *backdrop;
@property (nonatomic, strong) UIView *grain;
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;

@property (nonatomic, strong) UIView *fileCard;
@property (nonatomic, strong) UILabel *fileTitleLabel;
@property (nonatomic, strong) UILabel *fileStatusLabel;
@property (nonatomic, strong) UIButton *importButton;
@property (nonatomic, strong) UIButton *checkButton;
@property (nonatomic, strong) UIButton *pasteButton;

@property (nonatomic, strong) UIView *guideCard;
@property (nonatomic, strong) UILabel *guideLabel;

@property (nonatomic, strong) UIView *warningCard;
@property (nonatomic, strong) UILabel *warningLabel;

@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@end

@implementation TKLoginViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    TKTheme *theme = [TKTheme shared];
    self.title = L(@"Sign in");
    self.view.backgroundColor = [theme backgroundColor];

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
    self.titleLabel.text = L(@"Sign in to TikTok");
    self.titleLabel.font = [UIFont boldSystemFontOfSize:TKIsPad() ? 28 : 22];
    self.titleLabel.textColor = [theme embossTextColor];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.backgroundColor = [UIColor clearColor];
    [theme embossLabel:self.titleLabel];
    [self.scroll addSubview:self.titleLabel];

    self.subtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.subtitleLabel.text = L(@"Import a signed-in TikTok browser session. TikTak+ verifies the account directly with TikTok. Some account features may be restricted by TikTok.");
    self.subtitleLabel.font = [UIFont systemFontOfSize:14];
    self.subtitleLabel.textColor = [theme secondaryTextColor];
    self.subtitleLabel.textAlignment = NSTextAlignmentCenter;
    self.subtitleLabel.numberOfLines = 0;
    self.subtitleLabel.backgroundColor = [UIColor clearColor];
    [theme embossLabel:self.subtitleLabel];
    [self.scroll addSubview:self.subtitleLabel];

    // File import card
    self.fileCard = [[UIView alloc] initWithFrame:CGRectZero];
    self.fileCard.backgroundColor = [theme cardColor];
    self.fileCard.layer.cornerRadius = 8.0;
    self.fileCard.layer.masksToBounds = YES;
    self.fileCard.layer.borderColor = [theme separatorColor].CGColor;
    self.fileCard.layer.borderWidth = 1.0;
    [self.scroll addSubview:self.fileCard];

    self.fileTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.fileTitleLabel.text = L(@"Session File (Method A)");
    self.fileTitleLabel.font = [UIFont boldSystemFontOfSize:16];
    self.fileTitleLabel.textColor = [theme primaryTextColor];
    self.fileTitleLabel.backgroundColor = [UIColor clearColor];
    [self.fileCard addSubview:self.fileTitleLabel];

    self.fileStatusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.fileStatusLabel.font = [UIFont systemFontOfSize:13];
    self.fileStatusLabel.numberOfLines = 0;
    self.fileStatusLabel.backgroundColor = [UIColor clearColor];
    [self.fileCard addSubview:self.fileStatusLabel];

    self.importButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.importButton setBackgroundImage:[theme accentButtonImageHighlighted:NO disabled:NO] forState:UIControlStateNormal];
    [self.importButton setBackgroundImage:[theme accentButtonImageHighlighted:YES disabled:NO] forState:UIControlStateHighlighted];
    [self.importButton setBackgroundImage:[theme accentButtonImageHighlighted:NO disabled:YES] forState:UIControlStateDisabled];
    [self.importButton setTitle:L(@"Import Session File") forState:UIControlStateNormal];
    [self.importButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [self.importButton setTitleColor:[UIColor colorWithWhite:1.0 alpha:0.4] forState:UIControlStateDisabled];
    self.importButton.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [self.importButton addTarget:self action:@selector(importTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.fileCard addSubview:self.importButton];

    self.checkButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.checkButton setBackgroundImage:[theme buttonImageHighlighted:NO] forState:UIControlStateNormal];
    [self.checkButton setBackgroundImage:[theme buttonImageHighlighted:YES] forState:UIControlStateHighlighted];
    [self.checkButton setTitle:L(@"Re-scan Documents") forState:UIControlStateNormal];
    [self.checkButton setTitleColor:[theme primaryTextColor] forState:UIControlStateNormal];
    self.checkButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [self.checkButton addTarget:self action:@selector(updateFileStatus) forControlEvents:UIControlEventTouchUpInside];
    [self.fileCard addSubview:self.checkButton];

    self.pasteButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.pasteButton setBackgroundImage:[theme buttonImageHighlighted:NO] forState:UIControlStateNormal];
    [self.pasteButton setBackgroundImage:[theme buttonImageHighlighted:YES] forState:UIControlStateHighlighted];
    [self.pasteButton setTitle:L(@"Paste Session JSON") forState:UIControlStateNormal];
    [self.pasteButton setTitleColor:[theme primaryTextColor] forState:UIControlStateNormal];
    self.pasteButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [self.pasteButton addTarget:self action:@selector(pasteTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.fileCard addSubview:self.pasteButton];

    // Instructions card
    self.guideCard = [[UIView alloc] initWithFrame:CGRectZero];
    self.guideCard.backgroundColor = [theme cardColor];
    self.guideCard.layer.cornerRadius = 8.0;
    self.guideCard.layer.masksToBounds = YES;
    self.guideCard.layer.borderColor = [theme separatorColor].CGColor;
    self.guideCard.layer.borderWidth = 1.0;
    [self.scroll addSubview:self.guideCard];

    self.guideLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.guideLabel.text = L(@"How to sign in:\n1. Log into tiktok.com in your PC or mobile browser.\n2. Export your cookies (e.g. using Cookie-Editor or browser tools) to a ttsession.json file.\n3. Put ttsession.json into TikTak's Documents folder via iTunes File Sharing or Filza/iFile.\n4. Tap 'Import Session File' above. TikTak+ verifies and stores it securely on this device, then deletes the imported file. No helper is used.");
    self.guideLabel.font = [UIFont systemFontOfSize:12];
    self.guideLabel.textColor = [theme secondaryTextColor];
    self.guideLabel.numberOfLines = 0;
    self.guideLabel.backgroundColor = [UIColor clearColor];
    [self.guideCard addSubview:self.guideLabel];

    // Warning card
    self.warningCard = [[UIView alloc] initWithFrame:CGRectZero];
    self.warningCard.backgroundColor = [UIColor colorWithRed:0.25 green:0.1 blue:0.1 alpha:0.6];
    self.warningCard.layer.cornerRadius = 8.0;
    self.warningCard.layer.masksToBounds = YES;
    self.warningCard.layer.borderColor = [UIColor colorWithRed:0.8 green:0.2 blue:0.2 alpha:0.5].CGColor;
    self.warningCard.layer.borderWidth = 1.0;
    [self.scroll addSubview:self.warningCard];

    self.warningLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.warningLabel.text = L(@"Notice: TikTak is an unofficial client. Always use a secondary or throwaway TikTok account to avoid any risk to your primary account.");
    self.warningLabel.font = [UIFont boldSystemFontOfSize:12];
    self.warningLabel.textColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.8 alpha:1.0];
    self.warningLabel.numberOfLines = 0;
    self.warningLabel.backgroundColor = [UIColor clearColor];
    [self.warningCard addSubview:self.warningLabel];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    self.spinner.hidesWhenStopped = YES;
    [self.view addSubview:self.spinner];

    [self updateFileStatus];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self updateFileStatus];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    CGFloat w = self.view.bounds.size.width;
    CGFloat contentW = TKIsPad() ? MIN(520, w - 40) : (w - 24);
    CGFloat left = (w - contentW) / 2.0;

    CGFloat y = 20;
    self.titleLabel.frame = CGRectMake(left, y, contentW, 36);
    y += 42;

    CGSize subSize = [self.subtitleLabel.text sizeWithFont:self.subtitleLabel.font
                                        constrainedToSize:CGSizeMake(contentW, 120)
                                            lineBreakMode:NSLineBreakByWordWrapping];
    self.subtitleLabel.frame = CGRectMake(left, y, contentW, subSize.height);
    y += subSize.height + 18;

    // File card
    CGFloat cardInnerW = contentW - 24;
    self.fileTitleLabel.frame = CGRectMake(12, 12, cardInnerW, 22);
    CGSize statSize = [self.fileStatusLabel.text sizeWithFont:self.fileStatusLabel.font
                                           constrainedToSize:CGSizeMake(cardInnerW, 100)
                                               lineBreakMode:NSLineBreakByWordWrapping];
    self.fileStatusLabel.frame = CGRectMake(12, 38, cardInnerW, statSize.height);
    CGFloat btnY = 38 + statSize.height + 14;
    self.importButton.frame = CGRectMake(12, btnY, cardInnerW, 40);
    self.checkButton.frame = CGRectMake(12, btnY + 48, (cardInnerW - 10) / 2.0, 36);
    self.pasteButton.frame = CGRectMake(12 + (cardInnerW - 10) / 2.0 + 10, btnY + 48, (cardInnerW - 10) / 2.0, 36);
    CGFloat fileCardH = btnY + 48 + 36 + 14;
    self.fileCard.frame = CGRectMake(left, y, contentW, fileCardH);
    y += fileCardH + 16;

    // Guide card
    CGSize guideSize = [self.guideLabel.text sizeWithFont:self.guideLabel.font
                                       constrainedToSize:CGSizeMake(cardInnerW, 300)
                                           lineBreakMode:NSLineBreakByWordWrapping];
    self.guideLabel.frame = CGRectMake(12, 12, cardInnerW, guideSize.height);
    CGFloat guideCardH = guideSize.height + 24;
    self.guideCard.frame = CGRectMake(left, y, contentW, guideCardH);
    y += guideCardH + 16;

    // Warning card
    CGSize warnSize = [self.warningLabel.text sizeWithFont:self.warningLabel.font
                                        constrainedToSize:CGSizeMake(cardInnerW, 200)
                                            lineBreakMode:NSLineBreakByWordWrapping];
    self.warningLabel.frame = CGRectMake(12, 12, cardInnerW, warnSize.height);
    CGFloat warnCardH = warnSize.height + 24;
    self.warningCard.frame = CGRectMake(left, y, contentW, warnCardH);
    y += warnCardH + 30;

    self.scroll.contentSize = CGSizeMake(w, y);
    self.spinner.center = CGPointMake(w / 2.0, self.view.bounds.size.height / 2.0);
}

- (void)updateFileStatus
{
    BOOL hasFile = [TKSession hasPendingCookieFile];
    if (hasFile) {
        self.fileStatusLabel.textColor = [UIColor colorWithRed:0.2 green:0.8 blue:0.3 alpha:1.0];
        self.fileStatusLabel.text = L(@"ttsession.json detected in Documents. Ready to import.");
        self.importButton.enabled = YES;
    } else {
        self.fileStatusLabel.textColor = [[TKTheme shared] secondaryTextColor];
        self.fileStatusLabel.text = L(@"No ttsession.json found in Documents yet. Put the file in Documents via iTunes or Filza, then tap Re-scan.");
        self.importButton.enabled = NO;
    }
    [self.view setNeedsLayout];
}

- (void)importTapped
{
    [self.spinner startAnimating];
    self.view.userInteractionEnabled = NO;

    [[TKSession sharedSession] importCookiesWithCompletion:^(BOOL success, NSString *errorMessage) {
        [self.spinner stopAnimating];
        self.view.userInteractionEnabled = YES;

        if (success) {
            NSString *handle = [TKSession sharedSession].handle;
            NSString *msg = [NSString stringWithFormat:L(@"Signed in as @%@"), handle ?: @""];
            UIAlertView *alert = [[TKAlertView alloc] initWithTitle:L(@"Sign-in successful")
                                                           message:msg
                                                          delegate:self
                                                 cancelButtonTitle:L(@"OK")
                                                 otherButtonTitles:nil];
            alert.tag = 100;
            [alert show];
        } else {
            UIAlertView *alert = [[TKAlertView alloc] initWithTitle:L(@"Sign-in failed")
                                                           message:errorMessage ?: L(@"Could not import session.")
                                                          delegate:nil
                                                 cancelButtonTitle:L(@"OK")
                                                 otherButtonTitles:nil];
            [alert show];
            [self updateFileStatus];
        }
    }];
}

- (void)pasteTapped
{
    UIAlertView *alert = [[TKAlertView alloc] initWithTitle:L(@"Paste Session")
                                                   message:L(@"Paste your cookie JSON or session string:")
                                                  delegate:self
                                         cancelButtonTitle:L(@"Cancel")
                                         otherButtonTitles:L(@"Import"), nil];
    alert.alertViewStyle = UIAlertViewStylePlainTextInput;
    UITextField *tf = [alert textFieldAtIndex:0];
    tf.placeholder = @"{\"sessionid\": \"...\"}";
    tf.secureTextEntry = YES;
    tf.autocorrectionType = UITextAutocorrectionTypeNo;
    tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
    alert.tag = 200;
    [alert show];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (alertView.tag == 100) {
        [self.navigationController popViewControllerAnimated:YES];
    } else if (alertView.tag == 200 && buttonIndex != alertView.cancelButtonIndex) {
        UITextField *tf = [alertView textFieldAtIndex:0];
        NSString *text = [tf.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!text.length) return;

        [self.spinner startAnimating];
        self.view.userInteractionEnabled = NO;

        [[TKSession sharedSession] importCookiesString:text completion:^(BOOL success, NSString *errorMessage) {
            [self.spinner stopAnimating];
            self.view.userInteractionEnabled = YES;

            if (success) {
                NSString *handle = [TKSession sharedSession].handle;
                NSString *msg = [NSString stringWithFormat:L(@"Signed in as @%@"), handle ?: @""];
                UIAlertView *alert = [[TKAlertView alloc] initWithTitle:L(@"Sign-in successful")
                                                               message:msg
                                                              delegate:self
                                                     cancelButtonTitle:L(@"OK")
                                                     otherButtonTitles:nil];
                alert.tag = 100;
                [alert show];
            } else {
                UIAlertView *alert = [[TKAlertView alloc] initWithTitle:L(@"Sign-in failed")
                                                               message:errorMessage ?: L(@"Could not import session.")
                                                              delegate:nil
                                                     cancelButtonTitle:L(@"OK")
                                                     otherButtonTitles:nil];
                [alert show];
            }
        }];
    }
}

@end
