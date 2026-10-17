#import <Foundation/Foundation.h>
#import "TKModels.h"

@protocol TKFeedSource <NSObject>

@property (nonatomic, readonly) NSArray *videos;     // TKVideo, in feed order
@property (nonatomic, readonly) BOOL loading;

- (void)reloadWithCompletion:(void (^)(NSError *error))completion;
- (void)ensureAhead:(NSInteger)index by:(NSInteger)count completion:(void (^)(BOOL added))completion;

@optional
- (void)noteWatched:(TKVideo *)video seconds:(NSTimeInterval)watched duration:(NSTimeInterval)duration passive:(BOOL)passive;
- (void)noteSaved:(TKVideo *)video;
- (void)noteNotInterested:(TKVideo *)video;
- (void)noteEngaged:(TKVideo *)video weight:(double)weight;

@end
