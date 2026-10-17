#import "TKSearchViewController.h"
#import "TKGridViewController.h"
#import "TKLinkRouter.h"
#import "TKTikTok.h"
#import "TKHTTP.h"
#import "TKModels.h"
#import "TKSettings.h"
#import "TKImageLoader.h"
#import "TKTheme.h"
#import "TKUtils.h"
#import "TKCommon.h"

enum { TKTabVideos, TKTabCreators, TKTabHashtags, TKTabSounds };

static const NSUInteger TKSearchListMax = 40;     // rows per tab

#pragma mark - The video results

@interface TKSearchResultsViewController : TKGridViewController
@property (nonatomic, copy) NSString *query;
@property (nonatomic, strong) NSMutableArray *users;      // TKProfile: the creators TikTok put first
@property (nonatomic) long long offset;
@property (nonatomic, copy) dispatch_block_t changed;      // a page arrived
- (instancetype)initWithQuery:(NSString *)query;
@end

@implementation TKSearchResultsViewController

- (instancetype)initWithQuery:(NSString *)query
{
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _query = [query copy];
        _users = [NSMutableArray array];
    }
    return self;
}

- (TKHTTPTask *)fetchPageAfterFirst:(BOOL)more completion:(void (^)(NSArray *, BOOL, NSError *))completion
{
    if (!more) { self.offset = 0; [self.users removeAllObjects]; }
    return [TKTikTok search:self.query offset:self.offset completion:^(TKVideoPage *page, NSError *error) {
        if (page) {
            self.offset = page.cursor;
            for (TKProfile *u in page.users) {
                BOOL known = NO;
                for (TKProfile *k in self.users) if ([k.handle caseInsensitiveCompare:u.handle] == NSOrderedSame) known = YES;
                if (!known) [self.users addObject:u];
            }
        }
        completion(page.videos, page.hasMore, error);
        if (self.changed) self.changed();
    }];
}

- (NSString *)emptyMessage { return L(@"Nothing found."); }
- (NSString *)feedTitle { return self.query; }

@end

#pragma mark - Search

@interface TKSearchViewController () <UISearchBarDelegate, UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) NSString *initialQuery;
@property (nonatomic, copy) NSString *query;               // what the results are for
@property (nonatomic, strong) UISearchBar *searchBar;      // its scope bar (iOS 6) switches the tabs of the results
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) TKSearchResultsViewController *results;
@property (nonatomic, strong) NSArray *suggestions;        // NSString, for suggestionsText
@property (nonatomic, copy) NSString *suggestionsText;
@property (nonatomic, strong) TKHTTPTask *suggestTask;
@property (nonatomic, strong) TKHashtag *exactHashtag;      // a hashtag named exactly like the search
@property (nonatomic, strong) NSArray *rows;               // NSDictionary: kind + what it shows
@property (nonatomic) BOOL typing;                         // the keyboard is up
@property (nonatomic) CGFloat keyboardHeight;
@end

@implementation TKSearchViewController

- (instancetype)initWithQuery:(NSString *)query
{
    if ((self = [super initWithNibName:nil bundle:nil])) _initialQuery = [query copy];
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [self.suggestTask cancel];
    self.searchBar.delegate = nil;
    self.table.delegate = nil;
    self.table.dataSource = nil;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    TKTheme *theme = [TKTheme shared];
    self.title = L(@"Search");
    self.view.backgroundColor = [theme backgroundColor];

    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 44)];
    self.searchBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.searchBar.placeholder = L(@"Search videos, creators, hashtags");
    self.searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.searchBar.autocorrectionType = UITextAutocorrectionTypeNo;
    self.searchBar.delegate = self;
    self.searchBar.scopeButtonTitles = @[ L(@"Videos"), L(@"Creators"), L(@"Hashtags"), L(@"Sounds") ];
    self.searchBar.selectedScopeButtonIndex = TKTabVideos;
    self.searchBar.showsScopeBar = NO;
    [theme applyToSearchBar:self.searchBar];
    [self.view addSubview:self.searchBar];

    self.table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.table.dataSource = self;
    self.table.delegate = self;
    [theme applyToTableView:self.table];
    self.table.backgroundColor = [theme backgroundColor];
    [self.view addSubview:self.table];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
    if (self.initialQuery.length) [self searchFor:self.initialQuery];
    else [self rebuildRows];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    if (!self.query.length && !self.searchBar.isFirstResponder && !self.initialQuery.length) [self.searchBar becomeFirstResponder];
    self.initialQuery = nil;
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [self.searchBar resignFirstResponder];
}

- (BOOL)shouldAutorotate { return YES; }
- (NSUInteger)supportedInterfaceOrientations { return TKIsPad() ? UIInterfaceOrientationMaskAll : UIInterfaceOrientationMaskPortrait; }

- (BOOL)showingResults { return self.query.length > 0 && !self.typing; }
- (NSInteger)tab { return self.searchBar.selectedScopeButtonIndex; }

- (void)viewWillLayoutSubviews
{
    [super viewWillLayoutSubviews];
    CGSize s = self.view.bounds.size;
    BOOL scope = [self showingResults];
    if (self.searchBar.showsScopeBar != scope) self.searchBar.showsScopeBar = scope;
    // (44, 88 with the scope bar, on iOS 6; iOS 11+ bars are taller and say so themselves)
    CGFloat top = ceilf([self.searchBar sizeThatFits:CGSizeMake(s.width, 0)].height);
    if (top < 44) top = scope ? 88 : 44;
    self.searchBar.frame = CGRectMake(0, 0, s.width, top);
    CGRect content = CGRectMake(0, top, s.width, s.height - top);
    self.table.frame = content;
    self.results.view.frame = content;
    BOOL grid = [self showingResults] && [self tab] == TKTabVideos;
    self.results.view.hidden = !grid;
    self.table.hidden = grid;
    UIEdgeInsets inset = UIEdgeInsetsMake(0, 0, MAX(0, self.keyboardHeight - (s.height - CGRectGetMaxY(content))), 0);
    self.table.contentInset = inset;
    self.table.scrollIndicatorInsets = inset;
}

#pragma mark - Searching

- (void)searchFor:(NSString *)text
{
    NSString *q = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!q.length) return;
    self.searchBar.text = q;
    [self.searchBar resignFirstResponder];
    [TKSettings addSearch:q];
    BOOL oneWord = [q rangeOfCharacterFromSet:[NSCharacterSet whitespaceCharacterSet]].location == NSNotFound;
    if (oneWord && q.length > 1 && [q hasPrefix:@"#"]) { [TKLinkRouter openHashtag:[q substringFromIndex:1]]; [self rebuildRows]; return; }
    if (oneWord && q.length > 1 && [q hasPrefix:@"@"]) { [TKLinkRouter openProfile:[q substringFromIndex:1]]; [self rebuildRows]; return; }

    self.query = q;
    self.exactHashtag = nil;
    if (self.results) {
        [self.results willMoveToParentViewController:nil];
        [self.results.view removeFromSuperview];
        [self.results removeFromParentViewController];
    }
    self.results = [[TKSearchResultsViewController alloc] initWithQuery:q];
    __weak TKSearchViewController *weakSelf = self;
    self.results.changed = ^{ [weakSelf rebuildRows]; };
    [self addChildViewController:self.results];
    [self.view insertSubview:self.results.view belowSubview:self.table];
    [self.results didMoveToParentViewController:self];
    self.searchBar.selectedScopeButtonIndex = TKTabVideos;

    // a hashtag named like the search (its name has no spaces)
    NSString *joined = [[q componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] componentsJoinedByString:@""];
    if (joined.length >= 2) {
        [TKTikTok hashtag:joined cursor:0 completion:^(TKVideoPage *page, NSError *error) {
            TKSearchViewController *me = weakSelf;
            if (!me || ![q isEqualToString:me.query] || !page.hashtag) return;
            me.exactHashtag = page.hashtag;
            [me rebuildRows];
        }];
    }
    [self.view setNeedsLayout];
    [self rebuildRows];
}

- (void)tabChanged
{
    [self.view setNeedsLayout];
    [self rebuildRows];
    [self.table setContentOffset:CGPointZero animated:NO];
}

- (void)askSuggestions
{
    NSString *text = [self.searchBar.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    [self.suggestTask cancel];
    if (!text.length) return;
    __weak TKSearchViewController *weakSelf = self;
    self.suggestTask = [TKTikTok suggestionsFor:text completion:^(NSArray *words, NSError *error) {
        TKSearchViewController *me = weakSelf;
        if (!me) return;
        me.suggestions = words ?: @[];
        me.suggestionsText = text;
        [me rebuildRows];
    }];
}

#pragma mark - Rows

- (void)rebuildRows
{
    NSMutableArray *rows = [NSMutableArray array];
    NSString *text = [self.searchBar.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
    if (self.typing && text.length) {
        [rows addObject:@{ @"kind": @"suggest", @"text": text }];
        if ([self.suggestionsText isEqualToString:text] || [text hasPrefix:self.suggestionsText ?: @"\x01"]) {
            for (NSString *w in self.suggestions) if ([w caseInsensitiveCompare:text] != NSOrderedSame) [rows addObject:@{ @"kind": @"suggest", @"text": w }];
        }
    } else if (![self showingResults]) {
        for (NSString *q in [TKSettings searchHistory]) [rows addObject:@{ @"kind": @"history", @"text": q }];
        if (rows.count) [rows addObject:@{ @"kind": @"clear" }];
        else [rows addObject:@{ @"kind": @"note", @"text": L(@"Search TikTok for videos, creators, hashtags and sounds.") }];
    } else if ([self tab] == TKTabCreators) {
        [rows addObjectsFromArray:[self creatorRows]];
    } else if ([self tab] == TKTabHashtags) {
        [rows addObjectsFromArray:[self hashtagRows]];
    } else if ([self tab] == TKTabSounds) {
        [rows addObjectsFromArray:[self soundRows]];
    }
    if ([self showingResults] && [self tab] != TKTabVideos && !rows.count)
        [rows addObject:@{ @"kind": @"note", @"text": self.results.loading ? L(@"Searching…") : L(@"Nothing found.") }];
    self.rows = rows;
    [self.table reloadData];
}

// The creators TikTok names first, then those of the videos found
- (NSArray *)creatorRows
{
    NSMutableArray *rows = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (TKProfile *p in self.results.users) {
        if (!p.handle.length || [seen containsObject:[p.handle lowercaseString]]) continue;
        [seen addObject:[p.handle lowercaseString]];
        [rows addObject:@{ @"kind": @"user", @"profile": p }];
    }
    for (TKVideo *v in self.results.videos) {
        if (!v.author.length || [seen containsObject:[v.author lowercaseString]] || rows.count >= TKSearchListMax) continue;
        [seen addObject:[v.author lowercaseString]];
        TKProfile *p = [[TKProfile alloc] init];
        p.handle = v.author;
        p.name = v.authorName;
        p.avatarURL = v.authorAvatarURL;
        p.liveRoom = v.authorLiveRoom;
        [rows addObject:@{ @"kind": @"user", @"profile": p }];
    }
    return rows;
}

// The hashtag named like the search, then the ones the videos found carry (the most frequent first)
- (NSArray *)hashtagRows
{
    NSMutableArray *rows = [NSMutableArray array];
    NSString *exact = [self.exactHashtag.name lowercaseString];
    if (self.exactHashtag) [rows addObject:@{ @"kind": @"tag", @"name": self.exactHashtag.name, @"tag": self.exactHashtag }];
    NSCountedSet *counts = [[NSCountedSet alloc] init];
    for (TKVideo *v in self.results.videos) for (NSString *t in v.tags) if (t.length && ![t isEqualToString:exact]) [counts addObject:t];
    NSArray *sorted = [[counts allObjects] sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSUInteger ca = [counts countForObject:a], cb = [counts countForObject:b];
        return ca == cb ? [a compare:b] : (ca > cb ? NSOrderedAscending : NSOrderedDescending);
    }];
    for (NSString *t in sorted) { if (rows.count >= TKSearchListMax) break; [rows addObject:@{ @"kind": @"tag", @"name": t }]; }
    return rows;
}

// The sounds of the videos found: songs first, then people's own sounds
- (NSArray *)soundRows
{
    NSMutableArray *songs = [NSMutableArray array], *own = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (TKVideo *v in self.results.videos) {
        if (!v.musicId.length || !v.music.length || [seen containsObject:v.musicId]) continue;
        [seen addObject:v.musicId];
        NSDictionary *row = @{ @"kind": @"sound", @"id": v.musicId, @"title": v.music, @"author": v.musicAuthor ?: @"", @"cover": v.musicCoverURL ?: @"" };
        [(v.musicOriginal ? own : songs) addObject:row];
    }
    [songs addObjectsFromArray:own];
    return songs.count > TKSearchListMax ? [songs subarrayWithRange:NSMakeRange(0, TKSearchListMax)] : songs;
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return (NSInteger)self.rows.count; }

- (CGFloat)tableView:(UITableView *)t heightForRowAtIndexPath:(NSIndexPath *)ip
{
    NSString *kind = self.rows[(NSUInteger)ip.row][@"kind"];
    if ([kind isEqualToString:@"user"] || [kind isEqualToString:@"sound"]) return 60;
    if ([kind isEqualToString:@"note"]) return 90;
    return 46;
}

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip
{
    NSDictionary *row = self.rows[(NSUInteger)ip.row];
    NSString *kind = row[@"kind"];
    TKTheme *theme = [TKTheme shared];
    BOOL pictured = [kind isEqualToString:@"user"] || [kind isEqualToString:@"sound"];
    NSString *reuse = pictured ? @"pictured" : @"plain";
    UITableViewCell *cell = [t dequeueReusableCellWithIdentifier:reuse];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuse];
        [theme styleCell:cell];
        cell.backgroundColor = [theme backgroundColor];
        if (pictured) {
            TKImageView *pic = [[TKImageView alloc] initWithFrame:CGRectMake(12, 8, 44, 44)];
            pic.tag = 77;
            pic.contentMode = UIViewContentModeScaleAspectFill;
            pic.clipsToBounds = YES;
            pic.maxPixels = 120;
            pic.backgroundColor = [UIColor colorWithWhite:0.25 alpha:1];
            [cell.contentView addSubview:pic];
            cell.indentationLevel = 4;
            cell.indentationWidth = 14;
        }
    }
    cell.textLabel.font = [UIFont systemFontOfSize:16];
    cell.textLabel.textColor = [theme primaryTextColor];
    cell.textLabel.textAlignment = NSTextAlignmentLeft;
    cell.textLabel.numberOfLines = 1;
    cell.detailTextLabel.text = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleGray;
    TKImageView *pic = (TKImageView *)[cell.contentView viewWithTag:77];
    if ([kind isEqualToString:@"suggest"] || [kind isEqualToString:@"history"]) {
        cell.textLabel.text = [([kind isEqualToString:@"history"] ? @"🕘  " : @"🔍  ") stringByAppendingString:row[@"text"]];
    } else if ([kind isEqualToString:@"clear"]) {
        cell.textLabel.text = L(@"Clear search history");
        cell.textLabel.font = [UIFont systemFontOfSize:15];
        cell.textLabel.textColor = [theme linkColor];
    } else if ([kind isEqualToString:@"note"]) {
        cell.textLabel.text = row[@"text"];
        cell.textLabel.numberOfLines = 0;
        cell.textLabel.font = [UIFont systemFontOfSize:15];
        cell.textLabel.textColor = [theme secondaryTextColor];
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if ([kind isEqualToString:@"user"]) {
        TKProfile *p = row[@"profile"];
        pic.layer.cornerRadius = 22;
        [pic setImageURL:p.avatarURL placeholder:nil];
        NSString *name = p.name.length ? [TKUtils displayText:p.name] : p.handle;
        cell.textLabel.text = p.verified ? [name stringByAppendingString:@" ✓"] : name;
        NSMutableString *detail = [NSMutableString stringWithFormat:@"@%@", p.handle];
        if (p.followers) [detail appendFormat:@"  ·  %@", [NSString stringWithFormat:L(@"%@ followers"), [TKUtils formatBigCount:p.followers]]];
        if (p.liveRoom.length) [detail appendString:@"  ·  LIVE"];
        cell.detailTextLabel.text = detail;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if ([kind isEqualToString:@"tag"]) {
        cell.textLabel.text = [@"# " stringByAppendingString:row[@"name"]];
        TKHashtag *tag = row[@"tag"];
        if (tag.videoCount) cell.detailTextLabel.text = [NSString stringWithFormat:L(@"%@ videos"), [TKUtils formatBigCount:tag.videoCount]];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if ([kind isEqualToString:@"sound"]) {
        pic.layer.cornerRadius = 6;
        [pic setImageURL:row[@"cover"] placeholder:nil];
        cell.textLabel.text = [@"♪ " stringByAppendingString:[TKUtils displayText:row[@"title"]]];
        cell.detailTextLabel.text = [TKUtils displayText:row[@"author"]];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    cell.detailTextLabel.textColor = [theme secondaryTextColor];
    return cell;
}

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip
{
    [t deselectRowAtIndexPath:ip animated:YES];
    NSDictionary *row = self.rows[(NSUInteger)ip.row];
    NSString *kind = row[@"kind"];
    if ([kind isEqualToString:@"suggest"] || [kind isEqualToString:@"history"]) [self searchFor:row[@"text"]];
    else if ([kind isEqualToString:@"clear"]) { [TKSettings clearSearchHistory]; [self rebuildRows]; }
    else if ([kind isEqualToString:@"user"]) [TKLinkRouter openProfile:[(TKProfile *)row[@"profile"] handle]];
    else if ([kind isEqualToString:@"tag"]) [TKLinkRouter openHashtag:row[@"name"]];
    else if ([kind isEqualToString:@"sound"]) [TKLinkRouter openSound:row[@"id"] title:row[@"title"]];
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView
{
    if (scrollView == self.table && self.typing) [self.searchBar resignFirstResponder];
}

#pragma mark - Search bar

- (void)searchBarTextDidBeginEditing:(UISearchBar *)bar
{
    self.typing = YES;
    [bar setShowsCancelButton:YES animated:YES];
    [self.view setNeedsLayout];
    [self rebuildRows];
    [self askSuggestions];
}

- (void)searchBarTextDidEndEditing:(UISearchBar *)bar
{
    self.typing = NO;
    [bar setShowsCancelButton:NO animated:YES];
    [self.view setNeedsLayout];
    [self rebuildRows];
}

- (void)searchBar:(UISearchBar *)bar textDidChange:(NSString *)text
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(askSuggestions) object:nil];
    [self performSelector:@selector(askSuggestions) withObject:nil afterDelay:0.25];
    [self rebuildRows];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)bar { [self searchFor:bar.text]; }

- (void)searchBar:(UISearchBar *)bar selectedScopeButtonIndexDidChange:(NSInteger)selectedScope { [self tabChanged]; }

- (void)searchBarCancelButtonClicked:(UISearchBar *)bar
{
    bar.text = self.query ?: @"";
    [bar resignFirstResponder];
}

#pragma mark - Keyboard

- (void)keyboardWillShow:(NSNotification *)note
{
    CGRect frame = [self.view convertRect:[note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue] fromView:nil];
    self.keyboardHeight = MAX(0, self.view.bounds.size.height - frame.origin.y);
    [self.view setNeedsLayout];
}

- (void)keyboardWillHide:(NSNotification *)note
{
    self.keyboardHeight = 0;
    [self.view setNeedsLayout];
}

@end
