#import "TKAlertView.h"
#import "TKSavedViewController.h"
#import "TKFeedViewController.h"
#import "TKModels.h"
#import "TKSettings.h"
#import "TKImageLoader.h"
#import "TKTheme.h"
#import "TKUtils.h"
#import "TKCommon.h"
#import "TKVideoLibrary.h"
#import "TKCollectionsViewController.h"

@interface TKSavedViewController () <UISearchBarDelegate, UIAlertViewDelegate>
@property (nonatomic, strong) NSArray *saved;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic) BOOL history;
@property (nonatomic, copy) NSString *collectionId;
@end

@implementation TKSavedViewController

- (instancetype)init { return [self initWithHistory:NO]; }
- (instancetype)initWithHistory:(BOOL)history
{
    if ((self = [super initWithStyle:UITableViewStylePlain])) _history = history;
    return self;
}
- (instancetype)initWithCollection:(NSString *)collectionId title:(NSString *)title
{
    if ((self=[self initWithHistory:NO])) { _collectionId=[collectionId copy]; self.title=title; }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    if (!self.collectionId) self.title = self.history ? L(@"Watch history") : L(@"Saved");
    [[TKTheme shared] applyToTableView:self.tableView];
    self.tableView.rowHeight = 92;
    if (!self.collectionId) self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(done)];
    if (self.history) self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:L(@"Clear") style:UIBarButtonItemStyleBordered target:self action:@selector(askToClear)];
    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 44)];
    self.searchBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.searchBar.delegate = self;
    self.searchBar.placeholder = L(@"Search author, caption or sound");
    self.searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.searchBar.autocorrectionType = UITextAutocorrectionTypeNo;
    [[TKTheme shared] applyToSearchBar:self.searchBar];
    self.tableView.tableHeaderView = self.searchBar;
    self.tableView.accessibilityLabel = self.title;
    [self.tableView addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(held:)]];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reload) name:TKLibraryDidChangeNotification object:nil];
}

- (void)dealloc { self.searchBar.delegate = nil; [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self reload]; }
- (void)reload
{
    NSArray *source=self.collectionId ? [TKSettings videosInCollection:self.collectionId] : (self.history ? [TKSettings watchHistory] : [TKSettings savedVideos]);
    self.saved = [TKVideoLibrary videos:source matching:self.searchBar.text];
    self.navigationItem.rightBarButtonItem.enabled = [TKSettings watchHistory].count > 0;
    [self.tableView reloadData];
}
- (void)done { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)searchBar:(UISearchBar *)bar textDidChange:(NSString *)text { [self reload]; }
- (void)searchBarSearchButtonClicked:(UISearchBar *)bar { [bar resignFirstResponder]; }
- (void)scrollViewWillBeginDragging:(UIScrollView *)view { [self.searchBar resignFirstResponder]; }
- (void)held:(UILongPressGestureRecognizer *)g
{
    if(g.state!=UIGestureRecognizerStateBegan)return;
    NSIndexPath *ip=[self.tableView indexPathForRowAtPoint:[g locationInView:self.tableView]]; if(!ip)return;
    [self.searchBar resignFirstResponder];
    [TKCollectionPicker addVideo:self.saved[(NSUInteger)ip.row] inView:self.view completion:nil];
}
- (void)askToClear
{
    [self.searchBar resignFirstResponder];
    [[[TKAlertView alloc] initWithTitle:L(@"Clear watch history") message:L(@"Remove local viewing history? Saved videos and your TikTok account stay unchanged.") delegate:self cancelButtonTitle:L(@"Cancel") otherButtonTitles:L(@"Clear"), nil] show];
}
- (void)alertView:(UIAlertView *)alert clickedButtonAtIndex:(NSInteger)index { if (index != alert.cancelButtonIndex) [TKSettings clearWatchHistory]; }

- (BOOL)shouldAutorotate { return YES; }
- (NSUInteger)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAll; }

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return (NSInteger)self.saved.count; }

- (NSString *)footerText
{
    if(self.collectionId) return self.saved.count ? L(@"Swipe to remove a post from this collection. It stays in Saved. Hold a post to add it to another collection.") : L(@"Add posts from a video’s menu or hold a post in Saved.");
    if (self.saved.count) return self.history ? L(@"The last 200 watched posts are kept only on this device.") : nil;
    if ([self.searchBar.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length) return L(@"No matching posts.");
    return self.history ? L(@"Posts appear here after you watch them. History stays on this device.") : L(@"Tap the star on a video to keep it here.");
}

- (CGFloat)tableView:(UITableView *)table heightForFooterInSection:(NSInteger)section
{
    NSString *text = [self footerText];
    if (!text.length) return 0.01;
    CGSize size = [text sizeWithFont:[UIFont systemFontOfSize:13] constrainedToSize:CGSizeMake(MAX(1, table.bounds.size.width - 32), CGFLOAT_MAX) lineBreakMode:NSLineBreakByWordWrapping];
    return ceilf(size.height) + 20;
}
- (UIView *)tableView:(UITableView *)table viewForFooterInSection:(NSInteger)section
{
    NSString *text = [self footerText];
    if (!text.length) return nil;
    UIView *view = [[UIView alloc] initWithFrame:CGRectMake(0, 0, table.bounds.size.width, [self tableView:table heightForFooterInSection:section])];
    view.backgroundColor = [[TKTheme shared] backgroundColor];
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectInset(view.bounds, 16, 10)];
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    label.backgroundColor = [UIColor clearColor];
    label.textColor = [[TKTheme shared] secondaryTextColor];
    label.font = [UIFont systemFontOfSize:13];
    label.numberOfLines = 0;
    label.text = text;
    [view addSubview:label];
    return view;
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
    NSString *caption = [TKUtils truncate:[TKUtils displayText:TKStr(d[@"desc"])] to:80] ?: @"";
    if (self.history && TKDbl(d[@"watchedAt"]) > 0) {
        NSString *date = [NSDateFormatter localizedStringFromDate:[NSDate dateWithTimeIntervalSince1970:TKDbl(d[@"watchedAt"])] dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle];
        caption = [NSString stringWithFormat:@"%@\n%@", date, caption];
    }
    cell.detailTextLabel.text = caption;
    cell.detailTextLabel.numberOfLines = 2;
    return cell;
}

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip
{
    [t deselectRowAtIndexPath:ip animated:YES];
    [self.searchBar resignFirstResponder];
    NSMutableArray *videos = [NSMutableArray array];
    for (NSDictionary *d in self.saved) { TKVideo *v = [TKVideo videoFromJSON:d]; if (v) [videos addObject:v]; }
    TKFeedViewController *feed = [[TKFeedViewController alloc] initWithVideos:videos startIndex:ip.row title:self.title];
    feed.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:feed animated:YES completion:nil];
}

- (void)tableView:(UITableView *)t commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)ip
{
    if (style == UITableViewCellEditingStyleDelete) {
        NSString *vid = TKStr(self.saved[(NSUInteger)ip.row][@"id"]);
        if (self.collectionId) [TKSettings removeVideo:vid fromCollection:self.collectionId];
        else if (self.history) [TKSettings removeFromWatchHistory:vid];
        else [TKSettings unsaveVideo:vid];
        [self reload];
    }
}

@end
