#import <Foundation/Foundation.h>

// One public TikTok video, as the Pi helper describes it. The lightweight list form has no playUrl yet; it is
// filled in by -[TKTikTok resolve:...] right before playback (the direct URL is short-lived).
@interface TKVideo : NSObject
@property (nonatomic, copy) NSString *videoId;
@property (nonatomic, copy) NSString *author;        // @handle without the @
@property (nonatomic, copy) NSString *authorName;    // display name
@property (nonatomic, copy) NSString *desc;
@property (nonatomic, copy) NSString *coverURL;
@property (nonatomic, copy) NSString *webURL;        // the tiktok.com page (for "open in...")
@property (nonatomic, copy) NSString *music;
@property (nonatomic) NSInteger likes;
@property (nonatomic) NSInteger commentCount;
@property (nonatomic) NSInteger plays;
@property (nonatomic) NSInteger durationSeconds;
@property (nonatomic) NSInteger width;
@property (nonatomic) NSInteger height;
// What the recommender learns from (a /discover item carries all of it; other sources fill what they can)
@property (nonatomic) NSInteger category;            // TikTok's topic id (Explore CategoryType), 0 = unknown
@property (nonatomic, copy) NSArray *tags;           // hashtags, lowercased, without the #
@property (nonatomic, copy) NSString *musicId;
@property (nonatomic) BOOL musicOriginal;            // the creator's own sound: unique to the video, says nothing
@property (nonatomic, copy) NSString *musicAuthor;
@property (nonatomic, copy) NSString *musicCoverURL;
// Captions TikTok made for the video (NSDictionary: lang "eng-US", source "ASR" (speech) or "MT" (translation), url
// of a WebVTT file)
@property (nonatomic, copy) NSArray *subtitles;
@property (nonatomic, copy) NSString *lang;          // TikTok's guess of the caption language ("en", "cs", "un")
@property (nonatomic) NSTimeInterval createdAt;      // posted (Unix time), 0 = unknown
@property (nonatomic, copy) NSString *authorAvatarURL;
@property (nonatomic, copy) NSString *authorLiveRoom; // set while the author is live (a room id)
// A photo post (slideshow) instead of a video: its pictures and, when TikTok gives one to a visitor, its sound
@property (nonatomic) BOOL isPhoto;
@property (nonatomic, copy) NSArray *imageURLs;      // NSString, JPEG
@property (nonatomic, copy) NSString *audioURL;
// Filled by resolve (or handed out ready by /discover):
@property (nonatomic, copy) NSString *playURL;       // the TikTok CDN URL
@property (nonatomic, copy) NSDictionary *playHeaders; // Referer/User-Agent/Cookie the CDN needs
@property (nonatomic) NSTimeInterval fetchedAt;      // when playURL was handed out (it lasts about two days)
@property (nonatomic, readonly) BOOL playable;        // has what it needs to show: a play URL, or pictures

+ (instancetype)videoFromJSON:(NSDictionary *)json;
// A helper list's items; those ready to play get `headers` (the session cookies their URLs play with)
+ (NSArray *)videosFromItems:(NSArray *)items headers:(NSDictionary *)headers;
- (NSDictionary *)toJSON;                             // for the local saved/cache store
- (NSString *)shareURL;
@end

@interface TKComment : NSObject
@property (nonatomic, copy) NSString *commentId;
@property (nonatomic, copy) NSString *author;
@property (nonatomic, copy) NSString *authorName;
@property (nonatomic, copy) NSString *avatarURL;
@property (nonatomic) NSTimeInterval createdAt;      // Unix time, 0 = unknown
@property (nonatomic, copy) NSString *text;
@property (nonatomic) NSInteger likes;
@property (nonatomic) NSInteger replyCount;
@property (nonatomic) BOOL pinned;
@property (nonatomic) BOOL isReply;
+ (instancetype)commentFromJSON:(NSDictionary *)json;
@end

// A creator's profile page
@interface TKProfile : NSObject
@property (nonatomic, copy) NSString *handle;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *bio;
@property (nonatomic, copy) NSString *avatarURL;
@property (nonatomic, copy) NSString *liveRoom;       // set while they are live
@property (nonatomic) BOOL verified;
@property (nonatomic) BOOL isPrivate;
@property (nonatomic) long long followers;
@property (nonatomic) long long following;
@property (nonatomic) long long likes;
@property (nonatomic) NSInteger videoCount;
@property (nonatomic, copy) NSString *link;           // the link in their bio
@property (nonatomic, copy) NSString *secUid;         // what their post list is asked by
@property (nonatomic, copy) NSString *userId;
@property (nonatomic, copy) NSArray *videos;         // TKVideo, the newest posts (ready to play, or resolved when played)
@property (nonatomic) long long postsCursor;          // where the next page of posts starts (0 = none)
@property (nonatomic) BOOL postsUnavailable;
@property (nonatomic) BOOL hasMorePosts;
+ (instancetype)profileFromJSON:(NSDictionary *)json;
+ (instancetype)profileFromUserJSON:(NSDictionary *)user;   // just who they are (a search result)
@end

// A hashtag's page
@interface TKHashtag : NSObject
@property (nonatomic, copy) NSString *tagId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *desc;
@property (nonatomic) long long videoCount;
@property (nonatomic) long long viewCount;
+ (instancetype)hashtagFromJSON:(NSDictionary *)json;
@end

// A sound (music) and where to hear it
@interface TKSound : NSObject
@property (nonatomic, copy) NSString *soundId;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *author;
@property (nonatomic, copy) NSString *authorHandle;
@property (nonatomic, copy) NSString *coverURL;
@property (nonatomic, copy) NSString *playURL;
@property (nonatomic, copy) NSDictionary *headers;
@property (nonatomic) NSInteger durationSeconds;
@property (nonatomic) long long videoCount;
@property (nonatomic) BOOL original;                  // someone's own sound, not a song
+ (instancetype)soundFromJSON:(NSDictionary *)json;
@end

// One page of a list from the helper: search results, a hashtag's or a sound's videos, a creator's posts
@interface TKVideoPage : NSObject
@property (nonatomic, copy) NSArray *videos;          // TKVideo, ready to play
@property (nonatomic, copy) NSArray *users;           // TKProfile without videos (search: creators TikTok shows first)
@property (nonatomic) long long cursor;               // where the next page starts
@property (nonatomic) BOOL hasMore;
@property (nonatomic, strong) TKHashtag *hashtag;
@property (nonatomic, strong) TKSound *sound;
+ (instancetype)pageFromJSON:(NSDictionary *)json cursorKey:(NSString *)cursorKey;
@end

// A live room and the streams TikTok hands a visitor
@interface TKLiveRoom : NSObject
@property (nonatomic, copy) NSString *roomId;
@property (nonatomic) BOOL live;
@property (nonatomic, copy) NSString *title;
@property (nonatomic) NSInteger viewers;
@property (nonatomic, copy) NSString *coverURL;
@property (nonatomic, copy) NSString *ownerHandle;
@property (nonatomic, copy) NSString *ownerName;
@property (nonatomic, copy) NSString *ownerAvatarURL;
@property (nonatomic, copy) NSArray *streams;        // NSDictionary: quality, flv, hls, vcodec, resolution
@property (nonatomic, copy) NSDictionary *headers;
+ (instancetype)roomFromJSON:(NSDictionary *)json;
@end
