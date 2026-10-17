#import "TKTaste.h"
#import "TKCommon.h"
#include <math.h>

static NSString * const TKTasteKey = @"taste";
static const double TKLearningRate = 0.35;
static const double TKWeightLimit = 6.0;
static const NSUInteger TKMaxFeatures = 3000;

#pragma mark - Random numbers for the topic draws

static double TKUniform(void) { return ((double)arc4random() + 0.5) / 4294967296.0; }

static double TKNormal(void)   // Box-Muller
{
    return sqrt(-2.0 * log(TKUniform())) * cos(2.0 * M_PI * TKUniform());
}

static double TKGamma(double shape)   // Marsaglia & Tsang
{
    if (shape < 1.0) return TKGamma(shape + 1.0) * pow(TKUniform(), 1.0 / shape);
    double d = shape - 1.0 / 3.0, c = 1.0 / sqrt(9.0 * d);
    for (;;) {
        double x = TKNormal(), v = 1.0 + c * x;
        if (v <= 0) continue;
        v = v * v * v;
        double u = TKUniform();
        if (u < 1.0 - 0.0331 * x * x * x * x) return d * v;
        if (log(u) < 0.5 * x * x + d * (1.0 - v + log(v))) return d * v;
    }
}

static double TKBeta(double a, double b)
{
    double x = TKGamma(a), y = TKGamma(b);
    return x / (x + y);
}

// Hashtags that say nothing about the content (everyone puts them on everything)
static BOOL TKGenericTag(NSString *tag)
{
    static NSSet *exact;
    if (!exact) exact = [NSSet setWithArray:@[ @"fyp", @"fy", @"foryou", @"foryoupage", @"fypage", @"viral", @"trending",
                                               @"trend", @"tiktok", @"xyzbca", @"capcut", @"explore", @"explorepage",
                                               @"reels", @"duet", @"stitch", @"рек", @"реки", @"тренды", @"тренд" ]];
    if ([exact containsObject:tag]) return YES;
    for (NSString *p in @[ @"fyp", @"foryou", @"viral", @"xyz", @"рекоменд", @"tiktok" ]) if ([tag hasPrefix:p]) return YES;
    return NO;
}

@interface TKTaste ()
@property (nonatomic, strong) NSMutableDictionary *weights;   // feature -> NSNumber
@property (nonatomic, strong) NSMutableDictionary *topics;    // @"104" -> @[ alpha, beta ]
@property (nonatomic) NSUInteger updates;
@property (nonatomic, strong) NSSet *preferredLanguages;
@end

@implementation TKTaste

+ (instancetype)shared
{
    static TKTaste *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[TKTaste alloc] init]; });
    return shared;
}

+ (NSArray *)topicIds
{
    return @[ @100, @101, @102, @103, @104, @105, @106, @107, @108, @109,
              @110, @111, @112, @113, @114, @115, @116, @117, @118, @119 ];
}

+ (NSString *)topicName:(NSInteger)topicId
{
    static NSDictionary *names;
    if (!names) names = @{ @100: @"Anime & Comics", @101: @"Shows", @102: @"Beauty Care", @103: @"Games", @104: @"Comedy",
                           @105: @"Daily Life", @106: @"Family", @107: @"Relationship", @108: @"Drama", @109: @"Outfit",
                           @110: @"Lipsync", @111: @"Food", @112: @"Sports", @113: @"Animals", @114: @"Society",
                           @115: @"Cars", @116: @"Education", @117: @"Fitness & Health", @118: @"Technology",
                           @119: @"Singing & Dancing" };
    return names[@(topicId)] ?: [NSString stringWithFormat:@"topic %ld", (long)topicId];
}

- (instancetype)init
{
    if ((self = [super init])) {
        NSDictionary *saved = TKDict([[NSUserDefaults standardUserDefaults] objectForKey:TKTasteKey]);
        _weights = [TKDict(saved[@"w"]) mutableCopy] ?: [NSMutableDictionary dictionary];
        _topics = [TKDict(saved[@"t"]) mutableCopy] ?: [NSMutableDictionary dictionary];
        _updates = (NSUInteger)MAX(0, TKInt(saved[@"n"]));
        // the device's languages get a head start until the viewer's own behaviour says otherwise
        NSMutableSet *langs = [NSMutableSet setWithObject:@"en"];
        for (NSString *l in [NSLocale preferredLanguages]) {
            NSString *code = [[[l componentsSeparatedByString:@"-"] firstObject] lowercaseString];
            if (code.length) [langs addObject:code];
            if (langs.count >= 4) break;
        }
        if ([langs containsObject:@"cs"] || [langs containsObject:@"sk"]) [langs addObjectsFromArray:@[ @"cs", @"sk" ]];
        _preferredLanguages = langs;
    }
    return self;
}

#pragma mark - Features

// feature -> its share of the video's reward (the hashtags split one share between them)
- (NSDictionary *)featuresOf:(TKVideo *)v
{
    NSMutableDictionary *f = [NSMutableDictionary dictionary];
    if (!v) return f;
    if (v.category) f[[NSString stringWithFormat:@"cat:%ld", (long)v.category]] = @0.6;
    NSMutableArray *tags = [NSMutableArray array];
    for (NSString *t in v.tags) if (t.length && !TKGenericTag(t) && tags.count < 6) [tags addObject:t];
    for (NSString *t in tags) f[[@"tag:" stringByAppendingString:t]] = @(0.9 / tags.count);
    if (v.author.length) f[[@"au:" stringByAppendingString:[v.author lowercaseString]]] = @1.0;
    if (v.musicId.length && !v.musicOriginal) f[[@"snd:" stringByAppendingString:v.musicId]] = @0.5;
    if (v.lang.length && ![v.lang isEqualToString:@"un"]) f[[@"lang:" stringByAppendingString:v.lang]] = @0.6;
    NSInteger d = v.durationSeconds;
    if (d > 0) f[d < 12 ? @"len:short" : (d < 40 ? @"len:mid" : @"len:long")] = @0.25;
    return f;
}

- (double)scoreVideo:(TKVideo *)v
{
    NSDictionary *f = [self featuresOf:v];
    double s = 0;
    for (NSString *k in f) {
        double share = [f[k] doubleValue];
        NSNumber *w = self.weights[k];
        if (w) s += w.doubleValue * share;
        else if ([k hasPrefix:@"lang:"]) s += ([self.preferredLanguages containsObject:[k substringFromIndex:5]] ? 0.6 : -0.25) * share;
    }
    s += 0.15 * MIN(1.0, log10(1.0 + (double)MAX(0, v.likes)) / 6.0);   // a light nudge toward what others liked
    if (v.createdAt > 0) {                                               // and toward what is new: today +0.35,
        double days = MAX(0.0, ([[NSDate date] timeIntervalSince1970] - v.createdAt) / 86400.0);   // in ten days a third,
        s += 0.35 * exp(-days / 10.0);                                                              // in a month nothing
    }
    return s;
}

#pragma mark - Topics

- (void)topic:(NSInteger)topicId alpha:(double *)alpha beta:(double *)beta
{
    NSArray *ab = TKArr(self.topics[[NSString stringWithFormat:@"%ld", (long)topicId]]);
    *alpha = ab.count == 2 ? MAX(1.0, TKDbl(ab[0])) : 1.0;
    *beta = ab.count == 2 ? MAX(1.0, TKDbl(ab[1])) : 1.0;
}

- (NSArray *)topicsToFetch:(NSUInteger)count
{
    NSMutableArray *draws = [NSMutableArray array];
    for (NSNumber *t in [TKTaste topicIds]) {
        double a, b;
        [self topic:t.integerValue alpha:&a beta:&b];
        [draws addObject:@[ @(TKBeta(a, b)), t ]];
    }
    [draws sortUsingComparator:^NSComparisonResult(NSArray *x, NSArray *y) { return [y[0] compare:x[0]]; }];
    NSMutableArray *out = [NSMutableArray array];
    for (NSArray *d in draws) { if (out.count >= count) break; [out addObject:d[1]]; }
    // now and then one slot goes to a topic picked blindly, so a taste can widen instead of narrowing for good
    if (count > 1 && arc4random_uniform(4) == 0) {
        NSArray *all = [TKTaste topicIds];
        NSNumber *blind = all[arc4random_uniform((uint32_t)all.count)];
        if (![out containsObject:blind]) out[out.count - 1] = blind;
    }
    return out;
}

#pragma mark - Learning

- (void)applyReward:(double)reward toVideo:(TKVideo *)v
{
    NSDictionary *f = [self featuresOf:v];
    for (NSString *k in f) {
        double w = [self.weights[k] doubleValue] + TKLearningRate * reward * [f[k] doubleValue];
        self.weights[k] = @(MAX(-TKWeightLimit, MIN(TKWeightLimit, w)));
    }
}

- (void)learnFromVideo:(TKVideo *)v engagement:(double)engagement bonus:(double)bonus
{
    if (!v) return;
    double e = MAX(0.0, MIN(1.0, engagement));
    double reward = (e - 0.45) * 2.0 + bonus;    // e 0 -> -0.9, 0.3 -> -0.3, 0.6 -> +0.3, 0.85 -> +0.8, 1 -> +1.1
    [self applyReward:reward toVideo:v];
    if (v.category) {
        double a, b;
        [self topic:v.category alpha:&a beta:&b];
        a = 1.0 + (a - 1.0) * 0.97 + e;                                    // older outcomes fade
        b = 1.0 + (b - 1.0) * 0.97 + (1.0 - e) + (bonus < -1.0 ? 1.0 : 0.0);
        self.topics[[NSString stringWithFormat:@"%ld", (long)v.category]] = @[ @(a), @(b) ];
    }
    self.updates++;
    if (self.updates % 40 == 0) [self forgetALittle];
    [self persist];
    TKLog(@"taste: %@ e=%.2f reward=%+.2f | %@", v.videoId, e, reward, [self explainVideo:v]);
}

- (void)nudgeVideo:(TKVideo *)v reward:(double)reward
{
    if (!v) return;
    [self applyReward:reward toVideo:v];
    [self persist];
}

- (void)seedTopics:(NSArray *)topicIds
{
    if (!topicIds.count) return;
    NSSet *picked = [NSSet setWithArray:topicIds];
    for (NSNumber *t in [TKTaste topicIds]) {
        double a, b;
        [self topic:t.integerValue alpha:&a beta:&b];
        BOOL yes = [picked containsObject:t];
        if (yes) a += 4.0; else b += 1.0;                 // as if four videos of it held you, one of each other failed
        self.topics[[NSString stringWithFormat:@"%ld", (long)t.integerValue]] = @[ @(a), @(b) ];
        if (yes) {
            NSString *cat = [NSString stringWithFormat:@"cat:%ld", (long)t.integerValue];
            self.weights[cat] = @(MIN(TKWeightLimit, [self.weights[cat] doubleValue] + 1.0));
        }
    }
    [self persist];
    TKLog(@"taste: topics picked by hand: %@", [[topicIds valueForKey:@"stringValue"] componentsJoinedByString:@","]);
}

// Old lessons fade so a changed taste shows through; the faintest weights go, which keeps the model small
- (void)forgetALittle
{
    NSMutableArray *drop = [NSMutableArray array];
    for (NSString *k in [self.weights allKeys]) {
        double w = [self.weights[k] doubleValue] * 0.97;
        if (fabs(w) < 0.03) [drop addObject:k];
        else self.weights[k] = @(w);
    }
    [self.weights removeObjectsForKeys:drop];
    if (self.weights.count > TKMaxFeatures) {
        NSArray *byStrength = [self.weights keysSortedByValueUsingComparator:^NSComparisonResult(NSNumber *x, NSNumber *y) {
            return [@(fabs(x.doubleValue)) compare:@(fabs(y.doubleValue))];
        }];
        [self.weights removeObjectsForKeys:[byStrength subarrayWithRange:NSMakeRange(0, self.weights.count - TKMaxFeatures)]];
    }
}

- (void)persist
{
    [[NSUserDefaults standardUserDefaults] setObject:@{ @"w": self.weights, @"t": self.topics, @"n": @(self.updates) } forKey:TKTasteKey];
}

- (void)reset
{
    [self.weights removeAllObjects];
    [self.topics removeAllObjects];
    self.updates = 0;
    [self persist];
}

#pragma mark - What it learned (for the screen that shows it)

+ (NSString *)localizedTopicName:(NSInteger)topicId
{
    switch (topicId) {
        case 100: return L(@"Anime & Comics");
        case 101: return L(@"Shows");
        case 102: return L(@"Beauty Care");
        case 103: return L(@"Games");
        case 104: return L(@"Comedy");
        case 105: return L(@"Daily Life");
        case 106: return L(@"Family");
        case 107: return L(@"Relationship");
        case 108: return L(@"Drama");
        case 109: return L(@"Outfit");
        case 110: return L(@"Lipsync");
        case 111: return L(@"Food");
        case 112: return L(@"Sports");
        case 113: return L(@"Animals");
        case 114: return L(@"Society");
        case 115: return L(@"Cars");
        case 116: return L(@"Education");
        case 117: return L(@"Fitness & Health");
        case 118: return L(@"Technology");
        case 119: return L(@"Singing & Dancing");
        default: return L(@"Other");
    }
}

- (NSArray *)featureWeightsWithPrefix:(NSString *)prefix
{
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *k in self.weights) {
        double w = [self.weights[k] doubleValue];
        if ([k hasPrefix:prefix] && fabs(w) >= 0.1) [out addObject:@[ k, @(w) ]];
    }
    [out sortUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) {
        return [@(fabs([b[1] doubleValue])) compare:@(fabs([a[1] doubleValue]))];
    }];
    return out;
}

- (NSArray *)topicRecords
{
    NSMutableArray *out = [NSMutableArray array];
    for (NSNumber *t in [TKTaste topicIds]) {
        double a, b;
        [self topic:t.integerValue alpha:&a beta:&b];
        if (a + b <= 2.01) continue;
        [out addObject:@{ @"id": t, @"rate": @(a / (a + b)), @"seen": @(a + b - 2.0) }];
    }
    [out sortUsingComparator:^NSComparisonResult(NSDictionary *x, NSDictionary *y) { return [y[@"rate"] compare:x[@"rate"]]; }];
    return out;
}

- (void)forgetFeature:(NSString *)key
{
    if (!key.length) return;
    [self.weights removeObjectForKey:key];
    [self persist];
}

- (void)forgetTopic:(NSInteger)topicId
{
    [self.topics removeObjectForKey:[NSString stringWithFormat:@"%ld", (long)topicId]];
    [self.weights removeObjectForKey:[NSString stringWithFormat:@"cat:%ld", (long)topicId]];
    [self persist];
}

#pragma mark - Debug

- (NSString *)summary
{
    NSArray *keys = [self.weights keysSortedByValueUsingComparator:^NSComparisonResult(NSNumber *x, NSNumber *y) { return [y compare:x]; }];
    NSMutableArray *likes = [NSMutableArray array], *dislikes = [NSMutableArray array];
    for (NSString *k in keys) {
        double w = [self.weights[k] doubleValue];
        if (w > 0 && likes.count < 8) [likes addObject:[NSString stringWithFormat:@"%@ %.2f", k, w]];
    }
    for (NSString *k in [keys reverseObjectEnumerator]) {
        double w = [self.weights[k] doubleValue];
        if (w < 0 && dislikes.count < 6) [dislikes addObject:[NSString stringWithFormat:@"%@ %.2f", k, w]];
    }
    NSMutableArray *topics = [NSMutableArray array];
    for (NSNumber *t in [TKTaste topicIds]) {
        double a, b;
        [self topic:t.integerValue alpha:&a beta:&b];
        if (a + b > 2.01) [topics addObject:[NSString stringWithFormat:@"%@ %.2f (%.1f)", [TKTaste topicName:t.integerValue], a / (a + b), a + b - 2.0]];
    }
    return [NSString stringWithFormat:@"taste: %lu lessons, %lu features | likes: %@ | dislikes: %@ | topics: %@",
            (unsigned long)self.updates, (unsigned long)self.weights.count, [likes componentsJoinedByString:@", "],
            [dislikes componentsJoinedByString:@", "], [topics componentsJoinedByString:@", "]];
}

- (NSString *)explainVideo:(TKVideo *)v
{
    NSDictionary *f = [self featuresOf:v];
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *k in [[f allKeys] sortedArrayUsingSelector:@selector(compare:)])
        [parts addObject:[NSString stringWithFormat:@"%@=%.2f", k, [self.weights[k] doubleValue]]];
    return [parts componentsJoinedByString:@" "];
}

@end
