#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// User preferences in NSUserDefaults (the server key is in the keychain). Setters post TKSettingsDidChangeNotification.
@interface TKSettings : NSObject

+ (void)registerDefaults;
+ (void)save;

// The Pi helper
+ (NSString *)serverBaseURL;            // e.g. http://192.168.1.154:8730 or https://ytdlp.samcejko.eu
+ (void)setServerBaseURL:(NSString *)value;
+ (NSString *)serverKey;                // keychain; "" when none
+ (void)setServerKey:(NSString *)value;
+ (BOOL)serverConfigured;
+ (BOOL)streamThroughServer;            // force video through the Pi /proxy (for use away from home); default NO
+ (void)setStreamThroughServer:(BOOL)value;

// Playback
+ (BOOL)startMuted;
+ (void)setStartMuted:(BOOL)value;
+ (BOOL)autoAdvance;                    // move to the next video when one ends
+ (void)setAutoAdvance:(BOOL)value;
+ (BOOL)showCaptions;                   // TikTok's captions over the video when it has some; default YES
+ (void)setShowCaptions:(BOOL)value;

// The topics picked at the first start (the screen shows once)
+ (BOOL)topicsChosen;
+ (void)setTopicsChosen:(BOOL)value;

// Searches, newest first
+ (NSArray *)searchHistory;
+ (void)addSearch:(NSString *)query;
+ (void)clearSearchHistory;

// Appearance
+ (BOOL)darkTheme;
+ (void)setDarkTheme:(BOOL)value;

// Network
+ (BOOL)verifyTLS;
+ (void)setVerifyTLS:(BOOL)value;

// Languages the feed leaves out: TikTok's caption language codes, plus "un" (no caption text) and "*" (every
// language not in +knownLanguages, the list the settings show)
+ (NSArray *)knownLanguages;
+ (NSArray *)hiddenLanguages;
+ (void)setHiddenLanguages:(NSArray *)codes;
+ (BOOL)allowsLanguage:(NSString *)code;

// Saved videos (each is TKVideo -toJSON; newest first)
+ (NSArray *)savedVideos;
+ (BOOL)isSaved:(NSString *)videoId;
+ (void)saveVideoJSON:(NSDictionary *)json;
+ (void)unsaveVideo:(NSString *)videoId;

// Local viewing history; independent of TikTok account history and feed deduplication.
+ (BOOL)recordWatchHistory;
+ (void)setRecordWatchHistory:(BOOL)value;
+ (NSArray *)watchHistory;
+ (void)recordWatchedVideo:(NSDictionary *)json;
+ (void)removeFromWatchHistory:(NSString *)videoId;
+ (void)clearWatchHistory;

+ (NSArray *)favoriteCreators;
+ (NSArray *)favoriteSounds;
+ (BOOL)isFavoriteCreator:(NSString *)handle;
+ (BOOL)isFavoriteSound:(NSString *)soundId;
+ (void)saveFavoriteCreator:(NSDictionary *)creator;
+ (void)removeFavoriteCreator:(NSString *)handle;
+ (void)saveFavoriteSound:(NSDictionary *)sound;
+ (void)removeFavoriteSound:(NSString *)soundId;
+ (NSArray *)blockedCreators;
+ (void)setCreator:(NSString *)handle blocked:(BOOL)blocked;
+ (NSArray *)hiddenKeywords;
+ (void)setHiddenKeywords:(NSString *)text;
+ (BOOL)allowsPost:(NSDictionary *)video;
+ (BOOL)hidePhotoPosts;
+ (void)setHidePhotoPosts:(BOOL)value;
+ (NSInteger)maxVideoDuration;
+ (void)setMaxVideoDuration:(NSInteger)seconds;
+ (float)defaultPlaybackSpeed;
+ (void)setDefaultPlaybackSpeed:(float)speed;
+ (BOOL)cleanVideo;
+ (void)setCleanVideo:(BOOL)value;

// Collections contain references to saved posts. Removing a collection never deletes saved posts.
+ (NSArray *)collections;
+ (NSString *)createCollection:(NSString *)name;
+ (BOOL)renameCollection:(NSString *)collectionId name:(NSString *)name;
+ (void)deleteCollection:(NSString *)collectionId;
+ (NSArray *)videosInCollection:(NSString *)collectionId;
+ (void)addVideo:(NSDictionary *)video toCollection:(NSString *)collectionId;
+ (void)removeVideo:(NSString *)videoId fromCollection:(NSString *)collectionId;
+ (NSString *)watchLaterCollectionId;

// Videos already shown (the feed does not bring them back; the taste itself lives in TKTaste)
+ (BOOL)hasSeenVideo:(NSString *)videoId;
+ (void)markVideoSeen:(NSString *)videoId;
// Account actions (Phase 3 writes: like, follow, comment - experimental, off by default)
+ (BOOL)allowAccountWrites;
+ (void)setAllowAccountWrites:(BOOL)value;

@end
