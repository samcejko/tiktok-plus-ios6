#import "TKPersonalFeed.h"
#import "TKTikTok.h"
#import "TKFeed.h"
#import "TKCommon.h"
#import "TKHTTP.h"
#import "TKSettings.h"

@interface TKPersonalFeed ()
@property (nonatomic, strong) NSMutableArray *mutableVideos;
@property (nonatomic, assign, readwrite) BOOL loading;
@property (nonatomic, strong) TKFeed *learningFeed;
@property (nonatomic, strong) TKHTTPTask *task;
@property (nonatomic) NSUInteger generation;
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
        _learningFeed = [[TKFeed alloc] init];
    }
    return self;
}

- (void)dealloc { [_task cancel]; }

- (NSArray *)videos
{
    return [self.mutableVideos copy];
}

- (void)reloadWithCompletion:(void (^)(NSError *error))completion
{
    [self.task cancel];
    NSUInteger generation=++self.generation;
    self.loading = YES;
    void (^handleVideos)(NSArray *, NSError *) = ^(NSArray *videos, NSError *error) {
        if (generation != self.generation) return;
        self.task=nil;
        self.loading = NO;
        videos=[videos filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(TKVideo *v,NSDictionary *bindings){ return [TKSettings allowsPost:[v toJSON]]; }]];
        if(!videos.count && !error)error=TKMakeError(TKErrorAPI,L(@"No videos match your feed filters."));
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
        self.task=[TKTikTok followingFeedWithCount:20 completion:handleVideos];
    } else {
        self.task=[TKTikTok personalFeedWithCount:20 completion:handleVideos];
    }
}

- (void)ensureAhead:(NSInteger)index by:(NSInteger)count completion:(void (^)(BOOL added))completion
{
    if (self.loading || (index + count < (NSInteger)self.mutableVideos.count)) {
        if (completion) completion(NO);
        return;
    }

    NSUInteger generation=self.generation;
    self.loading = YES;
    void (^handleMore)(NSArray *, NSError *) = ^(NSArray *videos, NSError *error) {
        if (generation != self.generation) return;
        self.task=nil;
        self.loading = NO;
        videos=[videos filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(TKVideo *v,NSDictionary *bindings){ return [TKSettings allowsPost:[v toJSON]]; }]];
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
        self.task=[TKTikTok followingFeedWithCount:20 completion:handleMore];
    } else {
        self.task=[TKTikTok personalFeedWithCount:20 completion:handleMore];
    }
}

- (void)noteWatched:(TKVideo *)video seconds:(NSTimeInterval)watched duration:(NSTimeInterval)duration passive:(BOOL)passive
{
    [self.learningFeed noteWatched:video seconds:watched duration:duration passive:passive];
}

- (void)noteSaved:(TKVideo *)video
{
    [self.learningFeed noteSaved:video];
}

- (void)noteNotInterested:(TKVideo *)video
{
    [self.learningFeed noteNotInterested:video];
}

- (void)noteEngaged:(TKVideo *)video weight:(double)weight
{
    [self.learningFeed noteEngaged:video weight:weight];
}

@end
