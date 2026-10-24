#import "TKSettingsViewController.h"
#import "TKLanguagesViewController.h"
#import "TKTasteViewController.h"
#import "TKTopicsViewController.h"
#import "TKExternalOpen.h"
#import "TKTikTok.h"
#import "TKSettings.h"
#import "TKSession.h"
#import "TKLoginViewController.h"
#import "TKNotificationsViewController.h"
#import "TKLikedViewController.h"
#import "TKProfileViewController.h"
#import "TKImageLoader.h"
#import "TKTheme.h"
#import "TKUtils.h"
#import "TKCommon.h"
#import "TKViewingSettingsViewController.h"

enum { SecServer, SecAccount, SecFeed, SecPlayback, SecAppearance, SecData, SecAbout, SecCount };

@interface TKSettingsViewController () <UIAlertViewDelegate>
@end

@implementation TKSettingsViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = L(@"Settings");
    [[TKTheme shared] applyToTableView:self.tableView];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(done)];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionChanged) name:TKSessionDidChangeNotification object:nil];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
- (void)sessionChanged { [self.tableView reloadData]; }

- (void)done { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self.tableView reloadData]; }   // (back from the languages)
- (BOOL)shouldAutorotate { return YES; }
- (NSUInteger)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAll; }

- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return SecCount; }

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s
{
    switch (s) {
        case SecServer: return 2;
        case SecAccount: return [TKSession sharedSession].signedIn ? 3 : 1;
        case SecFeed: return 3;
        case SecPlayback: return 4;
        case SecAppearance: return 1;
        case SecData: return 3;
        case SecAbout: return 2;
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s
{
    switch (s) {
        case SecServer: return L(@"Connection");
        case SecAccount: return L(@"Account");
        case SecFeed: return L(@"Explore");
        case SecPlayback: return L(@"Playback");
        case SecAppearance: return L(@"Appearance");
        case SecData: return L(@"Data");
        case SecAbout: return L(@"About");
    }
    return nil;
}

- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s
{
    if (s == SecServer) return L(@"TikTak+ connects directly to TikTok. No helper server is required. Session cookies stay on this device and are sent only to TikTok.");
    if (s == SecAccount) {
        if ([TKSession sharedSession].signedIn) {
            return L(@"Account features depend on what TikTok makes available. Sending likes, follows and comments is not supported in this version.");
        } else {
            return L(@"Drop ttsession.json or ttcookies.json into TikTak's Documents folder via iTunes or Filza to sign in.");
        }
    }
    if (s == SecAbout) return L(@"TikTak+ is an unofficial viewer and client for TikTok. Supports optional sign-in via session file import. Not affiliated with TikTok or ByteDance.");
    if (s == SecData) return L(@"Watch history is stored locally. You can search, delete individual posts or clear it from the menu.");
    return nil;
}

- (UISwitch *)switchOn:(BOOL)on tag:(NSInteger)tag
{
    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectZero];
    sw.on = on;
    sw.tag = tag;
    [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    return sw;
}

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip
{
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    [[TKTheme shared] styleCell:cell];
    NSInteger s = ip.section, r = ip.row;
    if (s == SecServer) {
        if (r == 0) { cell.textLabel.text = L(@"Direct connection to TikTok"); cell.selectionStyle = UITableViewCellSelectionStyleNone; }
        else { cell.textLabel.text = L(@"Test connection"); cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; }
    } else if (s == SecAccount) {
        if ([TKSession sharedSession].signedIn) {
            if (r == 0) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
                [[TKTheme shared] styleCell:cell];
                NSString *nick = [TKSession sharedSession].displayName.length ? [TKSession sharedSession].displayName : L(@"Me");
                NSString *uid = [TKSession sharedSession].handle.length ? [@"@" stringByAppendingString:[TKSession sharedSession].handle] : @"";
                cell.textLabel.text = nick;
                cell.detailTextLabel.text = uid;
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                cell.imageView.image = [self placeholderAvatarOfSize:CGSizeMake(34, 34)];
                NSString *thumb = [TKSession sharedSession].avatarURL;
                if (thumb.length) {
                    [[TKImageLoader shared] loadImage:thumb maxPixels:100 completion:^(UIImage *img) {
                        if (img) {
                            cell.imageView.image = img;
                            [cell setNeedsLayout];
                        }
                    }];
                }
            } else if (r == 1) {
                cell.textLabel.text = L(@"Liked videos"); cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            } else {
                cell.textLabel.text = L(@"Sign out"); cell.textLabel.textColor = [UIColor colorWithRed:0.8 green:0.2 blue:0.2 alpha:1];
            }
        } else {
            cell.textLabel.text = L(@"Sign in");
            cell.detailTextLabel.text = [TKSession hasPendingCookieFile] ? L(@"Session file ready to import") : L(@"Import ttsession.json");
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
    } else if (s == SecFeed) {
        if (r == 0) {
            cell.textLabel.text = L(@"Video languages");
            NSUInteger hidden = [TKSettings hiddenLanguages].count;
            cell.detailTextLabel.text = hidden ? [NSString stringWithFormat:L(@"%lu hidden"), (unsigned long)hidden] : L(@"All");
        } else if (r == 1) {
            cell.textLabel.text = L(@"Pick topics");
        } else {
            cell.textLabel.text = L(@"What it learned");
        }
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (s == SecPlayback) {
        if (r == 0) { cell.textLabel.text = L(@"Start muted"); cell.accessoryView = [self switchOn:[TKSettings startMuted] tag:20]; }
        else if (r == 1) { cell.textLabel.text = L(@"Auto-advance"); cell.accessoryView = [self switchOn:[TKSettings autoAdvance] tag:21]; }
        else if (r==2) { cell.textLabel.text = L(@"Captions"); cell.accessoryView = [self switchOn:[TKSettings showCaptions] tag:22]; }
        else { cell.textLabel.text=L(@"Content and playback"); cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator; }
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (s == SecAppearance) {
        cell.textLabel.text = L(@"Dark theme"); cell.accessoryView = [self switchOn:[TKTheme shared].isDark tag:30]; cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (s == SecData) {
        cell.textLabel.text = r == 0 ? L(@"Clear image cache") : (r == 1 ? L(@"Clear saved videos") : L(@"Record watch history"));
        if (r == 1) cell.textLabel.textColor = [UIColor colorWithRed:0.8 green:0.2 blue:0.2 alpha:1];
        if (r == 2) { cell.accessoryView = [self switchOn:[TKSettings recordWatchHistory] tag:23]; cell.selectionStyle = UITableViewCellSelectionStyleNone; }
    } else if (s == SecAbout && r == 0) {
        cell.textLabel.text = L(@"Version"); cell.detailTextLabel.text = [TKUtils appVersion]; cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (s == SecAbout) {
        cell.textLabel.text = L(@"Support the development"); cell.detailTextLabel.text = @"ko-fi.com/samcejko"; cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}

- (void)switchChanged:(UISwitch *)sw
{
    switch (sw.tag) {
        case 10: [TKSettings setStreamThroughServer:sw.on]; break;
        case 20: [TKSettings setStartMuted:sw.on]; break;
        case 21: [TKSettings setAutoAdvance:sw.on]; break;
        case 22: [TKSettings setShowCaptions:sw.on]; break;
        case 23: [TKSettings setRecordWatchHistory:sw.on]; break;
        case 30: [[TKTheme shared] setDark:sw.on]; break;
        case 40: [TKSettings setVerifyTLS:sw.on]; [TKSettings save]; break;
        case 50: {
            if (sw.on) {
                UIAlertView *a = [[UIAlertView alloc] initWithTitle:L(@"Enable account actions?")
                                                            message:L(@"Liking, following and commenting run directly under your account on TikTok's servers. Aggressive use may trigger rate limits or account flags. We recommend using a throwaway account.")
                                                           delegate:self
                                                  cancelButtonTitle:L(@"Cancel")
                                                  otherButtonTitles:L(@"Enable"), nil];
                a.tag = 50;
                [a show];
            } else {
                [TKSettings setAllowAccountWrites:NO];
            }
            break;
        }
    }
}

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip
{
    [t deselectRowAtIndexPath:ip animated:YES];
    NSInteger s = ip.section, r = ip.row;
    if (s == SecServer && r == 1) {
        [self testConnection];
    } else if (s == SecAccount) {
        if ([TKSession sharedSession].signedIn) {
            if (r == 0) {
                if ([TKSession sharedSession].handle.length) {
                    [self.navigationController pushViewController:[[TKProfileViewController alloc] initWithHandle:[TKSession sharedSession].handle] animated:YES];
                }
            } else if (r == 1) {
                [self.navigationController pushViewController:[[TKLikedViewController alloc] init] animated:YES];
            } else if (r == 2) {
                UIAlertView *a = [[UIAlertView alloc] initWithTitle:L(@"Sign out") message:L(@"Are you sure you want to sign out?") delegate:self cancelButtonTitle:L(@"Cancel") otherButtonTitles:L(@"Sign out"), nil];
                a.tag = 51;
                [a show];
            }
        } else {
            [self.navigationController pushViewController:[[TKLoginViewController alloc] init] animated:YES];
        }
    } else if (s == SecFeed) {
        UIViewController *next = r == 0 ? [[TKLanguagesViewController alloc] init]
                               : r == 1 ? (UIViewController *)[[TKTopicsViewController alloc] init] : [[TKTasteViewController alloc] init];
        [self.navigationController pushViewController:next animated:YES];
    } else if (s == SecPlayback && r == 3) {
        [self.navigationController pushViewController:[[TKViewingSettingsViewController alloc] init] animated:YES];
    } else if (s == SecData && r == 0) {
        [[TKImageLoader shared] clearMemory];
        [[TKImageLoader shared] clearDiskWithCompletion:^{ [TKUtils alertWithTitle:nil message:L(@"Image cache cleared.")]; }];
    } else if (s == SecData && r == 1) {
        UIAlertView *a = [[UIAlertView alloc] initWithTitle:L(@"Clear saved videos") message:L(@"Remove every saved video?") delegate:self cancelButtonTitle:L(@"Cancel") otherButtonTitles:L(@"Clear"), nil];
        a.tag = 3;
        [a show];
    } else if (s == SecAbout && r == 1) {
        // (iOS 6 asks: Safari or Surfari; newer iOS opens Safari at once)
        [TKExternalOpen presentOpenInForURL:[NSURL URLWithString:@"https://ko-fi.com/samcejko"] from:self anchor:[t cellForRowAtIndexPath:ip]];
    }
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (alertView.tag == 50) {
        if (buttonIndex == alertView.cancelButtonIndex) {
            [TKSettings setAllowAccountWrites:NO];
        } else {
            [TKSettings setAllowAccountWrites:YES];
        }
        [self.tableView reloadData];
        return;
    }
    if (alertView.tag == 51) {
        if (buttonIndex != alertView.cancelButtonIndex) {
            [[TKSession sharedSession] signOut];
            [self.tableView reloadData];
        }
        return;
    }
    if (buttonIndex == alertView.cancelButtonIndex) return;
    if (alertView.tag == 1) { [TKSettings setServerBaseURL:[alertView textFieldAtIndex:0].text]; }
    else if (alertView.tag == 2) { [TKSettings setServerKey:[alertView textFieldAtIndex:0].text]; }
    else if (alertView.tag == 3) { for (NSDictionary *d in [TKSettings savedVideos]) [TKSettings unsaveVideo:TKStr(d[@"id"])]; }
    [self.tableView reloadData];
}

- (UIImage *)placeholderAvatarOfSize:(CGSize)size
{
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetFillColorWithColor(ctx, [UIColor colorWithWhite:0.35 alpha:1].CGColor);
    CGContextFillEllipseInRect(ctx, CGRectMake(0, 0, size.width, size.height));
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

- (void)testConnection
{
    UIActivityIndicatorView *sp = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    [sp startAnimating];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:sp];
    [TKTikTok checkHealth:^(BOOL ok, NSString *info, NSError *error) {
        self.navigationItem.rightBarButtonItem = nil;
        if (ok) [TKUtils alertWithTitle:L(@"Connected") message:info ?: L(@"Direct connection to TikTok")];
        else [TKUtils alertWithTitle:L(@"Not connected") message:error.localizedDescription ?: L(@"The server did not answer.")];
    }];
}

@end
