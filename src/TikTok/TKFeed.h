#import <Foundation/Foundation.h>
#import "TKModels.h"
#import "TKFeedSource.h"

// Our own "For You". Candidates come from TikTok's logged-out Explore feed - a fresh batch per topic, so the supply
// never runs out (videos in languages the viewer turned off are left out). Which topics to ask
// for is drawn from what you liked (TKTaste); each next video is the best-scoring candidate with some randomness,
// a share of pure exploration (large at first, never zero), and rules that keep the feed varied: not the same
// creator twice within a few videos, rarely the same topic three times running.
@interface TKFeed : NSObject <TKFeedSource>

@property (nonatomic, readonly) NSArray *videos;     // TKVideo, in feed order
@property (nonatomic, readonly) BOOL loading;

// A fresh start (the first batches); `videos` changes only when it completes
- (void)reloadWithCompletion:(void (^)(NSError *error))completion;
// Makes sure there are items at least `count` past `index`, fetching more candidates when needed
- (void)ensureAhead:(NSInteger)index by:(NSInteger)count completion:(void (^)(BOOL added))completion;

// What the viewer did: the lessons the taste learns from
// passive: the video ended and the feed moved on by itself - finishing it then says less than swiping on after it
- (void)noteWatched:(TKVideo *)video seconds:(NSTimeInterval)watched duration:(NSTimeInterval)duration passive:(BOOL)passive;
- (void)noteSaved:(TKVideo *)video;
- (void)noteNotInterested:(TKVideo *)video;
- (void)noteEngaged:(TKVideo *)video weight:(double)weight;          // comments opened, link copied

@end
