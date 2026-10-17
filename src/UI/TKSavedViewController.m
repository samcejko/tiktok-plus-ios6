#import "TKSavedViewController.h"
#import "TKFeedViewController.h"
#import "TKModels.h"
#import "TKSettings.h"
#import "TKImageLoader.h"
#import "TKTheme.h"
#import "TKUtils.h"
#import "TKCommon.h"

@interface TKSavedViewController ()
@property (nonatomic, strong) NSArray *saved;
@end

@implementation TKSavedViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = L(@"Saved");
    [[TKTheme shared] applyToTableView:self.tableView];
    self.tableView.rowHeight = 92;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(done)];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reload) name:TKLibraryDidChangeNotification object:nil];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self reload]; }
- (void)reload { self.saved = [TKSettings savedVideos]; [self.tableView reloadData]; }
- (void)done { [self dismissViewControllerAnimated:YES completion:nil]; }

- (BOOL)shouldAutorotate { return YES; }
- (NSUInteger)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAll; }

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return (NSInteger)self.saved.count; }

- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s
{
    return self.saved.count ? nil : L(@"Tap the star on a video to keep it here.");
}

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip
{
    UITableViewCell *cell = [t dequeueReusableCellWithIdentifier:@"s"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"s"];
        [[TKTheme shared] styleCell:cell];
        TKImageView *thumb = [[TKImageView alloc] initWithFrame:CGRectMake(8, 6, 60, 80)];
        thumb.tag = 77;
        thumb.contentMode = UIViewContentModeScaleAspectFill;
        thumb.clipsToBounds = YES;
        thumb.backgroundColor = [UIColor colorWithWhite:0.1 alpha:1];
        [cell.contentView addSubview:thumb];
        cell.indentationLevel = 5;
        cell.indentationWidth = 14;
    }
    NSDictionary *d = self.saved[(NSUInteger)ip.row];
    TKImageView *thumb = (TKImageView *)[cell viewWithTag:77];
    [thumb setImageURL:TKStr(d[@"cover"]) placeholder:nil];
    cell.textLabel.text = [@"@" stringByAppendingString:TKStr(d[@"author"]) ?: @""];
    cell.detailTextLabel.text = [TKUtils truncate:[TKUtils displayText:TKStr(d[@"desc"])] to:80];
    cell.detailTextLabel.numberOfLines = 2;
    return cell;
}

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip
{
    [t deselectRowAtIndexPath:ip animated:YES];
    NSMutableArray *videos = [NSMutableArray array];
    for (NSDictionary *d in self.saved) { TKVideo *v = [TKVideo videoFromJSON:d]; if (v) [videos addObject:v]; }
    TKFeedViewController *feed = [[TKFeedViewController alloc] initWithVideos:videos startIndex:ip.row title:L(@"Saved")];
    feed.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:feed animated:YES completion:nil];
}

- (void)tableView:(UITableView *)t commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)ip
{
    if (style == UITableViewCellEditingStyleDelete) {
        [TKSettings unsaveVideo:TKStr(self.saved[(NSUInteger)ip.row][@"id"])];
        [self reload];
    }
}

@end
