#import <Foundation/Foundation.h>
#import "TKModels.h"

@class TKHTTPTask;

// Talks to the Pi helper (the only server this app needs). All completions run on the main thread.
@interface TKTikTok : NSObject

+ (BOOL)configured;                          // a server base URL is set
+ (void)checkHealth:(void (^)(BOOL ok, NSString *info, NSError *error))completion;

// A fresh batch from TikTok's Explore feed for one topic (an Explore CategoryType). Ready to play: playURL and
// playHeaders are set, and every item carries the features the recommender learns from.
+ (TKHTTPTask *)discoverCategory:(NSInteger)category count:(NSInteger)count completion:(void (^)(NSArray *videos, NSError *error))completion;

// A creator's recent public videos (lightweight items; call resolveVideo: before playing one)
+ (TKHTTPTask *)videosForCreator:(NSString *)handle count:(NSInteger)count completion:(void (^)(NSArray *videos, NSError *error))completion;

// Fills in playURL + playHeaders (short-lived). Pass a TKVideo from a list, or build one with just videoId set.
+ (TKHTTPTask *)resolveVideo:(TKVideo *)video completion:(void (^)(TKVideo *resolved, NSError *error))completion;
+ (TKHTTPTask *)resolveId:(NSString *)videoId author:(NSString *)author completion:(void (^)(TKVideo *resolved, NSError *error))completion;

+ (TKHTTPTask *)commentsForVideo:(NSString *)videoId count:(NSInteger)count completion:(void (^)(NSArray *comments, NSError *error))completion;
+ (TKHTTPTask *)repliesForVideo:(NSString *)videoId comment:(NSString *)commentId count:(NSInteger)count completion:(void (^)(NSArray *replies, NSError *error))completion;

// A creator's page: who they are and their newest posts; more of them, older than the cursor
+ (TKHTTPTask *)profileForUser:(NSString *)handle completion:(void (^)(TKProfile *profile, NSError *error))completion;
+ (TKHTTPTask *)postsOf:(TKProfile *)profile cursor:(long long)cursor completion:(void (^)(TKVideoPage *page, NSError *error))completion;

// TikTok's search (videos ready to play, and the creators it puts first), and what it suggests while typing
+ (TKHTTPTask *)search:(NSString *)query offset:(long long)offset completion:(void (^)(TKVideoPage *page, NSError *error))completion;
+ (TKHTTPTask *)suggestionsFor:(NSString *)text completion:(void (^)(NSArray *words, NSError *error))completion;

// A hashtag's or a sound's videos (page.hashtag / page.sound describe it; 0 = the first page)
+ (TKHTTPTask *)hashtag:(NSString *)name cursor:(long long)cursor completion:(void (^)(TKVideoPage *page, NSError *error))completion;
+ (TKHTTPTask *)sound:(NSString *)soundId cursor:(long long)cursor completion:(void (^)(TKVideoPage *page, NSError *error))completion;

// A small text file straight from TikTok's CDN (captions)
+ (TKHTTPTask *)fetchText:(NSString *)url completion:(void (^)(NSString *text, NSError *error))completion;

// Live: one room (is it on, its streams), and the rooms seen lately among Explore authors (NSDictionary: room, user,
// name, avatar) - the only way to find live streams without an account
+ (TKHTTPTask *)liveRoom:(NSString *)roomId completion:(void (^)(TKLiveRoom *room, NSError *error))completion;
+ (TKHTTPTask *)liveRooms:(void (^)(NSArray *rooms, NSError *error))completion;

// Where a (short) TikTok link leads
+ (TKHTTPTask *)expandLink:(NSString *)link completion:(void (^)(NSString *url, NSError *error))completion;

// The Pi /proxy URL that streams a resolved video's bytes through the Pi (fallback, and for use away from home)
+ (NSString *)proxyURLForPlayURL:(NSString *)playURL;

// Logged-in session & user features
+ (TKHTTPTask *)sessionCreateWithCookies:(NSString *)cookieData completion:(void (^)(BOOL success, NSString *token, NSDictionary *user, NSError *error))completion;
+ (TKHTTPTask *)sessionValidateWithCompletion:(void (^)(BOOL valid, NSDictionary *user, NSError *error))completion;
+ (TKHTTPTask *)sessionDeleteWithCompletion:(void (^)(BOOL success))completion;

+ (TKHTTPTask *)myProfileWithCompletion:(void (^)(TKProfile *profile, NSError *error))completion;
+ (TKHTTPTask *)followingFeedWithCount:(NSInteger)count completion:(void (^)(NSArray *videos, NSError *error))completion;
+ (TKHTTPTask *)personalFeedWithCount:(NSInteger)count completion:(void (^)(NSArray *videos, NSError *error))completion;
+ (TKHTTPTask *)likedVideosWithCount:(NSInteger)count completion:(void (^)(NSArray *videos, NSError *error))completion;
+ (TKHTTPTask *)notificationsWithCount:(NSInteger)count completion:(void (^)(NSArray *notifications, NSError *error))completion;

// Logged-in writes (Phase 3: like, follow, comment)
+ (TKHTTPTask *)diggVideoId:(NSString *)videoId type:(NSInteger)type completion:(void (^)(BOOL success, NSError *error))completion;
+ (TKHTTPTask *)followUserId:(NSString *)userId secUid:(NSString *)secUid type:(NSInteger)type completion:(void (^)(BOOL success, NSError *error))completion;
+ (TKHTTPTask *)postCommentOnVideoId:(NSString *)videoId text:(NSString *)text completion:(void (^)(BOOL success, NSDictionary *comment, NSError *error))completion;

@end
