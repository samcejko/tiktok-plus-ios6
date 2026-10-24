#import "TKFavoritesViewController.h"
#import "TKSettings.h"
#import "TKLinkRouter.h"
#import "TKImageLoader.h"
#import "TKTheme.h"
#import "TKCommon.h"

@interface TKFavoritesViewController () <UISearchBarDelegate>
@property (nonatomic, copy) NSString *kind;
@property (nonatomic, strong) NSArray *items;
@property (nonatomic, strong) UISearchBar *searchBar;
@end
@implementation TKFavoritesViewController
- (instancetype)initWithKind:(NSString *)kind { if ((self=[super initWithStyle:UITableViewStylePlain])) _kind=[kind copy]; return self; }
- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title=[self.kind isEqual:@"sounds"] ? L(@"Favorite sounds") : ([self.kind isEqual:@"blocked"] ? L(@"Hidden creators") : L(@"Favorite creators"));
    [[TKTheme shared] applyToTableView:self.tableView]; self.tableView.rowHeight=66;
    if(self.navigationController.viewControllers.count<=1) self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(done)];
    self.navigationItem.rightBarButtonItem=self.editButtonItem;
    self.searchBar=[[UISearchBar alloc] initWithFrame:CGRectMake(0,0,self.view.bounds.size.width,44)];
    self.searchBar.delegate=self; self.searchBar.placeholder=L(@"Search"); self.searchBar.autocapitalizationType=UITextAutocapitalizationTypeNone; self.searchBar.autocorrectionType=UITextAutocorrectionTypeNo;
    [[TKTheme shared] applyToSearchBar:self.searchBar]; self.tableView.tableHeaderView=self.searchBar;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reload) name:TKLibraryDidChangeNotification object:nil]; [self reload];
}
- (void)dealloc { self.searchBar.delegate=nil; [[NSNotificationCenter defaultCenter] removeObserver:self]; }
- (void)done { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)reload
{
    NSArray *source=[self.kind isEqual:@"sounds"] ? [TKSettings favoriteSounds] : [TKSettings favoriteCreators];
    if ([self.kind isEqual:@"blocked"]) { NSMutableArray *a=[NSMutableArray array]; for(NSString *h in [TKSettings blockedCreators])[a addObject:@{@"handle":h,@"name":h}]; source=a; }
    NSMutableArray *a=[NSMutableArray array]; NSString *q=[self.searchBar.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    for(NSDictionary *d in source) {
        NSString *text=[NSString stringWithFormat:@"%@ %@ %@",TKStr(d[@"handle"]) ?: @"",TKStr(d[@"name"]) ?: @"",TKStr(d[@"author"]) ?: @""];
        if(!q.length || [text rangeOfString:q options:NSCaseInsensitiveSearch|NSDiacriticInsensitiveSearch].location!=NSNotFound)[a addObject:d];
    }
    self.items=a; [self.tableView reloadData];
}
- (void)searchBar:(UISearchBar *)bar textDidChange:(NSString *)text { [self reload]; }
- (void)searchBarSearchButtonClicked:(UISearchBar *)bar { [bar resignFirstResponder]; }
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return self.items.count; }
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s
{
    return [self.kind isEqual:@"blocked"] ? L(@"Swipe to unhide a creator.") : (self.items.count ? nil : L(@"No favorites yet."));
}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip
{
    UITableViewCell *cell=[t dequeueReusableCellWithIdentifier:@"favorite"];
    if(!cell) {
        cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"favorite"]; [[TKTheme shared] styleCell:cell];
        TKImageView *image=[[TKImageView alloc] initWithFrame:CGRectMake(10,8,50,50)]; image.tag=77; image.contentMode=UIViewContentModeScaleAspectFill; image.clipsToBounds=YES; image.layer.cornerRadius=7; [cell.contentView addSubview:image]; cell.indentationLevel=4; cell.indentationWidth=16;
    }
    NSDictionary *d=self.items[(NSUInteger)ip.row]; BOOL sound=[self.kind isEqual:@"sounds"];
    [(TKImageView *)[cell viewWithTag:77] setImageURL:TKStr(d[sound ? @"cover" : @"avatar"]) placeholder:nil];
    cell.textLabel.text=sound ? (TKStr(d[@"name"]).length ? d[@"name"] : L(@"Sound")) : [@"@" stringByAppendingString:TKStr(d[@"handle"]) ?: @""];
    cell.detailTextLabel.text=sound ? TKStr(d[@"author"]) : TKStr(d[@"name"]); cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator; return cell;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip
{
    [t deselectRowAtIndexPath:ip animated:YES]; [self.searchBar resignFirstResponder]; NSDictionary *d=self.items[(NSUInteger)ip.row];
    if([self.kind isEqual:@"sounds"]) [TKLinkRouter openSound:d[@"id"] title:d[@"name"]]; else [TKLinkRouter openProfile:d[@"handle"]];
}
- (NSString *)tableView:(UITableView *)t titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)ip { return [self.kind isEqual:@"blocked"] ? L(@"Unhide") : L(@"Remove"); }
- (void)tableView:(UITableView *)t commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)ip
{
    if(style!=UITableViewCellEditingStyleDelete)return; NSDictionary *d=self.items[(NSUInteger)ip.row];
    if([self.kind isEqual:@"blocked"]) [TKSettings setCreator:d[@"handle"] blocked:NO];
    else if([self.kind isEqual:@"sounds"]) [TKSettings removeFavoriteSound:d[@"id"]];
    else [TKSettings removeFavoriteCreator:d[@"handle"]];
}
- (BOOL)shouldAutorotate { return YES; }
- (NSUInteger)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAll; }
@end
