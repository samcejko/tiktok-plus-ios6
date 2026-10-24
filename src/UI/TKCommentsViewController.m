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
@end

@implementation TKCommentsViewController

- (instancetype)initWithVideo:(TKVideo *)video
{
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        _video = video;
        _replies = [NSMutableDictionary dictionary];
        _loadingReplies = [NSMutableSet set];
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

- (void)dealloc { [self.task cancel]; }

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
    self.comments = nil;
    self.loading = YES;
    self.status = self.video ? L(@"Loading comments…") : @"";
    [self rebuildRows];
    if (!self.video.videoId.length) return;
    TKVideo *forVideo = self.video;
    self.task = [TKTikTok commentsForVideo:self.video.videoId count:50 completion:^(NSArray *comments, NSError *error) {
        if (forVideo != self.video) return;      // (switched to another video meanwhile)
        self.loading = NO;
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
    TKVideo *forVideo = self.video;
    [TKTikTok repliesForVideo:self.video.videoId comment:comment.commentId count:20 completion:^(NSArray *replies, NSError *error) {
        if (forVideo != self.video) return;
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
        [TKActionSheet options:@[L(@"Read full comment"),L(@"Copy comment")] title:L(@"Comment") inView:self.view selection:^(NSInteger i){
            if(i==0)[TKUtils alertWithTitle:[self nameOf:comment] message:comment.text];
            else [UIPasteboard generalPasteboard].string=comment.text;
        }];
    }
}

- (void)openAuthor:(UIButton *)sender
{
    if (sender.tag < 0 || sender.tag >= (NSInteger)self.rows.count) return;
    id row = self.rows[(NSUInteger)sender.tag];
    if ([row isKindOfClass:[TKComment class]] && [(TKComment *)row author].length) [TKLinkRouter openProfile:[(TKComment *)row author]];
}

- (void)postCommentPrompt
{
    if (![TKSettings allowAccountWrites]) {
        [TKUtils alertWithTitle:L(@"Actions disabled") message:L(@"Enable 'Allow actions on account' in Settings to post comments.")];
        return;
    }
    UIAlertView *a = [[UIAlertView alloc] initWithTitle:L(@"Add comment")
                                                message:[NSString stringWithFormat:L(@"Posting as @%@"), [TKSession sharedSession].handle ?: @""]
                                               delegate:self
                                      cancelButtonTitle:L(@"Cancel")
                                      otherButtonTitles:L(@"Post"), nil];
    a.alertViewStyle = UIAlertViewStylePlainTextInput;
    a.tag = 101;
    [a show];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (alertView.tag == 101) {
        if (buttonIndex == alertView.cancelButtonIndex) return;
        NSString *text = [alertView textFieldAtIndex:0].text;
        if (!text.length) return;
        [TKTikTok postCommentOnVideoId:self.video.videoId text:text completion:^(BOOL ok, NSDictionary *comment, NSError *error) {
            if (ok) {
                [self load];
            } else {
                [TKUtils alertWithTitle:L(@"Failed") message:error.localizedDescription ?: L(@"Could not post comment.")];
            }
        }];
    }
}

@end
