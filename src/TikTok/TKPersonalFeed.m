#import "TKPersonalFeed.h"
#import "TKTikTok.h"
#import "TKFeed.h"
#import "TKCommon.h"

@interface TKPersonalFeed ()
@property (nonatomic, strong) NSMutableArray *mutableVideos;
@property (nonatomic, assign, readwrite) BOOL loading;
@property (nonatomic, strong) TKFeed *fallbackFeed;
@end

@implementation TKPersonalFeed

- (instancetype)init
{
    return [self initWithFollowingMode:NO];
}

- (instancetype)initWithFollowingMode:(BOOL)followingMode
{
    self = [super init];
    if (self) {
        _isFollowingMode = followingMode;
        _mutableVideos = [NSMutableArray array];
        _fallbackFeed = [[TKFeed alloc] init];
    }
    return self;
}

- (NSArray *)videos
{
    return [self.mutableVideos copy];
}

- (void)reloadWithCompletion:(void (^)(NSError *error))completion
{
    self.loading = YES;
    void (^handleVideos)(NSArray *, NSError *) = ^(NSArray *videos, NSError *error) {
        self.loading = NO;
        if (videos.count > 0) {
            [self.mutableVideos removeAllObjects];
            [self.mutableVideos addObjectsFromArray:videos];
            if (completion) completion(nil);
        } else {
            [self.mutableVideos removeAllObjects];
            if (completion) completion(error);
        }
    };

    if (self.isFollowingMode) {
        [TKTikTok followingFeedWithCount:20 completion:handleVideos];
    } else {
        [TKTikTok personalFeedWithCount:20 completion:handleVideos];
    }
}

- (void)ensureAhead:(NSInteger)index by:(NSInteger)count completion:(void (^)(BOOL added))completion
{
    if (self.loading || (index + count < (NSInteger)self.mutableVideos.count)) {
        if (completion) completion(NO);
        return;
    }

    self.loading = YES;
    void (^handleMore)(NSArray *, NSError *) = ^(NSArray *videos, NSError *error) {
        self.loading = NO;
        if (videos.count > 0) {
            NSMutableSet *existingIds = [NSMutableSet set];
            for (TKVideo *v in self.mutableVideos) {
                if (v.videoId) [existingIds addObject:v.videoId];
            }
            BOOL addedAny = NO;
            for (TKVideo *v in videos) {
                if (v.videoId && ![existingIds containsObject:v.videoId]) {
                    [self.mutableVideos addObject:v];
                    [existingIds addObject:v.videoId];
                    addedAny = YES;
                }
            }
            if (completion) completion(addedAny);
        } else {
            if (completion) completion(NO);
        }
    };

    if (self.isFollowingMode) {
        [TKTikTok followingFeedWithCount:20 completion:handleMore];
    } else {
        [TKTikTok personalFeedWithCount:20 completion:handleMore];
    }
}

- (void)noteWatched:(TKVideo *)video seconds:(NSTimeInterval)watched duration:(NSTimeInterval)duration passive:(BOOL)passive
{
    [self.fallbackFeed noteWatched:video seconds:watched duration:duration passive:passive];
}

- (void)noteSaved:(TKVideo *)video
{
    [self.fallbackFeed noteSaved:video];
}

- (void)noteNotInterested:(TKVideo *)video
{
    [self.fallbackFeed noteNotInterested:video];
}

- (void)noteEngaged:(TKVideo *)video weight:(double)weight
{
    [self.fallbackFeed noteEngaged:video weight:weight];
}

@end
