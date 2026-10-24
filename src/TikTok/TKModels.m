#import "TKModels.h"
#import "TKCommon.h"

@implementation TKVideo

+ (instancetype)videoFromJSON:(NSDictionary *)json
{
    if (![json isKindOfClass:[NSDictionary class]]) return nil;
    TKVideo *v = [[TKVideo alloc] init];
    v.videoId = TKStr(json[@"id"]);
    if (!v.videoId.length) return nil;
    v.author = TKStr(json[@"author"]);
    v.authorName = TKStr(json[@"authorName"]) ?: v.author;
    v.desc = TKStr(json[@"desc"]) ?: @"";
    v.coverURL = TKStr(json[@"cover"]);
    v.webURL = TKStr(json[@"url"]);
    v.music = TKStr(json[@"music"]);
    v.likes = TKInt(json[@"likes"]);
    v.commentCount = TKInt(json[@"comments"]);
    v.plays = TKInt(json[@"plays"]);
    v.durationSeconds = TKInt(json[@"duration"]);
    v.width = TKInt(json[@"width"]);
    v.height = TKInt(json[@"height"]);
    v.category = TKInt(json[@"category"]);
    NSMutableArray *tags = [NSMutableArray array];
    for (id t in TKArr(json[@"tags"])) { NSString *s = [TKStr(t) lowercaseString]; if (s.length && ![tags containsObject:s]) [tags addObject:s]; }
    v.tags = tags.count ? tags : [self hashtagsInText:v.desc];
    v.musicId = TKStr(json[@"musicId"]);
    v.musicOriginal = TKBool(json[@"musicOriginal"]);
    v.musicAuthor = TKStr(json[@"musicAuthor"]);
    v.musicCoverURL = TKStr(json[@"musicCover"]);
    NSMutableArray *subs = [NSMutableArray array];
    for (id s in TKArr(json[@"subtitles"])) if (TKStr(TKDict(s)[@"url"]).length) [subs addObject:s];
    v.subtitles = subs;
    v.lang = TKStr(json[@"lang"]);
    v.createdAt = TKDbl(json[@"created"]);
    v.authorAvatarURL = TKStr(json[@"authorAvatar"]);
    NSString *room = TKStr(json[@"authorLive"]);
    v.authorLiveRoom = (room.length && ![room isEqualToString:@"0"]) ? room : nil;
    v.isPhoto = [TKStr(json[@"type"]) isEqualToString:@"photo"];
    NSMutableArray *images = [NSMutableArray array];
    for (id img in TKArr(json[@"images"])) {
        NSString *u = [img isKindOfClass:[NSDictionary class]] ? TKStr(img[@"url"]) : TKStr(img);
        if (u.length) [images addObject:u];
    }
    v.imageURLs = images;
    v.audioURL = TKStr(json[@"musicUrl"]);
    v.playURL = TKStr(json[@"playUrl"]);
    if ([json[@"headers"] isKindOfClass:[NSDictionary class]]) v.playHeaders = json[@"headers"];
    return v;
}

+ (NSArray *)videosFromItems:(NSArray *)items headers:(NSDictionary *)headers
{
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    NSMutableArray *videos = [NSMutableArray array];
    for (id item in TKArr(items)) {
        TKVideo *v = [TKVideo videoFromJSON:TKDict(item)];
        if (!v) continue;
        if (v.playable) {
            if (!v.playHeaders) v.playHeaders = headers;
            v.fetchedAt = now;
        }
        [videos addObject:v];
    }
    return videos;
}

// #words of a caption, for sources that do not list the hashtags separately
+ (NSArray *)hashtagsInText:(NSString *)text
{
    NSMutableArray *out = [NSMutableArray array];
    if (!text.length) return out;
    static NSRegularExpression *re;
    if (!re) re = [NSRegularExpression regularExpressionWithPattern:@"#([\\w]+)" options:0 error:NULL];
    for (NSTextCheckingResult *m in [re matchesInString:text options:0 range:NSMakeRange(0, text.length)]) {
        NSString *tag = [[text substringWithRange:[m rangeAtIndex:1]] lowercaseString];
        if (tag.length && ![out containsObject:tag]) [out addObject:tag];
    }
    return out;
}

- (BOOL)playable { return self.playURL.length > 0 || self.imageURLs.count > 0; }

- (NSDictionary *)toJSON
{
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"id"] = self.videoId ?: @"";
    if (self.author) d[@"author"] = self.author;
    if (self.authorName) d[@"authorName"] = self.authorName;
    if (self.desc) d[@"desc"] = self.desc;
    if (self.coverURL) d[@"cover"] = self.coverURL;
    if (self.webURL) d[@"url"] = self.webURL;
    if (self.music) d[@"music"] = self.music;
    d[@"likes"] = @(self.likes);
    d[@"comments"] = @(self.commentCount);
    d[@"plays"] = @(self.plays);
    d[@"duration"] = @(self.durationSeconds);
    d[@"width"] = @(self.width);
    d[@"height"] = @(self.height);
    if (self.category) d[@"category"] = @(self.category);
    if (self.tags.count) d[@"tags"] = self.tags;
    if (self.musicId.length) d[@"musicId"] = self.musicId;
    d[@"musicOriginal"] = @(self.musicOriginal);
    if (self.musicAuthor.length) d[@"musicAuthor"] = self.musicAuthor;
    if (self.musicCoverURL.length) d[@"musicCover"] = self.musicCoverURL;
    if (self.lang.length) d[@"lang"] = self.lang;
    if (self.createdAt > 0) d[@"created"] = @(self.createdAt);
    if (self.authorAvatarURL.length) d[@"authorAvatar"] = self.authorAvatarURL;
    if (self.isPhoto) d[@"type"] = @"photo";
    // (pictures and play URLs are not kept: they are fetched fresh when the saved post is opened)
    return d;
}

- (NSString *)shareURL
{
    if (self.webURL.length) return self.webURL;
    if (self.author.length && self.videoId.length) return [NSString stringWithFormat:@"https://www.tiktok.com/@%@/video/%@", self.author, self.videoId];
    return [NSString stringWithFormat:@"https://www.tiktok.com/@_/video/%@", self.videoId ?: @""];
}

@end

@implementation TKComment

+ (instancetype)commentFromJSON:(NSDictionary *)json
{
    if (![json isKindOfClass:[NSDictionary class]]) return nil;
    TKComment *c = [[TKComment alloc] init];
    c.commentId = TKStr(json[@"cid"]);
    c.author = TKStr(json[@"author"]) ?: @"";
    c.authorName = TKStr(json[@"authorName"]);
    c.avatarURL = TKStr(json[@"avatar"]);
    c.createdAt = TKDbl(json[@"time"]);
    c.text = TKStr(json[@"text"]) ?: @"";
    c.likes = TKInt(json[@"likes"]);
    c.replyCount = TKInt(json[@"replies"]);
    c.pinned = TKBool(json[@"pinned"]);
    return c;
}

@end

@implementation TKProfile

+ (instancetype)profileFromUserJSON:(NSDictionary *)u
{
    if (![u isKindOfClass:[NSDictionary class]] || !TKStr(u[@"handle"]).length) return nil;
    TKProfile *p = [[TKProfile alloc] init];
    p.handle = TKStr(u[@"handle"]) ?: @"";
    p.name = TKStr(u[@"name"]) ?: @"";
    p.bio = TKStr(u[@"bio"]) ?: @"";
    p.avatarURL = TKStr(u[@"avatar"]);
    NSString *room = TKStr(u[@"liveRoom"]);
    p.liveRoom = (room.length && ![room isEqualToString:@"0"]) ? room : nil;
    p.verified = TKBool(u[@"verified"]);
    p.isPrivate = TKBool(u[@"private"]);
    p.followers = (long long)TKDbl(u[@"followers"]);
    p.following = (long long)TKDbl(u[@"following"]);
    p.likes = (long long)TKDbl(u[@"likes"]);
    p.videoCount = TKInt(u[@"videos"]);
    p.link = TKStr(u[@"link"]);
    p.secUid = TKStr(u[@"secUid"]);
    p.userId = TKStr(u[@"id"]) ?: TKStr(u[@"uid"]);
    return p;
}

+ (instancetype)profileFromJSON:(NSDictionary *)json
{
    TKProfile *p = [self profileFromUserJSON:TKDict(TKDict(json)[@"user"])];
    if (!p) return nil;
    NSMutableArray *videos = [NSMutableArray array];
    for (TKVideo *v in [TKVideo videosFromItems:TKArr(TKDict(json)[@"items"]) headers:TKDict(TKDict(json)[@"headers"])]) {
        // (yt-dlp's list names the author only by handle: the picture and the live room come from the profile)
        if (!v.author.length) v.author = p.handle;
        if (!v.authorAvatarURL.length) v.authorAvatarURL = p.avatarURL;
        if (!v.authorLiveRoom.length) v.authorLiveRoom = p.liveRoom;
        [videos addObject:v];
    }
    p.videos = videos;
    p.postsUnavailable = TKBool(json[@"postsUnavailable"]);
    p.postsCursor = (long long)TKDbl(TKDict(json)[@"cursor"]);
    p.hasMorePosts = TKBool(TKDict(json)[@"hasMore"]) && p.postsCursor > 0;
    return p;
}

@end

@implementation TKHashtag

+ (instancetype)hashtagFromJSON:(NSDictionary *)json
{
    NSDictionary *j = TKDict(json);
    if (!TKStr(j[@"name"]).length) return nil;
    TKHashtag *t = [[TKHashtag alloc] init];
    t.tagId = TKStr(j[@"id"]);
    t.name = TKStr(j[@"name"]);
    t.desc = TKStr(j[@"desc"]) ?: @"";
    t.videoCount = (long long)TKDbl(j[@"videos"]);
    t.viewCount = (long long)TKDbl(j[@"views"]);
    return t;
}

@end

@implementation TKSound

+ (instancetype)soundFromJSON:(NSDictionary *)json
{
    NSDictionary *j = TKDict(json);
    if (!TKStr(j[@"id"]).length) return nil;
    TKSound *s = [[TKSound alloc] init];
    s.soundId = TKStr(j[@"id"]);
    s.title = TKStr(j[@"title"]) ?: @"";
    s.author = TKStr(j[@"author"]) ?: @"";
    s.authorHandle = TKStr(j[@"authorHandle"]);
    s.coverURL = TKStr(j[@"cover"]);
    s.playURL = TKStr(j[@"playUrl"]);
    s.headers = TKDict(j[@"headers"]);
    s.durationSeconds = TKInt(j[@"duration"]);
    s.videoCount = (long long)TKDbl(j[@"videos"]);
    s.original = TKBool(j[@"original"]);
    return s;
}

@end

@implementation TKVideoPage

+ (instancetype)pageFromJSON:(NSDictionary *)json cursorKey:(NSString *)cursorKey
{
    NSDictionary *j = TKDict(json);
    if (!j) return nil;
    TKVideoPage *page = [[TKVideoPage alloc] init];
    page.videos = [TKVideo videosFromItems:TKArr(j[@"items"]) headers:TKDict(j[@"headers"])];
    NSMutableArray *users = [NSMutableArray array];
    for (id u in TKArr(j[@"users"])) { TKProfile *p = [TKProfile profileFromUserJSON:TKDict(u)]; if (p) [users addObject:p]; }
    page.users = users;
    page.cursor = (long long)TKDbl(j[cursorKey]);
    page.hasMore = TKBool(j[@"hasMore"]);
    page.hashtag = [TKHashtag hashtagFromJSON:TKDict(j[@"tag"])];
    page.sound = [TKSound soundFromJSON:TKDict(j[@"sound"])];
    return page;
}

@end

@implementation TKLiveRoom

+ (instancetype)roomFromJSON:(NSDictionary *)json
{
    NSDictionary *j = TKDict(json);
    if (!TKStr(j[@"room"]).length) return nil;
    TKLiveRoom *r = [[TKLiveRoom alloc] init];
    r.roomId = TKStr(j[@"room"]);
    r.live = TKBool(j[@"live"]);
    r.title = TKStr(j[@"title"]) ?: @"";
    r.viewers = TKInt(j[@"viewers"]);
    r.coverURL = TKStr(j[@"cover"]);
    NSDictionary *owner = TKDict(j[@"owner"]);
    r.ownerHandle = TKStr(owner[@"handle"]) ?: @"";
    r.ownerName = TKStr(owner[@"name"]) ?: @"";
    r.ownerAvatarURL = TKStr(owner[@"avatar"]);
    NSMutableArray *streams = [NSMutableArray array];
    for (id s in TKArr(j[@"streams"])) if ([s isKindOfClass:[NSDictionary class]]) [streams addObject:s];
    r.streams = streams;
    r.headers = TKDict(j[@"headers"]);
    return r;
}

@end
