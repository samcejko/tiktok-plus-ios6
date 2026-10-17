#import "TKLanguagesViewController.h"
#import "TKSettings.h"
#import "TKTheme.h"
#import "TKCommon.h"

@interface TKLanguagesViewController ()
@property (nonatomic, strong) NSArray *codes;
@end

@implementation TKLanguagesViewController

+ (NSString *)nameOfLanguage:(NSString *)code
{
    if (!code.length || [code isEqualToString:@"un"]) return L(@"No caption");
    if ([code isEqualToString:@"*"]) return L(@"Other languages");
    NSString *ui = [[NSLocale preferredLanguages] firstObject] ?: @"en";
    NSString *name = [[[NSLocale alloc] initWithLocaleIdentifier:ui] displayNameForKey:NSLocaleLanguageCode value:code];
    if (!name.length) return code;
    return [[[name substringToIndex:1] uppercaseString] stringByAppendingString:[name substringFromIndex:1]];
}

- (instancetype)init { return [super initWithStyle:UITableViewStyleGrouped]; }

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = L(@"Video languages");
    [[TKTheme shared] applyToTableView:self.tableView];
    self.codes = [[TKSettings knownLanguages] arrayByAddingObjectsFromArray:@[ @"*", @"un" ]];
}

- (BOOL)shouldAutorotate { return YES; }
- (NSUInteger)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAll; }

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return (NSInteger)self.codes.count; }

- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s
{
    return L(@"Videos in languages you untick are left out of your feed. TikTok guesses the language from the caption.");
}

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip
{
    UITableViewCell *cell = [t dequeueReusableCellWithIdentifier:@"lang"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"lang"];
        [[TKTheme shared] styleCell:cell];
    }
    NSString *code = self.codes[(NSUInteger)ip.row];
    cell.textLabel.text = [TKLanguagesViewController nameOfLanguage:code];
    cell.accessoryType = [[TKSettings hiddenLanguages] containsObject:code] ? UITableViewCellAccessoryNone : UITableViewCellAccessoryCheckmark;
    return cell;
}

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip
{
    [t deselectRowAtIndexPath:ip animated:YES];
    NSString *code = self.codes[(NSUInteger)ip.row];
    NSMutableArray *hidden = [[TKSettings hiddenLanguages] mutableCopy];
    if ([hidden containsObject:code]) [hidden removeObject:code];
    else [hidden addObject:code];
    [TKSettings setHiddenLanguages:hidden];
    [t reloadRowsAtIndexPaths:@[ ip ] withRowAnimation:UITableViewRowAnimationNone];
}

@end
