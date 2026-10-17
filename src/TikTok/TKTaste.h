#import <Foundation/Foundation.h>
#import "TKModels.h"

// The viewer's taste, learned only from how they watch (it never leaves the device):
//  - a weight per feature of a video - its topic, hashtags, creator, shared sound, caption language and length.
//    Finishing or saving a video raises the weights of its features, swiping it away lowers them;
//  - a success record per Explore topic, from which -topicsToFetch: draws (Thompson sampling): topics that
//    worked come up more often, untried and uncertain ones still get their turn.
// Old lessons slowly fade, so a changing taste shows through.
@interface TKTaste : NSObject

+ (instancetype)shared;

// TikTok's Explore topics (CategoryType ids as NSNumber) and an English name for the log
+ (NSArray *)topicIds;
+ (NSString *)topicName:(NSInteger)topicId;

@property (nonatomic, readonly) NSUInteger updates;       // lessons so far (how experienced the model is)

- (double)scoreVideo:(TKVideo *)video;                     // learned preference plus small priors; no randomness
- (NSArray *)topicsToFetch:(NSUInteger)count;              // NSNumber topic ids, drawn by Thompson sampling

// A lesson: engagement 0 (gone at once) ... 1 (watched again, saved); bonus adds to the reward of the features
- (void)learnFromVideo:(TKVideo *)video engagement:(double)engagement bonus:(double)bonus;
// A small extra nudge to the features only (comments opened, link copied)
- (void)nudgeVideo:(TKVideo *)video reward:(double)reward;
// Topics picked by hand (the first start, or later in the settings): a head start in the topic draws and the scores;
// the others are not shut out, they just wait more
- (void)seedTopics:(NSArray *)topicIds;

// For the "what it learned about me" screen
+ (NSString *)localizedTopicName:(NSInteger)topicId;
- (NSArray *)featureWeightsWithPrefix:(NSString *)prefix;  // @[ key, weight ] pairs ("tag:", "au:"...), strongest first
- (NSArray *)topicRecords;     // NSDictionary id, rate (0..1), seen (how much evidence) - topics with a record, best first
- (void)forgetFeature:(NSString *)key;
- (void)forgetTopic:(NSInteger)topicId;

- (NSString *)summary;                                     // debug: strongest likes and dislikes, topic odds
- (NSString *)explainVideo:(TKVideo *)video;               // debug: the feature weights behind a video's score
- (void)reset;

@end
