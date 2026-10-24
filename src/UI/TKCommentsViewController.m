#import "TKAlertView.h"
#import "TKCommentsViewController.h"
#import "TKLinkRouter.h"
#import "TKLinkLabel.h"
#import "TKTikTok.h"
#import "TKSession.h"
#import "TKSettings.h"
#import "TKHTTP.h"
#import "TKModels.h"
#import "TKImageLoader.h"
#import "TKTheme.h"
#import "TKUtils.h"
#import "TKCommon.h"
#import "TKActionSheet.h"

// A comment shows at most this many lines (some are walls of emoji that would fill the whole sheet)
static const NSInteger TKCommentMaxLines = 8;
static const CGFloat TKReplyIndent = 30;
static const CGFloat TKAvatarLeft = 12;
static const CGFloat TKTextLeft = 54;          // the text column (a reply: + TKReplyIndent)
static const CGFloat TKLikesWidth = 46;        // the heart column on the right

// Rows are measured with a label set up exactly like the cell's, so the height matches what gets drawn
// (emoji lines are taller than the body font's).
static UILabel *TKCommentSizingLabel(void)
{
    static UILabel *label;
    if (!label) {
        label = [[UILabel alloc] initWithFrame:CGRectZero];
        label.numberOfLines = TKCommentMaxLines;
        label.lineBreakMode = NSLineBreakByTruncatingTail;
    }
    return label;
}

#pragma mark - Cell

@interface TKCommentCell : UITableViewCell
@property (nonatomic, strong) TKImageView *avatar;
@property (nonatomic, strong) UIButton *avatarButton;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UIButton *nameButton;
@property (nonatomic, strong) TKLinkLabel *bodyLabel;     // (its web links open on a tap)
@property (nonatomic, strong) UILabel *metaLabel;
@property (nonatomic, strong) UILabel *heartLabel;
@property (nonatomic, strong) UIButton *heartButton;
@property (nonatomic, strong) UILabel *likesLabel;
@property (nonatomic) BOOL reply;
@end

@implementation TKCommentCell

- (UILabel *)label:(UIFont *)font color:(UIColor *)color
{
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectZero];
    l.font = font;
    l.textColor = color;
    l.backgroundColor = [UIColor clearColor];
    [self.contentView addSubview:l];
    return l;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        TKTheme *theme = [TKTheme shared];
        [theme styleCell:self];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        _avatar = [[TKImageView alloc] initWithFrame:CGRectZero];
        _avatar.contentMode = UIViewContentModeScaleAspectFill;
        _avatar.clipsToBounds = YES;
        _avatar.maxPixels = 96;
        _avatar.backgroundColor = [UIColor colorWithWhite:0.3 alpha:1];
        [self.contentView addSubview:_avatar];
        _nameLabel = [self label:[UIFont boldSystemFontOfSize:12] color:[theme secondaryTextColor]];
        _bodyLabel = [[TKLinkLabel alloc] initWithFrame:CGRectZero];
        _bodyLabel.font = [theme bodyFont];
        _bodyLabel.textColor = [theme primaryTextColor];
        _bodyLabel.backgroundColor = [UIColor clearColor];
        _bodyLabel.numberOfLines = TKCommentMaxLines;
        _bodyLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self.contentView addSubview:_bodyLabel];
        _metaLabel = [self label:[UIFont systemFontOfSize:11] color:[theme secondaryTextColor]];
        _heartLabel = [self label:[UIFont systemFontOfSize:15] color:[theme secondaryTextColor]];
        _heartButton=[UIButton buttonWithType:UIButtonTypeCustom];
        [self.contentView addSubview:_heartButton];
        _heartLabel.text = @"♥";
        _heartLabel.textAlignment = NSTextAlignmentCenter;
        _likesLabel = [self label:[UIFont systemFontOfSize:11] color:[theme secondaryTextColor]];
        _likesLabel.textAlignment = NSTextAlignmentCenter;
        _avatarButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _nameButton = [UIButton buttonWithType:UIButtonTypeCustom];
        [self.contentView addSubview:_avatarButton];
        [self.contentView addSubview:_nameButton];
    }
    return self;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width, indent = self.reply ? TKReplyIndent : 0;
    CGFloat side = self.reply ? 24 : 34;
    self.avatar.frame = CGRectMake(TKAvatarLeft + indent, 10, side, side);
    self.avatar.layer.cornerRadius = side / 2;
    self.avatarButton.frame = CGRectInset(self.avatar.frame, -6, -6);
    CGFloat x = TKTextLeft + indent - (self.reply ? 8 : 0), textW = w - x - TKLikesWidth;
    self.nameLabel.frame = CGRectMake(x, 8, textW, 16);
    CGSize nameSize = [self.nameLabel.text ?: @"" sizeWithFont:self.nameLabel.font];
    self.nameButton.frame = CGRectMake(x - 4, 2, MIN(textW, ceilf(nameSize.width)) + 8, 26);
    CGSize s = [self.bodyLabel sizeThatFits:CGSizeMake(textW, CGFLOAT_MAX)];
    self.bodyLabel.frame = CGRectMake(x, 25, textW, ceilf(s.height));
    self.metaLabel.frame = CGRectMake(x, CGRectGetMaxY(self.bodyLabel.frame) + 3, textW, 14);
    self.heartLabel.frame = CGRectMake(w - TKLikesWidth, 12, TKLikesWidth, 18);
    self.likesLabel.frame = CGRectMake(w - TKLikesWidth, 30, TKLikesWidth, 14);
    self.heartButton.frame=CGRectMake(w-TKLikesWidth,4,TKLikesWidth,44);
    [self.contentView bringSubviewToFront:self.heartButton];
}

@end

#pragma mark - Controller

@interface TKCommentsViewController () <UIAlertViewDelegate>
@property (nonatomic, strong) TKVideo *video;
@property (nonatomic) BOOL panel;
@property (nonatomic) BOOL inSheet;
@property (nonatomic, strong) NSArray *comments;               // top level
@property (nonatomic, strong) NSMutableDictionary *replies;    // comment id -> NSArray of replies
@property (nonatomic, strong) NSMutableSet *loadingReplies;    // comment ids
@property (nonatomic, strong) NSArray *rows;                   // TKComment, or @{ "more": TKComment }, or @{ "action": "comment" }
@property (nonatomic) BOOL loading;
@property (nonatomic, copy) NSString *status;
@property (nonatomic, strong) TKHTTPTask *task;
@property (nonatomic, strong) NSMutableDictionary *drafts;
@property (nonatomic, strong) NSMutableSet *pendingActions;
@property (nonatomic, strong) TKComment *replyTarget;
@property (nonatomic, strong) TKVideo *composeVideo;
@property (nonatomic, copy) NSString *composeToken;
@property (nonatomic, copy) NSString *draftKey;
@property (nonatomic, weak) UIAlertView *composeAlert;
@property (nonatomic) BOOL sending;
@property (nonatomic) NSUInteger generation;

@end

@implementation TKCommentsViewController

- (instancetype)initWithVideo:(TKVideo *)video
{
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        _video = video;
        _replies = [NSMutableDictionary dictionary];
        _loadingReplies = [NSMutableSet set]; _drafts=[NSMutableDictionary dictionary]; _pendingActions=[NSMutableSet set];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(accountChanged) name:TKSessionDidChangeNotification object:nil];
    }
    return self;
}

- (instancetype)initForBottomSheetWithVideo:(TKVideo *)video
{
    if ((self = [self initWithVideo:video])) _inSheet = YES;
    return self;
}

- (instancetype)initAsPanel
{
    if ((self = [self initWithVideo:nil])) _panel = YES;
    return self;
}

- (void)dealloc { [self.task cancel]; [[NSNotificationCenter defaultCenter] removeObserver:self]; }
- (void)accountChanged
{
    [self.drafts removeAllObjects]; self.replyTarget=nil;
    [self.composeAlert dismissWithClickedButtonIndex:self.composeAlert.cancelButtonIndex animated:NO];
    if(self.isViewLoaded)[self load];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = L(@"Comments");
    [[TKTheme shared] applyToTableView:self.tableView];
    if (!self.panel && !self.inSheet) {
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(done)];
        if ([TKSession sharedSession].signedIn && [TKSettings allowAccountWrites]) {
            self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:L(@"Comment") style:UIBarButtonItemStylePlain target:self action:@selector(postCommentPrompt)];
        }
    }
    self.refreshControl=[[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self action:@selector(load) forControlEvents:UIControlEventValueChanged];
    [self load];
}

- (void)done { [self dismissViewControllerAnimated:YES completion:nil]; }

- (BOOL)shouldAutorotate { return YES; }
- (NSUInteger)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAll; }

- (void)showVideo:(TKVideo *)video
{
    if (video == self.video || [video.videoId isEqualToString:self.video.videoId]) return;
    self.video = video;
    [self.replies removeAllObjects];
    [self.loadingReplies removeAllObjects];
    if (self.isViewLoaded) [self load];
}

- (void)load
{
    [self.task cancel];
    NSUInteger generation=++self.generation;
    self.comments = nil; [self.replies removeAllObjects]; [self.loadingReplies removeAllObjects];
    self.loading = YES;
    self.status = self.video ? L(@"Loading comments…") : @"";
    [self rebuildRows];
    if (!self.video.videoId.length) { self.loading=NO; [self.refreshControl endRefreshing]; return; }
    TKVideo *forVideo = self.video;
    self.task = [TKTikTok commentsForVideo:self.video.videoId count:50 completion:^(NSArray *comments, NSError *error) {
        if (forVideo != self.video || generation!=self.generation) return;
        self.loading = NO; [self.refreshControl endRefreshing];
        self.comments = comments;
        if (error) self.status = error.localizedDescription;
        else if (!comments.count) self.status = L(@"No comments to show.");
        [self rebuildRows];
    }];
    [self.tableView setContentOffset:CGPointZero animated:NO];
}

- (void)rebuildRows
{
    NSMutableArray *rows = [NSMutableArray array];
    if ([TKSession sharedSession].signedIn && [TKSettings allowAccountWrites] && self.video.videoId.length) {
        [rows addObject:@{ @"action": @"comment" }];
    }
    for (TKComment *c in self.comments) {
        [rows addObject:c];
        if (c.replyCount <= 0 || !c.commentId.length) continue;
        NSArray *replies = self.replies[c.commentId];
        if (replies.count) [rows addObjectsFromArray:replies];
        else if (!replies) [rows addObject:@{ @"more": c }];
    }
    self.rows = rows;
    [self.tableView reloadData];
}

- (void)loadRepliesOf:(TKComment *)comment
{
    if (!comment.commentId.length || [self.loadingReplies containsObject:comment.commentId]) return;
    [self.loadingReplies addObject:comment.commentId];
    [self.tableView reloadData];
    TKVideo *forVideo = self.video; NSUInteger generation=self.generation;
    [TKTikTok repliesForVideo:self.video.videoId comment:comment.commentId count:20 completion:^(NSArray *replies, NSError *error) {
        if (forVideo != self.video || generation!=self.generation) return;
        [self.loadingReplies removeObject:comment.commentId];
        if (replies) self.replies[comment.commentId] = replies;   // (an empty list: the row goes away)
        [self rebuildRows];
    }];
}

// "@handle" when that is all there is, else the name they chose
- (NSString *)nameOf:(TKComment *)c
{
    NSString *name = c.authorName.length ? [TKUtils displayText:c.authorName] : @"";
    return name.length ? name : [@"@" stringByAppendingString:c.author ?: @""];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return self.rows.count ? (NSInteger)self.rows.count : 1; }

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip
{
    if (!self.rows.count || [self.rows[(NSUInteger)ip.row] isKindOfClass:[NSDictionary class]]) {
        if (self.rows.count) {
            NSDictionary *dict = self.rows[(NSUInteger)ip.row];
            if ([dict[@"action"] isEqualToString:@"comment"]) {
                UITableViewCell *actCell = [t dequeueReusableCellWithIdentifier:@"act"];
                if (!actCell) {
                    actCell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"act"];
                    [[TKTheme shared] styleCell:actCell];
                }
                actCell.textLabel.text = [NSString stringWithFormat:L(@"Add a comment as @%@…"), [TKSession sharedSession].handle ?: L(@"me")];
                actCell.textLabel.font = [[TKTheme shared] bodyFont];
                actCell.textLabel.textColor = [[TKTheme shared] secondaryTextColor];
                actCell.textLabel.textAlignment = NSTextAlignmentLeft;
                actCell.indentationLevel = 1;
                actCell.indentationWidth = 8;
                actCell.selectionStyle = UITableViewCellSelectionStyleGray;
                return actCell;
            }
        }
        UITableViewCell *cell = [t dequeueReusableCellWithIdentifier:@"note"];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"note"];
            [[TKTheme shared] styleCell:cell];
        }
        cell.indentationLevel = 0;
        if (!self.rows.count) {
            cell.textLabel.text = self.status;
            cell.textLabel.font = [[TKTheme shared] smallFont];
            cell.textLabel.textColor = [[TKTheme shared] secondaryTextColor];
            cell.textLabel.textAlignment = NSTextAlignmentCenter;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            return cell;
        }
        TKComment *parent = self.rows[(NSUInteger)ip.row][@"more"];
        BOOL busy = [self.loadingReplies containsObject:parent.commentId];
        cell.textLabel.text = busy ? L(@"Loading replies…") : [NSString stringWithFormat:@"— %@", [NSString stringWithFormat:L(@"View replies (%@)"), [TKUtils formatCount:parent.replyCount]]];
        cell.textLabel.font = [[TKTheme shared] tinyBoldFont];
        cell.textLabel.textColor = [[TKTheme shared] secondaryTextColor];
        cell.textLabel.textAlignment = NSTextAlignmentLeft;
        cell.indentationWidth = TKTextLeft - 10;
        cell.indentationLevel = 1;
        cell.selectionStyle = UITableViewCellSelectionStyleGray;
        return cell;
    }
    TKCommentCell *cell = [t dequeueReusableCellWithIdentifier:@"comment"];
    if (!cell) {
        cell = [[TKCommentCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"comment"];
        [cell.avatarButton addTarget:self action:@selector(openAuthor:) forControlEvents:UIControlEventTouchUpInside];
        [cell.nameButton addTarget:self action:@selector(openAuthor:) forControlEvents:UIControlEventTouchUpInside];
        [cell.heartButton addTarget:self action:@selector(likeCommentButton:) forControlEvents:UIControlEventTouchUpInside];
    }
    TKComment *c = self.rows[(NSUInteger)ip.row];
    cell.reply = c.isReply;
    [cell.avatar setImageURL:c.avatarURL placeholder:nil];
    NSMutableString *name = [[self nameOf:c] mutableCopy];
    if (c.author.length && [c.author caseInsensitiveCompare:self.video.author ?: @""] == NSOrderedSame) [name appendFormat:@"  ·  %@", L(@"Creator")];
    if (c.pinned) [name appendFormat:@"  ·  %@", L(@"Pinned")];
    cell.nameLabel.text = name;
    cell.bodyLabel.font = c.isReply ? [[TKTheme shared] smallFont] : [[TKTheme shared] bodyFont];   // (before the text: its links take the font)
    cell.bodyLabel.text = [TKUtils displayText:c.text];
    cell.metaLabel.text = c.createdAt > 0 ? [TKUtils formatRelativeDate:[NSDate dateWithTimeIntervalSince1970:c.createdAt]] : @"";
    cell.heartLabel.textColor=c.likeStateKnown && c.liked ? [UIColor colorWithRed:1 green:.2 blue:.3 alpha:1] : [[TKTheme shared] secondaryTextColor];
    cell.heartLabel.text=c.likeStateKnown && c.liked ? @"♥" : @"♡";
    cell.heartButton.tag=ip.row;
    cell.heartButton.accessibilityLabel=c.likeStateKnown && c.liked ? L(@"Unlike comment") : L(@"Like comment");
    cell.heartButton.enabled=![self.pendingActions containsObject:c.commentId];
    cell.likesLabel.text = c.likes ? [TKUtils formatCount:c.likes] : @"";
    cell.avatarButton.tag = ip.row;
    cell.nameButton.tag = ip.row;
    [cell setNeedsLayout];
    return cell;
}

- (CGFloat)tableView:(UITableView *)t heightForRowAtIndexPath:(NSIndexPath *)ip
{
    if (!self.rows.count) return 80;
    id row = self.rows[(NSUInteger)ip.row];
    if ([row isKindOfClass:[NSDictionary class]]) {
        if ([row[@"action"] isEqualToString:@"comment"]) return 44;
        return 34;
    }
    TKComment *c = row;
    UILabel *sizer = TKCommentSizingLabel();
    sizer.font = c.isReply ? [[TKTheme shared] smallFont] : [[TKTheme shared] bodyFont];
    sizer.text = [TKUtils displayText:c.text];
    CGFloat x = TKTextLeft + (c.isReply ? TKReplyIndent - 8 : 0);
    CGSize s = [sizer sizeThatFits:CGSizeMake(t.bounds.size.width - x - TKLikesWidth, CGFLOAT_MAX)];
    return MAX(c.isReply ? 48 : 58, 25 + ceilf(s.height) + 3 + 14 + 10);
}

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip
{
    [t deselectRowAtIndexPath:ip animated:YES];
    if (!self.rows.count) return;
    id row = self.rows[(NSUInteger)ip.row];
    if ([row isKindOfClass:[NSDictionary class]]) {
        if ([row[@"action"] isEqualToString:@"comment"]) {
            [self postCommentPrompt];
        } else {
            [self loadRepliesOf:row[@"more"]];
        }
    } else if([row isKindOfClass:[TKComment class]]) {
        TKComment *comment=row;
        NSMutableArray *options=[NSMutableArray arrayWithObjects:L(@"Read full comment"),L(@"Copy comment"),nil];
        BOOL signedIn=[TKSession sharedSession].signedIn;
        if(signedIn)[options addObject:L(@"Reply")];
        BOOL own=signedIn && [comment.userId isEqualToString:[TKSession sharedSession].userId];
        if(own)[options addObject:L(@"Delete comment")];
        [TKActionSheet options:options title:L(@"Comment") inView:self.view selection:^(NSInteger i){
            if(i==0)[TKUtils alertWithTitle:[self nameOf:comment] message:comment.text];
            else if(i==1)[UIPasteboard generalPasteboard].string=comment.text;
            else if(i==2 && signedIn) { self.replyTarget=comment; [self showComposer]; }
            else if(own) [self confirmDelete:comment];
        }];
    }
}

- (void)openAuthor:(UIButton *)sender
{
    if (sender.tag < 0 || sender.tag >= (NSInteger)self.rows.count) return;
    id row = self.rows[(NSUInteger)sender.tag];
    if ([row isKindOfClass:[TKComment class]] && [(TKComment *)row author].length) [TKLinkRouter openProfile:[(TKComment *)row author]];
}

- (void)likeCommentButton:(UIButton *)button
{
    if(button.tag<0 || button.tag>=(NSInteger)self.rows.count) return;
    id row=self.rows[(NSUInteger)button.tag]; if(![row isKindOfClass:[TKComment class]])return;
    TKComment *comment=row;
    if(![TKSession sharedSession].signedIn) { [TKUtils alertWithTitle:L(@"Sign in") message:L(@"Sign in to use TikTok account actions.")]; return; }
    if([self.pendingActions containsObject:comment.commentId])return;
    [self.pendingActions addObject:comment.commentId]; [self.tableView reloadData];
    BOOL on=!(comment.likeStateKnown && comment.liked); TKVideo *video=self.video; NSString *token=[TKSession sharedSession].token;
    [TKTikTok likeComment:comment videoId:video.videoId on:on completion:^(BOOL ok,NSError *error){
        [self.pendingActions removeObject:comment.commentId];
        if(![token isEqualToString:[TKSession sharedSession].token] || video!=self.video)return;
        if(ok) { if(comment.likeStateKnown && comment.liked!=on)comment.likes=MAX(0,comment.likes+(on?1:-1)); comment.likeStateKnown=YES; comment.liked=on; }
        else [TKUtils alertWithTitle:L(@"Action not confirmed") message:error.localizedDescription];
        [self.tableView reloadData];
    }];
}
- (void)confirmDelete:(TKComment *)comment
{
    if([self.pendingActions containsObject:comment.commentId])return;
    TKVideo *video=self.video; NSString *token=[TKSession sharedSession].token;
    [TKActionSheet options:@[L(@"Delete comment")] title:L(@"Delete your comment permanently?") inView:self.view selection:^(NSInteger i){
        if(![token isEqualToString:[TKSession sharedSession].token] || video!=self.video)return;
        [self.pendingActions addObject:comment.commentId];
        [TKTikTok deleteComment:comment completion:^(BOOL ok,NSError *error){
            [self.pendingActions removeObject:comment.commentId];
            if(![token isEqualToString:[TKSession sharedSession].token] || video!=self.video)return;
            if(ok) {
                NSMutableArray *top=[self.comments mutableCopy]; [top removeObject:comment]; self.comments=top;
                for(NSString *key in self.replies.allKeys) { NSMutableArray *r=[self.replies[key] mutableCopy]; if([r containsObject:comment]) { [r removeObject:comment]; self.replies[key]=r; for(TKComment *parent in self.comments)if([parent.commentId isEqualToString:key])parent.replyCount=MAX(0,parent.replyCount-1); } }
                [self.replies removeObjectForKey:comment.commentId]; self.video.commentCount=MAX(0,self.video.commentCount-1);
                if(!self.comments.count)self.status=L(@"No comments to show."); [self rebuildRows];
            } else [TKUtils alertWithTitle:L(@"Action not confirmed") message:error.localizedDescription];
        }];
    }];
}
- (void)postCommentPrompt { self.replyTarget=nil; [self showComposer]; }
- (void)showComposer
{
    if(self.sending || self.composeAlert.visible)return;
    if(![TKSession sharedSession].signedIn || !self.video.videoId.length)return;
    self.composeVideo=self.video; self.composeToken=[TKSession sharedSession].token;
    self.draftKey=[NSString stringWithFormat:@"%@:%@:%@",self.composeToken,self.video.videoId,self.replyTarget.commentId ?: @""];
    NSString *title=self.replyTarget ? L(@"Reply") : L(@"Add comment");
    NSString *message=[NSString stringWithFormat:L(@"Posting as @%@"),[TKSession sharedSession].handle ?: @""];
    if(self.replyTarget)message=[message stringByAppendingFormat:@"\n@%@",self.replyTarget.author ?: @""];
    UIAlertView *a=[[TKAlertView alloc] initWithTitle:title message:message delegate:self cancelButtonTitle:L(@"Cancel") otherButtonTitles:L(@"Post"),nil];
    a.alertViewStyle=UIAlertViewStylePlainTextInput; a.tag=101;
    [a textFieldAtIndex:0].text=self.drafts[self.draftKey] ?: @"";
    self.composeAlert=a; [a show];
}
- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if(alertView.tag!=101)return;
    NSString *text=[alertView textFieldAtIndex:0].text ?: @"";
    NSString *key=self.draftKey,*token=self.composeToken; TKVideo *video=self.composeVideo; TKComment *parent=self.replyTarget;
    if(![token isEqualToString:[TKSession sharedSession].token])return;
    self.drafts[key]=text;
    if(buttonIndex==alertView.cancelButtonIndex || !text.length)return;
    if(video!=self.video || self.sending)return;
    self.sending=YES;
    [TKTikTok postCommentOnVideoId:video.videoId text:text replyTo:parent completion:^(BOOL ok,NSDictionary *result,NSError *error){
        self.sending=NO;
        if(![token isEqualToString:[TKSession sharedSession].token])return;
        if(ok) [self.drafts removeObjectForKey:key];
        if(video!=self.video)return;
        if(ok) {
            [self.task cancel]; self.generation++; [self.loadingReplies removeAllObjects]; self.loading=NO; [self.refreshControl endRefreshing];
            TKComment *comment=[TKComment commentFromJSON:result];
            if(parent) { comment.isReply=YES; comment.parentCommentId=parent.parentCommentId ?: parent.commentId; TKComment *root=parent; for(TKComment *c in self.comments)if([c.commentId isEqualToString:comment.parentCommentId])root=c; NSMutableArray *r=[self.replies[comment.parentCommentId] mutableCopy] ?: [NSMutableArray array]; [r addObject:comment]; self.replies[comment.parentCommentId]=r; root.replyCount++; }
            else { NSMutableArray *top=[self.comments mutableCopy] ?: [NSMutableArray array]; [top insertObject:comment atIndex:0]; self.comments=top; }
            self.video.commentCount++; [self rebuildRows];
        } else [TKUtils alertWithTitle:L(@"Action not confirmed") message:[NSString stringWithFormat:@"%@\n\n%@",error.localizedDescription ?: L(@"Could not post comment."),L(@"Your draft is kept. Refresh comments before sending it again.")]];
    }];
}
@end
