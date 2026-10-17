#import "TKLivesViewController.h"
#import "TKLinkRouter.h"
#import "TKTikTok.h"
#import "TKImageLoader.h"
#import "TKTheme.h"
#import "TKUtils.h"
#import "TKCommon.h"

static NSString * const TKLiveCellId = @"live";

@interface TKLiveRoomCell : UITableViewCell
@property (nonatomic, strong) TKImageView *avatar;
@property (nonatomic, strong) UILabel *pill;
@end

@implementation TKLiveRoomCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    if ((self = [super initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseIdentifier])) {
        _avatar = [[TKImageView alloc] initWithFrame:CGRectMake(0, 0, 48, 48)];
        _avatar.contentMode = UIViewContentModeScaleAspectFill;
        _avatar.clipsToBounds = YES;
        _avatar.layer.cornerRadius = 24;
        _avatar.layer.borderWidth = 2;
        _avatar.layer.borderColor = [[TKTheme shared] liveColor].CGColor;
        _avatar.backgroundColor = [UIColor colorWithWhite:0.25 alpha:1];
        [self.contentView addSubview:_avatar];
        _pill = [[UILabel alloc] initWithFrame:CGRectZero];
        _pill.text = @"LIVE";   // (TikTok's own word for it, in every language)
        _pill.font = [UIFont boldSystemFontOfSize:11];
        _pill.textColor = [UIColor whiteColor];
        _pill.textAlignment = NSTextAlignmentCenter;
        _pill.backgroundColor = [[TKTheme shared] liveColor];
        _pill.layer.cornerRadius = 3;
        _pill.layer.masksToBounds = YES;
        [self.contentView addSubview:_pill];
        self.textLabel.font = [UIFont boldSystemFontOfSize:16];
        self.detailTextLabel.font = [UIFont systemFontOfSize:13];
    }
    return self;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    CGSize s = self.contentView.bounds.size;
    self.avatar.frame = CGRectMake(12, floorf((s.height - 48) / 2), 48, 48);
    self.pill.frame = CGRectMake(s.width - 50, floorf((s.height - 16) / 2), 38, 16);
    CGFloat x = 72, w = MAX(40, s.width - x - 60);
    self.textLabel.frame = CGRectMake(x, floorf(s.height / 2) - 20, w, 20);
    self.detailTextLabel.frame = CGRectMake(x, floorf(s.height / 2) + 2, w, 18);
}

@end

@interface TKLivesViewController ()
@property (nonatomic, strong) NSArray *rooms;          // NSDictionary: room, user, name, avatar, seen
@property (nonatomic) BOOL loading;
@property (nonatomic, copy) NSString *message;         // instead of rows: nothing found, or what went wrong
@end

@implementation TKLivesViewController

- (instancetype)init { return [super initWithStyle:UITableViewStylePlain]; }

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = L(@"Live now");
    [[TKTheme shared] applyToTableView:self.tableView];
    self.tableView.rowHeight = 64;
    [self.tableView registerClass:[TKLiveRoomCell class] forCellReuseIdentifier:TKLiveCellId];
    if (self.navigationController.viewControllers.firstObject == self)
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(done)];
    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self action:@selector(load) forControlEvents:UIControlEventValueChanged];
    self.message = L(@"Looking for live streams…");
    [self load];
}

- (void)done { [self dismissViewControllerAnimated:YES completion:nil]; }
- (BOOL)shouldAutorotate { return YES; }
- (NSUInteger)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAll; }

- (void)load
{
    if (self.loading) return;
    self.loading = YES;
    [TKTikTok liveRooms:^(NSArray *rooms, NSError *error) {
        self.loading = NO;
        [self.refreshControl endRefreshing];
        if (error && !self.rooms.count) {
            self.message = error.localizedDescription;
        } else if (rooms) {
            self.rooms = rooms;
            self.message = rooms.count ? nil : L(@"Nobody from the feed is live right now. Pull down to look again.");
        }
        [self.tableView reloadData];
    }];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s
{
    return self.message ? 1 : (NSInteger)self.rooms.count;
}

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip
{
    if (self.message) {
        UITableViewCell *cell = [t dequeueReusableCellWithIdentifier:@"message"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"message"];
        [[TKTheme shared] styleCell:cell];
        cell.textLabel.text = self.message;
        cell.textLabel.numberOfLines = 0;
        cell.textLabel.font = [UIFont systemFontOfSize:14];
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.textColor = [[TKTheme shared] secondaryTextColor];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
    TKLiveRoomCell *cell = [t dequeueReusableCellWithIdentifier:TKLiveCellId forIndexPath:ip];
    [[TKTheme shared] styleCell:cell];
    NSDictionary *r = self.rooms[(NSUInteger)ip.row];
    NSString *handle = TKStr(r[@"user"]) ?: @"";
    NSString *name = TKStr(r[@"name"]);
    cell.textLabel.text = name.length ? [TKUtils displayText:name] : [@"@" stringByAppendingString:handle];
    cell.detailTextLabel.text = [@"@" stringByAppendingString:handle];
    [cell.avatar setImageURL:TKStr(r[@"avatar"]) placeholder:nil];
    return cell;
}

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip
{
    [t deselectRowAtIndexPath:ip animated:YES];
    if (self.message) return;
    NSString *room = TKStr(self.rooms[(NSUInteger)ip.row][@"room"]);
    if (room.length) [TKLinkRouter openLiveRoom:room];
}

@end
