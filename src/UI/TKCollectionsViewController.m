#import "TKAlertView.h"
#import "TKCollectionsViewController.h"
#import "TKSavedViewController.h"
#import "TKSettings.h"
#import "TKActionSheet.h"
#import "TKTheme.h"
#import "TKUtils.h"
#import "TKCommon.h"
#import <objc/runtime.h>

@interface TKCollectionPicker () <UIAlertViewDelegate>
@property (nonatomic, strong) NSDictionary *video;
@property (nonatomic, copy) void (^completion)(BOOL);
@end
@implementation TKCollectionPicker
+ (void)addVideo:(NSDictionary *)video inView:(UIView *)view completion:(void (^)(BOOL))completion
{
    TKCollectionPicker *picker=[[self alloc] init]; picker.video=video; picker.completion=completion;
    NSArray *collections=[TKSettings collections]; NSMutableArray *titles=[NSMutableArray array];
    for(NSDictionary *c in collections)[titles addObject:c[@"name"]]; [titles addObject:L(@"New collection")];
    [TKActionSheet options:titles title:L(@"Add to collection") inView:view selection:^(NSInteger i){
        if(i<(NSInteger)collections.count) { [TKSettings addVideo:video toCollection:collections[(NSUInteger)i][@"id"]]; if(completion)completion(YES); }
        else {
            UIAlertView *a=[[TKAlertView alloc] initWithTitle:L(@"New collection") message:L(@"Choose a unique name (up to 60 characters).") delegate:picker cancelButtonTitle:L(@"Cancel") otherButtonTitles:L(@"Save"),nil];
            a.alertViewStyle=UIAlertViewStylePlainTextInput;
            objc_setAssociatedObject(a,@selector(addVideo:inView:completion:),picker,OBJC_ASSOCIATION_RETAIN_NONATOMIC); [a show];
        }
    }];
}
- (void)alertView:(UIAlertView *)alert clickedButtonAtIndex:(NSInteger)index
{
    if(index==alert.cancelButtonIndex) { if(self.completion)self.completion(NO); return; }
    NSString *cid=[TKSettings createCollection:[alert textFieldAtIndex:0].text];
    if(cid) [TKSettings addVideo:self.video toCollection:cid];
    else [TKUtils alertWithTitle:L(@"Collection not saved") message:L(@"Use a unique, nonempty name of at most 60 characters. Up to 100 collections are supported.")];
    if(self.completion)self.completion(cid!=nil); self.completion=nil;
}
@end

@interface TKCollectionsViewController () <UIAlertViewDelegate>
@property (nonatomic, strong) NSArray *items;
@property (nonatomic, copy) NSString *editingId;
@end
@implementation TKCollectionsViewController
- (void)viewDidLoad
{
    [super viewDidLoad]; self.title=L(@"Collections"); [[TKTheme shared] applyToTableView:self.tableView];
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(done)];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(add)];
    [self.tableView addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(held:)]];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reload) name:TKLibraryDidChangeNotification object:nil]; [self reload];
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
- (void)done { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)reload { self.items=[TKSettings collections]; [self.tableView reloadData]; }
- (void)add { self.editingId=nil; [self prompt:nil]; }
- (void)prompt:(NSString *)name
{
    UIAlertView *a=[[TKAlertView alloc] initWithTitle:self.editingId ? L(@"Rename collection") : L(@"New collection") message:L(@"Choose a unique name (up to 60 characters).") delegate:self cancelButtonTitle:L(@"Cancel") otherButtonTitles:L(@"Save"),nil];
    a.alertViewStyle=UIAlertViewStylePlainTextInput; [a textFieldAtIndex:0].text=name ?: @""; [a show];
}
- (void)alertView:(UIAlertView *)a clickedButtonAtIndex:(NSInteger)i
{
    if(i==a.cancelButtonIndex)return;
    if(a.tag==2) { [TKSettings deleteCollection:self.editingId]; self.editingId=nil; return; }
    BOOL ok=self.editingId ? [TKSettings renameCollection:self.editingId name:[a textFieldAtIndex:0].text] : [TKSettings createCollection:[a textFieldAtIndex:0].text]!=nil;
    if(!ok)[TKUtils alertWithTitle:L(@"Collection not saved") message:L(@"Use a unique, nonempty name of at most 60 characters. Up to 100 collections are supported.")]; self.editingId=nil;
}
- (void)held:(UILongPressGestureRecognizer *)g
{
    if(g.state!=UIGestureRecognizerStateBegan)return;
    NSIndexPath *ip=[self.tableView indexPathForRowAtPoint:[g locationInView:self.tableView]]; if(!ip)return;
    [self showActionsForRow:(NSUInteger)ip.row];
}
- (void)showActionsForRow:(NSUInteger)row
{
    if(row>=self.items.count)return;
    NSDictionary *c=self.items[row];
    [TKActionSheet options:@[L(@"Rename"),L(@"Delete collection")] title:c[@"name"] inView:self.view selection:^(NSInteger i){
        self.editingId=c[@"id"];
        if(i==0)[self prompt:c[@"name"]];
        else { UIAlertView *a=[[TKAlertView alloc] initWithTitle:L(@"Delete collection") message:L(@"The saved videos will be kept.") delegate:self cancelButtonTitle:L(@"Cancel") otherButtonTitles:L(@"Delete"),nil]; a.tag=2; [a show]; }
    }];
}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return self.items.count; }
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s { return L(@"Hold to rename or delete."); }
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip
{
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil]; [[TKTheme shared] styleCell:cell];
    NSDictionary *c=self.items[(NSUInteger)ip.row]; cell.textLabel.text=c[@"name"]; cell.detailTextLabel.text=[NSString stringWithFormat:@"%lu",(unsigned long)[TKSettings videosInCollection:c[@"id"]].count]; cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator; return cell;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip
{
    [t deselectRowAtIndexPath:ip animated:YES]; NSDictionary *c=self.items[(NSUInteger)ip.row];
    [self.navigationController pushViewController:[[TKSavedViewController alloc] initWithCollection:c[@"id"] title:c[@"name"]] animated:YES];
}
- (BOOL)shouldAutorotate { return YES; }
- (NSUInteger)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAll; }
@end
