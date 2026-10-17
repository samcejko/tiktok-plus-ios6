#import "TKFeed.h"
#import "TKTaste.h"
#import "TKTikTok.h"
#import "TKSettings.h"
#import "TKCommon.h"
#include <math.h>

static const NSUInteger TKPoolLow = 12;                     // refill below this many candidates
static const NSInteger TKBatchPerTopic = 16;
static const NSTimeInterval TKPlayURLMaxAge = 12 * 3600;    // TikTok's URLs last about two days

typedef void (^TKFeedJob)(void (^done)(NSArray *videos));

static double TKFeedRandom(void) { return ((double)arc4random() + 0.5) / 4294967296.0; }

@interface TKFeed ()
@property (nonatomic, strong) NSMutableArray *pool;            // candidates not placed yet
@property (nonatomic, strong) NSMutableSet *knownIds;          // placed or pooled in this session
@property (nonatomic, strong) NSMutableArray *refillWaiters;   // completions of the refill in flight
@property (nonatomic) BOOL loading;
@end

@implementation TKFeed {
    NSMutableArray *_videos;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _videos = [NSMutableArray array];
        _pool = [NSMutableArray array];
        _knownIds = [NSMutableSet set];
        _refillWaiters = [NSMutableArray array];
    }
    return self;
}

- (NSArray *)videos { return _videos; }

#pragma mark - Candidates

// Asks for a few topics (and maybe one followed creator); completion(any new candidates) once all have answered.
- (void)refill:(void (^)(BOOL any))completion
{
    if (completion) [self.refillWaiters addObject:[completion copy]];
    if (self.loading) return;
    self.loading = YES;

    TKTaste *taste = [TKTaste shared];
    NSArray *topics = [taste topicsToFetch:(taste.updates < 20 ? 3 : 2)];   // wider while the taste is young
    NSMutableArray *jobs = [NSMutableArray array];
    for (NSNumber *t in topics) {
        TKFeedJob job = ^(void (^done)(NSArray *)) {
            [TKTikTok discoverCategory:t.integerValue count:TKBatchPerTopic completion:^(NSArray *videos, NSError *error) {
                if (error) TKLog(@"feed: %@ failed: %@", [TKTaste topicName:t.integerValue], error.localizedDescription);
                done(videos);
            }];
        };
        [jobs addObject:job];
    }

    __block NSInteger pending = (NSInteger)jobs.count;
    __block NSUInteger added = 0;
    for (TKFeedJob job in jobs) {
        job(^(NSArray *videos) {
            for (TKVideo *v in videos) {
                if (!v.videoId.length || [self.knownIds containsObject:v.videoId] || [TKSettings hasSeenVideo:v.videoId]) continue;
                if (![TKSettings allowsLanguage:v.lang]) continue;           // languages the viewer turned off
                [self.knownIds addObject:v.videoId];
                [self.pool addObject:v];
                added++;
            }
            if (--pending > 0) return;
            self.loading = NO;
            NSMutableArray *names = [NSMutableArray array];
            for (NSNumber *t in topics) [names addObject:[TKTaste topicName:t.integerValue]];
            TKLog(@"feed: +%lu candidates from %@, pool %lu", (unsigned long)added, [names componentsJoinedByString:@", "], (unsigned long)self.pool.count);
            NSArray *waiters = [self.refillWaiters copy];
            [self.refillWaiters removeAllObjects];
            for (void (^w)(BOOL) in waiters) w(added > 0);
        });
    }
}

// The next video: usually the best-scoring candidate (randomly among the top few), sometimes a pure exploration
// pick; never a creator of the last few videos, rarely the same topic three times running.
- (TKVideo *)takeNext
{
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    for (NSInteger i = (NSInteger)self.pool.count - 1; i >= 0; i--) {   // a stale URL is not worth re-resolving;
        TKVideo *v = self.pool[(NSUInteger)i];                             // a language turned off since goes too
        if ((v.fetchedAt > 0 && now - v.fetchedAt > TKPlayURLMaxAge) || ![TKSettings allowsLanguage:v.lang])
            [self.pool removeObjectAtIndex:(NSUInteger)i];
    }
    if (!self.pool.count) return nil;

    NSUInteger n = _videos.count;
    NSArray *recent = n > 8 ? [_videos subarrayWithRange:NSMakeRange(n - 8, 8)] : _videos;
    NSMutableSet *recentAuthors = [NSMutableSet set];
    for (TKVideo *v in recent) if (v.author.length) [recentAuthors addObject:[v.author lowercaseString]];
    TKVideo *last = _videos.lastObject;
    TKVideo *beforeLast = n > 1 ? _videos[n - 2] : nil;

    NSMutableArray *cands = [NSMutableArray array];
    for (TKVideo *v in self.pool) if (!v.author.length || ![recentAuthors containsObject:[v.author lowercaseString]]) [cands addObject:v];
    if (!cands.count) cands = [self.pool mutableCopy];

    TKTaste *taste = [TKTaste shared];
    double exploreShare = MAX(0.12, 0.35 - taste.updates * 0.004);   // much exploring at first, never none
    TKVideo *pick = nil;
    if (TKFeedRandom() < exploreShare) {
        NSMutableArray *other = [NSMutableArray array];               // preferably a topic not just shown
        for (TKVideo *v in cands) if (!last || v.category != last.category) [other addObject:v];
        NSArray *from = other.count ? other : cands;
        pick = from[arc4random_uniform((uint32_t)from.count)];
    } else {
        NSMutableArray *scored = [NSMutableArray array];
        for (TKVideo *v in cands) {
            double s = [taste scoreVideo:v];
            if (last && v.category && v.category == last.category) s -= (beforeLast.category == v.category) ? 0.9 : 0.25;
            NSUInteger shared = 0;
            for (NSString *t in v.tags) if ([last.tags containsObject:t]) shared++;
            s -= 0.15 * MIN(shared, (NSUInteger)3);
            [scored addObject:@[ @(s), v ]];
        }
        [scored sortUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) { return [b[0] compare:a[0]]; }];
        // softmax over the best few: the top one usually wins, but not always
        NSUInteger top = MIN((NSUInteger)6, scored.count);
        double best = [scored[0][0] doubleValue], weights[6], total = 0;
        for (NSUInteger i = 0; i < top; i++) { weights[i] = exp(([scored[i][0] doubleValue] - best) / 0.35); total += weights[i]; }
        double r = TKFeedRandom() * total;
        pick = scored[top - 1][1];
        for (NSUInteger i = 0; i < top; i++) { r -= weights[i]; if (r <= 0) { pick = scored[i][1]; break; } }
    }
    [self.pool removeObject:pick];
    return pick;
}

- (NSInteger)appendUpTo:(NSInteger)wanted
{
    NSInteger added = 0;
    while (added < wanted) {
        TKVideo *v = [self takeNext];
        if (!v) break;
        [_videos addObject:v];
        added++;
    }
    return added;
}

#pragma mark - Public

- (void)reloadWithCompletion:(void (^)(NSError *))completion
{
    if (![TKTikTok configured]) {
        if (completion) completion(TKMakeError(TKErrorAPI, L(@"Set the server address in Settings first.")));
        return;
    }
    [self.pool removeAllObjects];      // (knownIds stays: what this session showed does not come back)
    [self refill:^(BOOL any) {
        if (!self.pool.count) {
            if (completion) completion(TKMakeError(TKErrorNetwork, L(@"Could not load any videos. Check the server.")));
            return;
        }
        [self->_videos removeAllObjects];
        [self appendUpTo:6];
        if (completion) completion(nil);
        if (self.pool.count < TKPoolLow) [self refill:nil];
    }];
}

- (void)ensureAhead:(NSInteger)index by:(NSInteger)count completion:(void (^)(BOOL))completion
{
    NSInteger need = (index + count) - (NSInteger)_videos.count;
    NSInteger added = need > 0 ? [self appendUpTo:need] : 0;
    if (need <= added) {
        if (self.pool.count < TKPoolLow) [self refill:nil];   // top the pool up quietly
        if (completion) completion(added > 0);
        return;
    }
    [self refill:^(BOOL any) {
        NSInteger more = [self appendUpTo:need - added];
        if (completion) completion(added + more > 0);
    }];
}

- (void)noteWatched:(TKVideo *)video seconds:(NSTimeInterval)watched duration:(NSTimeInterval)duration passive:(BOOL)passive
{
    if (!video) return;
    double dur = duration > 0.5 ? duration : MAX(1.0, (double)video.durationSeconds);
    double r = watched / dur;
    double e;
    if (watched < 1.5 || r < 0.15) e = 0.0;               // swiped away almost at once
    else if (r < 0.5) e = watched >= 20 ? 0.55 : 0.3;     // a long video watched for a while still counts
    else if (r < 0.9) e = 0.6;
    else if (r < 1.6) e = 0.85;                            // to the end
    else e = 1.0;                                          // and again
    if (passive) e = MIN(e, 0.6);                          // it played out on its own: mild interest at most
    [[TKTaste shared] learnFromVideo:video engagement:e bonus:0];
}

- (void)noteSaved:(TKVideo *)video { [[TKTaste shared] learnFromVideo:video engagement:1.0 bonus:1.0]; }
- (void)noteNotInterested:(TKVideo *)video { [[TKTaste shared] learnFromVideo:video engagement:0.0 bonus:-1.6]; }
- (void)noteEngaged:(TKVideo *)video weight:(double)weight { [[TKTaste shared] nudgeVideo:video reward:weight]; }

@end
