#import "TKTasteViewController.h"
#import "TKLanguagesViewController.h"
#import "TKTaste.h"
#import "TKTheme.h"
#import "TKUtils.h"
#import "TKCommon.h"

enum { SecTopics, SecLikes, SecDislikes, SecActions, SecCount };

@interface TKTasteViewController () <UIAlertViewDelegate>
@property (nonatomic, strong) NSArray *topics;     // NSDictionary id, rate, seen
@property (nonatomic, strong) NSArray *likes;      // @[ key, weight ]
@property (nonatomic, strong) NSArray *dislikes;
@end

@implementation TKTasteViewController

- (instancetype)init { return [super initWithStyle:UITableViewStyleGrouped]; }

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = L(@"What it learned");
    [[TKTheme shared] applyToTableView:self.tableView];
    if (self.navigationController.viewControllers.firstObject == self)
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(done)];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self reload];
}

- (void)done { [self dismissViewControllerAnimated:YES completion:nil]; }
- (BOOL)shouldAutorotate { return YES; }
- (NSUInteger)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAll; }

// The likes and dislikes worth showing: hashtags, creators, languages and lengths (topics have their own section;
// sounds are only numbers)
- (void)reload
{
    TKTaste *taste = [TKTaste shared];
    self.topics = [taste topicRecords];
    NSMutableArray *all = [NSMutableArray array];
    for (NSString *prefix in @[ @"tag:", @"au:", @"lang:", @"len:" ]) [all addObjectsFromArray:[taste featureWeightsWithPrefix:prefix]];
    [all sortUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) { return [@(fabs([b[1] doubleValue])) compare:@(fabs([a[1] doubleValue]))]; }];
    NSMutableArray *likes = [NSMutableArray array], *dislikes = [NSMutableArray array];
    for (NSArray *e in all) {
        if ([e[1] doubleValue] > 0) { if (likes.count < 30) [likes addObject:e]; }
        else if (dislikes.count < 20) [dislikes addObject:e];
    }
    self.likes = likes;
    self.dislikes = dislikes;
    [self.tableView reloadData];
}

- (NSString *)nameOfFeature:(NSString *)key
{
    NSRange colon = [key rangeOfString:@":"];
    NSString *kind = colon.location == NSNotFound ? key : [key substringToIndex:colon.location];
    NSString *value = colon.location == NSNotFound ? @"" : [key substringFromIndex:colon.location + 1];
    if ([kind isEqualToString:@"tag"]) return [@"#" stringByAppendingString:[TKUtils displayText:value]];
    if ([kind isEqualToString:@"au"]) return [@"@" stringByAppendingString:value];
    if ([kind isEqualToString:@"lang"]) return [TKLanguagesViewController nameOfLanguage:value];
    if ([kind isEqualToString:@"len"]) {
        if ([value isEqualToString:@"short"]) return L(@"Short videos");
        if ([value isEqualToString:@"mid"]) return L(@"Medium-length videos");
        return L(@"Long videos");
    }
    return key;
}

// how strong, as up to five dots
- (NSString *)dotsFor:(double)weight
{
    NSInteger n = MAX(1, MIN(5, (NSInteger)ceil(fabs(weight) / 0.6)));
    NSMutableString *s = [NSMutableString string];
    for (NSInteger i = 0; i < 5; i++) [s appendString:i < n ? @"●" : @"○"];
    return s;
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return SecCount; }

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s
{
    switch (s) {
        case SecTopics: return (NSInteger)MAX((NSUInteger)1, self.topics.count);
        case SecLikes: return (NSInteger)MAX((NSUInteger)1, self.likes.count);
        case SecDislikes: return (NSInteger)MAX((NSUInteger)1, self.dislikes.count);
        case SecActions: return 2;
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s
{
    switch (s) {
        case SecTopics: return L(@"Topics it tried");
        case SecLikes: return L(@"What you like");
        case SecDislikes: return L(@"What you skip");
    }
    return nil;
}

- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s
{
    if (s == SecTopics) return L(@"How often a video of the topic held you. Topics nobody has tried yet still get their turn.");
    if (s == SecActions) return L(@"It learns only from how you watch: what you finish, skip, save or mark as not interested. None of it leaves this device. Swipe a row to make it forget it.");
    return nil;
}

- (BOOL)isPlaceholderAt:(NSIndexPath *)ip
{
    return (ip.section == SecTopics && !self.topics.count) || (ip.section == SecLikes && !self.likes.count) ||
           (ip.section == SecDislikes && !self.dislikes.count);
}

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip
{
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    [[TKTheme shared] styleCell:cell];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    if ([self isPlaceholderAt:ip]) {
        cell.textLabel.text = L(@"Nothing yet - keep watching.");
        cell.textLabel.textColor = [[TKTheme shared] secondaryTextColor];
        return cell;
    }
    if (ip.section == SecTopics) {
        NSDictionary *topic = self.topics[(NSUInteger)ip.row];
        cell.textLabel.text = [TKTaste localizedTopicName:[topic[@"id"] integerValue]];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0f %%", [topic[@"rate"] doubleValue] * 100.0];
    } else if (ip.section == SecLikes || ip.section == SecDislikes) {
        NSArray *e = (ip.section == SecLikes ? self.likes : self.dislikes)[(NSUInteger)ip.row];
        cell.textLabel.text = [self nameOfFeature:e[0]];
        cell.detailTextLabel.text = [self dotsFor:[e[1] doubleValue]];
    } else {
        cell.selectionStyle = UITableViewCellSelectionStyleBlue;
        if (ip.row == 0) {
            cell.textLabel.text = L(@"Video languages");
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else {
            cell.textLabel.text = L(@"Start over");
            cell.textLabel.textColor = [UIColor colorWithRed:0.8 green:0.2 blue:0.2 alpha:1];
        }
    }
    return cell;
}

- (BOOL)tableView:(UITableView *)t canEditRowAtIndexPath:(NSIndexPath *)ip
{
    return ip.section != SecActions && ![self isPlaceholderAt:ip];
}

- (NSString *)tableView:(UITableView *)t titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)ip { return L(@"Forget"); }

- (void)tableView:(UITableView *)t commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)ip
{
    if (style != UITableViewCellEditingStyleDelete) return;
    TKTaste *taste = [TKTaste shared];
    if (ip.section == SecTopics) [taste forgetTopic:[self.topics[(NSUInteger)ip.row][@"id"] integerValue]];
    else [taste forgetFeature:(ip.section == SecLikes ? self.likes : self.dislikes)[(NSUInteger)ip.row][0]];
    [self reload];
}

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip
{
    [t deselectRowAtIndexPath:ip animated:YES];
    if (ip.section != SecActions) return;
    if (ip.row == 0) {
        [self.navigationController pushViewController:[[TKLanguagesViewController alloc] init] animated:YES];
    } else {
        UIAlertView *a = [[UIAlertView alloc] initWithTitle:L(@"Start over") message:L(@"Forget everything it learned about you?")
                                                   delegate:self cancelButtonTitle:L(@"Cancel") otherButtonTitles:L(@"Forget everything"), nil];
        [a show];
    }
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex == alertView.cancelButtonIndex) return;
    [[TKTaste shared] reset];
    [self reload];
}

@end
