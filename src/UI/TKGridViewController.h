#import <UIKit/UIKit.h>

@class TKHTTPTask;

// What every page header stands on (iOS 6): a shaded, finely grained surface with an etched line along the bottom.
// Subclasses add their content in front.
@interface TKPageHeaderView : UIView
@end

// An avatar or a cover in a white frame with a soft shadow under it (round, or with rounded corners)
@interface TKFramedImageView : UIView
@property (nonatomic, strong, readonly) id imageView;     // a TKImageView
- (instancetype)initWithSize:(CGFloat)size round:(BOOL)round;
@end

// A page with a header over a grid of videos (a creator, a hashtag, a sound, search results). It asks for the next
// page as the end of the grid comes near; a tapped video plays full screen with the rest of the list after it, and
// that list grows from the same source.
@interface TKGridViewController : UIViewController <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>

@property (nonatomic, strong, readonly) UICollectionView *grid;
@property (nonatomic, strong, readonly) NSMutableArray *videos;       // TKVideo
@property (nonatomic, readonly) BOOL loading;

- (void)reload;                       // from the first page
- (void)loadMore;                     // the next page (when there is one and nothing is loading)

// For subclasses
// One page (more = NO: the first). The completion gets the page's videos, whether more follow, or an error.
- (TKHTTPTask *)fetchPageAfterFirst:(BOOL)more completion:(void (^)(NSArray *videos, BOOL hasMore, NSError *error))completion;
- (UIView *)headerView;                       // built once by the subclass; nil = none
- (CGFloat)headerHeightForWidth:(CGFloat)width;
- (void)headerChanged;                        // the header's content (and so its height) changed
- (NSString *)emptyMessage;                   // when the first page has nothing
- (NSString *)feedTitle;                      // over the videos opened from the grid
@end
