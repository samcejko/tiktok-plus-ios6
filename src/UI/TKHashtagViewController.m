#import "TKHashtagViewController.h"
#import "TKLinkLabel.h"
#import "TKTikTok.h"
#import "TKModels.h"
#import "TKTheme.h"
#import "TKUtils.h"
#import "TKCommon.h"

static const CGFloat TKTagTileSize = 84;

// iOS 6: a glossy tile with the # pressed into it, on the grained surface of the pages
@interface TKHashtagHeaderView : TKPageHeaderView
@property (nonatomic, strong) UIImageView *tile;
@property (nonatomic, strong) UILabel *hashLabel;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *countsLabel;
@property (nonatomic, strong) TKLinkLabel *descLabel;      // (the web links in the description open on a tap)
- (void)showHashtag:(TKHashtag *)tag;
- (CGFloat)layoutForWidth:(CGFloat)width apply:(BOOL)apply;
@end

@implementation TKHashtagHeaderView

- (instancetype)initWithFrame:(CGRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        TKTheme *theme = [TKTheme shared];
        _tile = [[UIImageView alloc] initWithImage:[theme pillImageWithColor:[theme accentColor]]];
        _tile.frame = CGRectMake(0, 0, TKTagTileSize, TKTagTileSize);
        _tile.layer.shadowColor = [UIColor blackColor].CGColor;
        _tile.layer.shadowOpacity = 0.5;
        _tile.layer.shadowRadius = 3;
        _tile.layer.shadowOffset = CGSizeMake(0, 2);
        [self addSubview:_tile];
        _hashLabel = [[UILabel alloc] initWithFrame:_tile.bounds];
        _hashLabel.text = @"#";
        _hashLabel.font = [UIFont boldSystemFontOfSize:52];
        _hashLabel.textColor = [UIColor whiteColor];
        _hashLabel.textAlignment = NSTextAlignmentCenter;
        _hashLabel.backgroundColor = [UIColor clearColor];
        _hashLabel.shadowColor = [UIColor colorWithRed:0.35 green:0 blue:0.08 alpha:0.7];
        _hashLabel.shadowOffset = CGSizeMake(0, -1);
        [_tile addSubview:_hashLabel];
        _nameLabel = [self label:[UIFont boldSystemFontOfSize:21] color:[theme embossTextColor]];
        _countsLabel = [self label:[UIFont systemFontOfSize:14] color:[theme secondaryTextColor]];
        _descLabel = [[TKLinkLabel alloc] initWithFrame:CGRectZero];
        _descLabel.font = [UIFont systemFontOfSize:14];
        _descLabel.textColor = [theme embossTextColor];
        _descLabel.backgroundColor = [UIColor clearColor];
        _descLabel.numberOfLines = 4;
        [theme embossLabel:_descLabel];
        [self addSubview:_descLabel];
    }
    return self;
}

- (UILabel *)label:(UIFont *)font color:(UIColor *)color
{
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectZero];
    l.font = font;
    l.textColor = color;
    l.backgroundColor = [UIColor clearColor];
    [[TKTheme shared] embossLabel:l];
    [self addSubview:l];
    return l;
}

- (void)showHashtag:(TKHashtag *)tag
{
    self.nameLabel.text = [@"#" stringByAppendingString:tag.name ?: @""];
    NSMutableArray *parts = [NSMutableArray array];
    if (tag.videoCount) [parts addObject:[NSString stringWithFormat:L(@"%@ videos"), [TKUtils formatBigCount:tag.videoCount]]];
    if (tag.viewCount) [parts addObject:[NSString stringWithFormat:L(@"%@ views"), [TKUtils formatBigCount:tag.viewCount]]];
    self.countsLabel.text = [parts componentsJoinedByString:@"  ·  "];
    self.descLabel.text = tag.desc.length ? [TKUtils displayText:tag.desc] : @"";
    [self setNeedsLayout];
}

- (CGFloat)layoutForWidth:(CGFloat)w apply:(BOOL)apply
{
    CGFloat x = 18 + TKTagTileSize + 16, textW = w - x - 16, y = 20;
    if (apply) {
        self.tile.frame = CGRectMake(18, y, TKTagTileSize, TKTagTileSize);
        self.nameLabel.frame = CGRectMake(x, y + 14, textW, 26);
        self.countsLabel.frame = CGRectMake(x, y + 44, textW, 20);
    }
    y += TKTagTileSize + 16;
    if (self.descLabel.text.length) {
        CGSize s = [self.descLabel.text sizeWithFont:self.descLabel.font constrainedToSize:CGSizeMake(w - 36, 4 * 18) lineBreakMode:NSLineBreakByWordWrapping];
        if (apply) self.descLabel.frame = CGRectMake(18, y, w - 36, ceilf(s.height));
        y += ceilf(s.height) + 14;
    }
    return y + 2;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    [self layoutForWidth:self.bounds.size.width apply:YES];
}

@end

@interface TKHashtagViewController ()
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) TKHashtag *hashtag;
@property (nonatomic, strong) TKHashtagHeaderView *header;
@property (nonatomic) long long cursor;
@end

@implementation TKHashtagViewController

- (instancetype)initWithName:(NSString *)name
{
    if ((self = [super initWithNibName:nil bundle:nil])) _name = [name copy] ?: @"";
    return self;
}

- (void)viewDidLoad
{
    self.title = [@"#" stringByAppendingString:self.name];
    [super viewDidLoad];
}

- (TKHTTPTask *)fetchPageAfterFirst:(BOOL)more completion:(void (^)(NSArray *, BOOL, NSError *))completion
{
    return [TKTikTok hashtag:self.name cursor:more ? self.cursor : 0 completion:^(TKVideoPage *page, NSError *error) {
        if (!page) { completion(nil, NO, error); return; }
        if (!more) {
            self.hashtag = page.hashtag;
            if (page.hashtag) [self.header showHashtag:page.hashtag];
        }
        self.cursor = page.cursor;
        completion(page.videos, page.hasMore, nil);
    }];
}

- (UIView *)headerView
{
    if (!self.hashtag) return nil;
    if (!self.header) {
        self.header = [[TKHashtagHeaderView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 140)];
        [self.header showHashtag:self.hashtag];
    }
    return self.header;
}

- (CGFloat)headerHeightForWidth:(CGFloat)width { return [(TKHashtagHeaderView *)[self headerView] layoutForWidth:width apply:NO]; }
- (NSString *)emptyMessage { return self.hashtag ? L(@"No videos to show.") : L(@"This hashtag was not found."); }
- (NSString *)feedTitle { return [@"#" stringByAppendingString:self.name]; }

@end
