#import "TKAlertView.h"
#import "TKViewingSettingsViewController.h"
#import "TKFavoritesViewController.h"
#import "TKSettings.h"
#import "TKTheme.h"
#import "TKActionSheet.h"
#import "TKCommon.h"

@interface TKViewingSettingsViewController () <UIAlertViewDelegate>
@end
@implementation TKViewingSettingsViewController
- (instancetype)init { return [super initWithStyle:UITableViewStyleGrouped]; }
- (void)viewDidLoad { [super viewDidLoad]; self.title=L(@"Content and playback"); [[TKTheme shared] applyToTableView:self.tableView]; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self.tableView reloadData]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return 2; }
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return s==0 ? 2 : 4; }
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s { return s==0 ? L(@"Playback") : L(@"Feed filters"); }
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s { return s==1 ? L(@"Filters affect Explore and account feeds on this device. Profiles, saved posts and direct links remain accessible.") : L(@"The default speed applies to new videos when the device supports it. Clean view hides captions and buttons; the menu remains accessible."); }
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip
{
    UITableViewCell *c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil]; [[TKTheme shared] styleCell:c];
    if(ip.section==0 && ip.row==0) { c.textLabel.text=L(@"Default playback speed"); c.detailTextLabel.text=[NSString stringWithFormat:@"%g×",[TKSettings defaultPlaybackSpeed]]; c.accessoryType=UITableViewCellAccessoryDisclosureIndicator; }
    else if(ip.section==1 && ip.row==0) { c.textLabel.text=L(@"Hidden creators"); c.detailTextLabel.text=[NSString stringWithFormat:@"%lu",(unsigned long)[TKSettings blockedCreators].count]; c.accessoryType=UITableViewCellAccessoryDisclosureIndicator; }
    else if(ip.section==1 && ip.row==1) { c.textLabel.text=L(@"Hidden words"); c.detailTextLabel.text=[NSString stringWithFormat:@"%lu",(unsigned long)[TKSettings hiddenKeywords].count]; c.accessoryType=UITableViewCellAccessoryDisclosureIndicator; }
    else if(ip.section==1 && ip.row==3) { c.textLabel.text=L(@"Maximum video length"); c.detailTextLabel.text=[TKSettings maxVideoDuration] ? [NSString stringWithFormat:L(@"%ld min"),(long)[TKSettings maxVideoDuration]/60] : L(@"Any length"); c.accessoryType=UITableViewCellAccessoryDisclosureIndicator; }
    else {
        BOOL clean=ip.section==0; c.textLabel.text=clean ? L(@"Clean view") : L(@"Hide photo posts");
        UISwitch *sw=[[UISwitch alloc] initWithFrame:CGRectZero]; sw.tag=clean ? 1 : 2; sw.on=clean ? [TKSettings cleanVideo] : [TKSettings hidePhotoPosts]; [sw addTarget:self action:@selector(changed:) forControlEvents:UIControlEventValueChanged]; c.accessoryView=sw; c.selectionStyle=UITableViewCellSelectionStyleNone;
    }
    return c;
}
- (void)changed:(UISwitch *)sw { if(sw.tag==1)[TKSettings setCleanVideo:sw.on]; else [TKSettings setHidePhotoPosts:sw.on]; }
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip
{
    [t deselectRowAtIndexPath:ip animated:YES];
    if(ip.section==0 && ip.row==0) {
        [TKActionSheet options:@[@"0.5×",@"1×",@"1.5×",@"2×"] title:L(@"Default playback speed") inView:self.view selection:^(NSInteger i){ [TKSettings setDefaultPlaybackSpeed:[@[@0.5,@1,@1.5,@2][(NSUInteger)i] floatValue]]; [self.tableView reloadData]; }];
    } else if(ip.section==1 && ip.row==0) [self.navigationController pushViewController:[[TKFavoritesViewController alloc] initWithKind:@"blocked"] animated:YES];
    else if(ip.section==1 && ip.row==1) {
        UIAlertView *a=[[TKAlertView alloc] initWithTitle:L(@"Hidden words") message:L(@"Separate words or phrases with commas. Matching captions, authors, tags and sounds are hidden from feeds.") delegate:self cancelButtonTitle:L(@"Cancel") otherButtonTitles:L(@"Save"),nil]; a.alertViewStyle=UIAlertViewStylePlainTextInput; [a textFieldAtIndex:0].text=[[TKSettings hiddenKeywords] componentsJoinedByString:@", "]; [a show];
    } else if(ip.section==1 && ip.row==3) {
        [TKActionSheet options:@[L(@"Any length"),L(@"1 min"),L(@"3 min"),L(@"5 min"),L(@"10 min")] title:L(@"Maximum video length") inView:self.view selection:^(NSInteger i){ [TKSettings setMaxVideoDuration:[@[@0,@60,@180,@300,@600][(NSUInteger)i] integerValue]]; [self.tableView reloadData]; }];
    }
}
- (void)alertView:(UIAlertView *)a clickedButtonAtIndex:(NSInteger)i { if(i!=a.cancelButtonIndex) { [TKSettings setHiddenKeywords:[a textFieldAtIndex:0].text]; [self.tableView reloadData]; } }
- (BOOL)shouldAutorotate { return YES; }
- (NSUInteger)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAll; }
@end
