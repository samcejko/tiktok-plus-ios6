#import "TKNotificationsViewController.h"
#import "TKTikTok.h"
#import "TKProfileViewController.h"
#import "TKFeedViewController.h"
#import "TKImageLoader.h"
#import "TKTheme.h"
#import "TKUtils.h"
#import "TKCommon.h"

@interface TKNotificationsViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray *items;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) TKHTTPTask *task;
@end

@implementation TKNotificationsViewController

- (void)dealloc
{
    [_task cancel];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    TKTheme *theme = [TKTheme shared];
    self.title = L(@"Notifications");
    self.view.backgroundColor = [theme backgroundColor];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 64;
    [theme applyToTableView:self.tableView];
    [self.view addSubview:self.tableView];

    self.emptyLabel = [[UILabel alloc] initWithFrame:self.view.bounds];
    self.emptyLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.emptyLabel.text = L(@"No notifications yet.");
    self.emptyLabel.font = [UIFont systemFontOfSize:15];
    self.emptyLabel.textColor = [theme secondaryTextColor];
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.hidden = YES;
    [self.view addSubview:self.emptyLabel];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:[theme spinnerStyle]];
    self.spinner.hidesWhenStopped = YES;
    [self.view addSubview:self.spinner];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                                                           target:self
                                                                                           action:@selector(loadNotifications)];

    [self loadNotifications];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    self.spinner.center = CGPointMake(self.view.bounds.size.width / 2.0, self.view.bounds.size.height / 2.0);
}

- (void)loadNotifications
{
    [self.task cancel];
    [self.spinner startAnimating];
    self.emptyLabel.hidden = YES;

    self.task = [TKTikTok notificationsWithCount:40 completion:^(NSArray *notifications, NSError *error) {
        [self.spinner stopAnimating];
        self.items = notifications ?: @[];
        self.emptyLabel.hidden = (self.items.count > 0);
        [self.tableView reloadData];
    }];
}

#pragma mark - Table View

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *CellId = @"NotificationCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellId];
        [[TKTheme shared] styleCell:cell];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

        TKImageView *iv = [[TKImageView alloc] initWithFrame:CGRectMake(10, 10, 44, 44)];
        iv.tag = 101;
        iv.layer.cornerRadius = 22;
        iv.layer.masksToBounds = YES;
        [cell.contentView addSubview:iv];

        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(64, 10, cell.contentView.bounds.size.width - 74, 20)];
        title.tag = 102;
        title.font = [[TKTheme shared] titleFont];
        title.textColor = [[TKTheme shared] primaryTextColor];
        title.backgroundColor = [UIColor clearColor];
        title.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [cell.contentView addSubview:title];

        UILabel *detail = [[UILabel alloc] initWithFrame:CGRectMake(64, 32, cell.contentView.bounds.size.width - 74, 18)];
        detail.tag = 103;
        detail.font = [[TKTheme shared] smallFont];
        detail.textColor = [[TKTheme shared] secondaryTextColor];
        detail.backgroundColor = [UIColor clearColor];
        detail.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [cell.contentView addSubview:detail];
    }

    NSDictionary *item = self.items[indexPath.row];
    NSDictionary *user = TKDict(item[@"user"]);
    NSString *handle = TKStr(user[@"handle"]);
    NSString *name = TKStr(user[@"name"]);
    NSString *author = name.length ? name : (handle.length ? [@"@" stringByAppendingString:handle] : L(@"Someone"));
    NSString *text = TKStr(item[@"text"]);
    NSString *titleText = TKStr(item[@"title"]);
    if (!text.length && titleText.length) text = titleText;

    TKImageView *iv = (TKImageView *)[cell.contentView viewWithTag:101];
    UILabel *titleLabel = (UILabel *)[cell.contentView viewWithTag:102];
    UILabel *detailLabel = (UILabel *)[cell.contentView viewWithTag:103];

    titleLabel.text = author;
    detailLabel.text = text.length ? text : L(@"Interacted with your account");

    NSString *avatarURL = TKStr(user[@"avatar"]);
    UIImage *placeholder = [[TKTheme shared] avatarPlaceholderWithSize:44];
    [iv setImageURL:avatarURL placeholder:placeholder];

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *item = self.items[indexPath.row];
    NSString *videoId = TKStr(item[@"videoId"]);
    NSDictionary *user = TKDict(item[@"user"]);
    NSString *handle = TKStr(user[@"handle"]);

    if (videoId.length) {
        [TKTikTok resolveId:videoId author:handle completion:^(TKVideo *resolved, NSError *error) {
            if (resolved) {
                [TKFeedViewController openVideos:@[resolved] startIndex:0 title:L(@"Video") loadMore:nil];
            } else if (handle.length) {
                [TKProfileViewController openUser:handle];
            }
        }];
    } else if (handle.length) {
        [TKProfileViewController openUser:handle];
    }
}

@end
