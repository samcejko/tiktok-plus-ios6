#import <UIKit/UIKit.h>
#import "TKTikTok.h"
#import "TKHTTP.h"
#import "TKDirectClient.h"
#import "TKSettings.h"
#import "TKSession.h"
#import "TKUtils.h"
#import "TKCommon.h"

@implementation TKTikTok

+ (BOOL)configured { return YES; }

+ (NSString *)urlForPath:(NSString *)path query:(NSString *)query
{
    // Internal route identifiers, never network URLs. All data goes directly to TikTok.
    return query.length ? [NSString stringWithFormat:@"%@?%@", path, query] : path;
}

// Preserve the model/UI facade while the direct transport normalizes TikTok's responses.
+ (TKHTTPTask *)directGET:(NSString *)route completion:(TKJSONCompletion)completion
{
    NSRange q = [route rangeOfString:@"?"];
    NSString *path = q.location == NSNotFound ? route : [route substringToIndex:q.location];
    NSString *query = q.location == NSNotFound ? nil : [route substringFromIndex:q.location+1];
    return [TKDirectClient getPath:path query:query completion:completion];
}

+ (NSError *)notConfigured
{
    return TKMakeError(TKErrorAPI, L(@"Set the server address in Settings first."));
}

+ (void)checkHealth:(void (^)(BOOL, NSString *, NSError *))completion
{
    NSString *url = [self urlForPath:@"/health" query:nil];
    if (!url) { completion(NO, nil, [self notConfigured]); return; }
    [self directGET:url completion:^(id json, NSInteger status, NSError *error) {
        if (error) { completion(NO, nil, error); return; }
        BOOL ok = TKBool(TKDict(json)[@"ok"]);
        completion(ok, TKStr(TKDict(json)[@"ytdlp"]), ok ? nil : TKMakeError(TKErrorAPI, L(@"The server answered but is not healthy.")));
    }];
}

+ (TKHTTPTask *)discoverCategory:(NSInteger)category count:(NSInteger)count completion:(void (^)(NSArray *, NSError *))completion
{
    NSString *url = [self urlForPath:@"/discover" query:[NSString stringWithFormat:@"cat=%ld&count=%ld&%@", (long)category, (long)count, [self formatPreference]]];
    if (!url) { completion(nil, [self notConfigured]); return nil; }
    return [self directGET:url completion:^(id json, NSInteger status, NSError *error) {
        if (error) { completion(nil, error); return; }
        NSDictionary *batchHeaders = TKDict(TKDict(json)[@"headers"]);
        NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
        NSMutableArray *videos = [NSMutableArray array];
        for (NSDictionary *item in TKArr(TKDict(json)[@"items"])) {
            TKVideo *v = [TKVideo videoFromJSON:TKDict(item)];
            if (!v.playable) continue;
            if (!v.playHeaders) v.playHeaders = batchHeaders;   // the session cookies every URL of the batch plays with
            v.fetchedAt = now;
            [videos addObject:v];
        }
        completion(videos, nil);
    }];
}

+ (TKHTTPTask *)videosForCreator:(NSString *)handle count:(NSInteger)count completion:(void (^)(NSArray *, NSError *))completion
{
    NSString *h = [handle hasPrefix:@"@"] ? [handle substringFromIndex:1] : handle;
    NSString *url = [self urlForPath:@"/user" query:[NSString stringWithFormat:@"name=%@&count=%ld", [TKUtils urlEncode:h], (long)count]];
    if (!url) { completion(nil, [self notConfigured]); return nil; }
    return [self directGET:url completion:^(id json, NSInteger status, NSError *error) {
        if (error) { completion(nil, error); return; }
        NSMutableArray *videos = [NSMutableArray array];
        for (NSDictionary *item in TKArr(TKDict(json)[@"items"])) {
            TKVideo *v = [TKVideo videoFromJSON:TKDict(item)];
            if (v) [videos addObject:v];
        }
        completion(videos, nil);
    }];
}

+ (void)applyResolved:(NSDictionary *)json to:(TKVideo *)video
{
    TKVideo *r = [TKVideo videoFromJSON:json];
    if (!r) return;
    video.playURL = r.playURL;
    video.playHeaders = r.playHeaders;
    video.fetchedAt = [NSDate timeIntervalSinceReferenceDate];
    if (!video.tags.count && r.tags.count) video.tags = r.tags;
    if (r.width) video.width = r.width;
    if (r.height) video.height = r.height;
    if (r.durationSeconds) video.durationSeconds = r.durationSeconds;
    if (r.music.length) video.music = r.music;
    if (r.desc.length && !video.desc.length) video.desc = r.desc;
    if (r.author.length && !video.author.length) video.author = r.author;
    if (r.authorName.length && !video.authorName.length) video.authorName = r.authorName;
    if (r.coverURL.length && !video.coverURL.length) video.coverURL = r.coverURL;
    if (r.likes) video.likes = r.likes;
    if (r.commentCount) video.commentCount = r.commentCount;
    if (r.createdAt > 0) video.createdAt = r.createdAt;
    if (r.authorAvatarURL.length) video.authorAvatarURL = r.authorAvatarURL;
    if (r.authorLiveRoom.length) video.authorLiveRoom = r.authorLiveRoom;
    if (r.category && !video.category) video.category = r.category;
    if (r.lang.length && !video.lang.length) video.lang = r.lang;
    video.subtitles = r.subtitles;
    video.musicAuthor = r.musicAuthor;
    video.musicCoverURL = r.musicCoverURL;
    video.musicId = r.musicId;
    video.isPhoto = r.isPhoto;
    video.imageURLs = r.imageURLs;
    video.audioURL = r.audioURL;
}

// What this device can show: H.264 only (iOS 6 has no HEVC decoder) and no taller than its screen in pixels.
// A server that does not know these parameters ignores them.
+ (NSString *)formatPreference
{
    UIScreen *s = [UIScreen mainScreen];
    CGFloat longSide = MAX(s.bounds.size.width, s.bounds.size.height) * s.scale;
    return [NSString stringWithFormat:@"vcodec=h264&maxh=%ld", (long)longSide];
}

+ (TKHTTPTask *)resolveVideo:(TKVideo *)video completion:(void (^)(TKVideo *, NSError *))completion
{
    NSString *q = [NSString stringWithFormat:@"id=%@", [TKUtils urlEncode:video.videoId ?: @""]];
    if (video.author.length) q = [q stringByAppendingFormat:@"&user=%@", [TKUtils urlEncode:video.author]];
    q = [q stringByAppendingFormat:@"&%@", [self formatPreference]];
    NSString *url = [self urlForPath:@"/resolve" query:q];
    if (!url) { completion(nil, [self notConfigured]); return nil; }
    return [self directGET:url completion:^(id json, NSInteger status, NSError *error) {
        if (error) { completion(nil, error); return; }
        BOOL hasPictures = TKArr(TKDict(json)[@"images"]).count > 0;    // a photo post: pictures instead of a video
        if (!TKStr(TKDict(json)[@"playUrl"]).length && !hasPictures) { completion(nil, TKMakeError(TKErrorAPI, L(@"This video could not be loaded."))); return; }
        [self applyResolved:TKDict(json) to:video];
        completion(video, nil);
    }];
}

+ (TKHTTPTask *)resolveId:(NSString *)videoId author:(NSString *)author completion:(void (^)(TKVideo *, NSError *))completion
{
    TKVideo *v = [[TKVideo alloc] init];
    v.videoId = videoId;
    v.author = author;
    return [self resolveVideo:v completion:completion];
}

+ (TKHTTPTask *)commentsForVideo:(NSString *)videoId count:(NSInteger)count completion:(void (^)(NSArray *, NSError *))completion
{
    NSString *url = [self urlForPath:@"/comments" query:[NSString stringWithFormat:@"id=%@&count=%ld", [TKUtils urlEncode:videoId ?: @""], (long)count]];
    if (!url) { completion(nil, [self notConfigured]); return nil; }
    return [self directGET:url completion:^(id json, NSInteger status, NSError *error) {
        if (error) { completion(nil, error); return; }
        NSMutableArray *comments = [NSMutableArray array];
        for (NSDictionary *item in TKArr(TKDict(json)[@"items"])) {
            TKComment *c = [TKComment commentFromJSON:TKDict(item)];
            if (c.text.length) [comments addObject:c];
        }
        completion(comments, nil);
    }];
}

+ (TKHTTPTask *)repliesForVideo:(NSString *)videoId comment:(NSString *)commentId count:(NSInteger)count completion:(void (^)(NSArray *, NSError *))completion
{
    NSString *url = [self urlForPath:@"/replies" query:[NSString stringWithFormat:@"id=%@&cid=%@&count=%ld", [TKUtils urlEncode:videoId ?: @""],
                                                         [TKUtils urlEncode:commentId ?: @""], (long)count]];
    if (!url) { completion(nil, [self notConfigured]); return nil; }
    return [self directGET:url completion:^(id json, NSInteger status, NSError *error) {
        if (error) { completion(nil, error); return; }
        NSMutableArray *replies = [NSMutableArray array];
        for (NSDictionary *item in TKArr(TKDict(json)[@"items"])) {
            TKComment *c = [TKComment commentFromJSON:TKDict(item)];
            c.isReply = YES;
            if (c.text.length) [replies addObject:c];
        }
        completion(replies, nil);
    }];
}

+ (TKHTTPTask *)profileForUser:(NSString *)handle completion:(void (^)(TKProfile *, NSError *))completion
{
    NSString *h = [handle hasPrefix:@"@"] ? [handle substringFromIndex:1] : handle;
    NSString *url = [self urlForPath:@"/profile" query:[NSString stringWithFormat:@"name=%@&%@", [TKUtils urlEncode:h ?: @""], [self formatPreference]]];
    if (!url) { completion(nil, [self notConfigured]); return nil; }
    return [self directGET:url completion:^(id json, NSInteger status, NSError *error) {
        if (error) { completion(nil, error); return; }
        TKProfile *p = [TKProfile profileFromJSON:TKDict(json)];
        completion(p, p ? nil : TKMakeError(TKErrorBadResponse, L(@"This profile could not be loaded.")));
    }];
}

// One page of a list endpoint
+ (TKHTTPTask *)pageAt:(NSString *)path query:(NSString *)query cursorKey:(NSString *)cursorKey completion:(void (^)(TKVideoPage *, NSError *))completion
{
    NSString *url = [self urlForPath:path query:[NSString stringWithFormat:@"%@&%@", query, [self formatPreference]]];
    if (!url) { completion(nil, [self notConfigured]); return nil; }
    return [self directGET:url completion:^(id json, NSInteger status, NSError *error) {
        if (error) { completion(nil, error); return; }
        TKVideoPage *page = [TKVideoPage pageFromJSON:TKDict(json) cursorKey:cursorKey];
        completion(page, page ? nil : TKMakeError(TKErrorBadResponse, L(@"The server sent an invalid response.")));
    }];
}

+ (TKHTTPTask *)postsOf:(TKProfile *)profile cursor:(long long)cursor completion:(void (^)(TKVideoPage *, NSError *))completion
{
    NSString *q = [NSString stringWithFormat:@"sec=%@&cursor=%lld", [TKUtils urlEncode:profile.secUid ?: @""], cursor];
    return [self pageAt:@"/posts" query:q cursorKey:@"cursor" completion:^(TKVideoPage *page, NSError *error) {
        for (TKVideo *v in page.videos) {
            if (!v.authorAvatarURL.length) v.authorAvatarURL = profile.avatarURL;
            if (!v.authorLiveRoom.length) v.authorLiveRoom = profile.liveRoom;
        }
        completion(page, error);
    }];
}

+ (TKHTTPTask *)search:(NSString *)query offset:(long long)offset completion:(void (^)(TKVideoPage *, NSError *))completion
{
    NSString *q = [NSString stringWithFormat:@"q=%@&offset=%lld", [TKUtils urlEncode:query ?: @""], offset];
    return [self pageAt:@"/search" query:q cursorKey:@"offset" completion:completion];
}

+ (TKHTTPTask *)suggestionsFor:(NSString *)text completion:(void (^)(NSArray *, NSError *))completion
{
    NSString *url = [self urlForPath:@"/suggest" query:[NSString stringWithFormat:@"q=%@", [TKUtils urlEncode:text ?: @""]]];
    if (!url) { completion(nil, [self notConfigured]); return nil; }
    return [self directGET:url completion:^(id json, NSInteger status, NSError *error) {
        NSMutableArray *words = [NSMutableArray array];
        for (id w in TKArr(TKDict(json)[@"items"])) if (TKStr(w).length) [words addObject:TKStr(w)];
        completion(error ? nil : words, error);
    }];
}

+ (TKHTTPTask *)hashtag:(NSString *)name cursor:(long long)cursor completion:(void (^)(TKVideoPage *, NSError *))completion
{
    NSString *q = [NSString stringWithFormat:@"name=%@&cursor=%lld", [TKUtils urlEncode:name ?: @""], cursor];
    return [self pageAt:@"/tag" query:q cursorKey:@"cursor" completion:completion];
}

+ (TKHTTPTask *)sound:(NSString *)soundId cursor:(long long)cursor completion:(void (^)(TKVideoPage *, NSError *))completion
{
    NSString *q = [NSString stringWithFormat:@"id=%@&cursor=%lld", [TKUtils urlEncode:soundId ?: @""], cursor];
    return [self pageAt:@"/sound" query:q cursorKey:@"cursor" completion:completion];
}

+ (TKHTTPTask *)fetchText:(NSString *)url completion:(void (^)(NSString *, NSError *))completion
{
    if (!url.length) { completion(nil, TKMakeError(TKErrorBadResponse, L(@"Unexpected response format."))); return nil; }
    return [TKHTTP get:url headers:nil completion:^(NSInteger status, NSData *body, NSDictionary *headers, NSError *error) {
        NSString *text = (!error && status < 400 && body.length) ? [[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding] : nil;
        completion(text, text ? nil : (error ?: TKMakeError(status ?: TKErrorBadResponse, L(@"The server sent an invalid response."))));
    }];
}

+ (TKHTTPTask *)liveRoom:(NSString *)roomId completion:(void (^)(TKLiveRoom *, NSError *))completion
{
    NSString *url = [self urlForPath:@"/live" query:[NSString stringWithFormat:@"room=%@", [TKUtils urlEncode:roomId ?: @""]]];
    if (!url) { completion(nil, [self notConfigured]); return nil; }
    return [self directGET:url completion:^(id json, NSInteger status, NSError *error) {
        if (error) { completion(nil, error); return; }
        TKLiveRoom *r = [TKLiveRoom roomFromJSON:TKDict(json)];
        completion(r, r ? nil : TKMakeError(TKErrorBadResponse, L(@"This live stream could not be loaded.")));
    }];
}

+ (TKHTTPTask *)liveRooms:(void (^)(NSArray *, NSError *))completion
{
    NSString *url = [self urlForPath:@"/lives" query:@"count=30"];
    if (!url) { completion(nil, [self notConfigured]); return nil; }
    return [self directGET:url completion:^(id json, NSInteger status, NSError *error) {
        if (error) { completion(nil, error); return; }
        NSMutableArray *rooms = [NSMutableArray array];
        for (id item in TKArr(TKDict(json)[@"items"])) if (TKStr(TKDict(item)[@"room"]).length) [rooms addObject:item];
        completion(rooms, nil);
    }];
}

+ (TKHTTPTask *)expandLink:(NSString *)link completion:(void (^)(NSString *, NSError *))completion
{
    NSString *url = [self urlForPath:@"/expand" query:[NSString stringWithFormat:@"u=%@", [TKUtils urlEncode:link ?: @""]]];
    if (!url) { completion(nil, [self notConfigured]); return nil; }
    return [self directGET:url completion:^(id json, NSInteger status, NSError *error) {
        completion(error ? nil : TKStr(TKDict(json)[@"url"]), error);
    }];
}

+ (NSString *)proxyURLForPlayURL:(NSString *)playURL
{
    return nil; // On-device media proxy handles TLS; no remote helper is required.
}

+ (NSDictionary *)sessionHeaders
{
    NSString *token = [TKSession sharedSession].token;
    if (token.length) {
        return @{ @"X-Tikie-Session": token };
    }
    return nil;
}

+ (TKHTTPTask *)sessionCreateWithCookies:(NSString *)cookieData completion:(void (^)(BOOL, NSString *, NSDictionary *, NSError *))completion
{
    return [TKDirectClient importCookies:cookieData completion:completion];
}

+ (TKHTTPTask *)sessionValidateWithCompletion:(void (^)(BOOL, NSDictionary *, NSError *))completion
{
    return [TKDirectClient validate:completion];
}

+ (TKHTTPTask *)sessionDeleteWithCompletion:(void (^)(BOOL))completion
{
    [TKDirectClient signOut];
    if (completion) completion(YES);
    return nil;
}


+ (TKHTTPTask *)myProfileWithCompletion:(void (^)(TKProfile *, NSError *))completion
{
    TKSession *session=[TKSession sharedSession];NSString *uid=session.userId,*token=session.token;
    if (!session.signedIn) { if(completion)completion(nil,TKMakeError(TKErrorAuth,L(@"Sign in")));return nil; }
    return [self profileForUser:session.handle completion:^(TKProfile *profile,NSError *error){
        if (![session.token isEqualToString:token] || ![profile.userId isEqualToString:uid]) { if(completion)completion(nil,error ?: TKMakeError(TKErrorAuth,L(@"The verified account and profile do not match. Export fresh TikTok cookies.")));return; }
        if(completion)completion(profile,error);
    }];
}

+ (TKHTTPTask *)followingFeedWithCount:(NSInteger)count completion:(void (^)(NSArray *, NSError *))completion
{
    NSString *url = [self urlForPath:@"/following" query:[NSString stringWithFormat:@"count=%ld&%@", (long)count, [self formatPreference]]];
    if (!url) { if (completion) completion(nil, [self notConfigured]); return nil; }
    return [self directGET:url completion:^(id json, NSInteger status, NSError *error) {
        if (error) { if (completion) completion(nil, error); return; }
        NSDictionary *batchHeaders = TKDict(TKDict(json)[@"headers"]);
        NSArray *items = TKArr(TKDict(json)[@"items"]);
        NSArray *videos = [TKVideo videosFromItems:items headers:batchHeaders];
        if (completion) completion(videos, nil);
    }];
}

+ (TKHTTPTask *)personalFeedWithCount:(NSInteger)count completion:(void (^)(NSArray *, NSError *))completion
{
    NSString *url = [self urlForPath:@"/foryou" query:[NSString stringWithFormat:@"count=%ld&%@", (long)count, [self formatPreference]]];
    if (!url) { if (completion) completion(nil, [self notConfigured]); return nil; }
    return [self directGET:url completion:^(id json, NSInteger status, NSError *error) {
        if (error) { if (completion) completion(nil, error); return; }
        NSDictionary *batchHeaders = TKDict(TKDict(json)[@"headers"]);
        NSArray *items = TKArr(TKDict(json)[@"items"]);
        NSArray *videos = [TKVideo videosFromItems:items headers:batchHeaders];
        if (completion) completion(videos, nil);
    }];
}

+ (TKHTTPTask *)likedVideosWithCount:(NSInteger)count completion:(void (^)(NSArray *, NSError *))completion
{
    NSString *url = [self urlForPath:@"/liked" query:[NSString stringWithFormat:@"count=%ld&%@", (long)count, [self formatPreference]]];
    if (!url) { if (completion) completion(nil, [self notConfigured]); return nil; }
    return [self directGET:url completion:^(id json, NSInteger status, NSError *error) {
        if (error) { if (completion) completion(nil, error); return; }
        NSDictionary *batchHeaders = TKDict(TKDict(json)[@"headers"]);
        NSArray *items = TKArr(TKDict(json)[@"items"]);
        NSArray *videos = [TKVideo videosFromItems:items headers:batchHeaders];
        if (completion) completion(videos, nil);
    }];
}

+ (TKHTTPTask *)notificationsWithCount:(NSInteger)count completion:(void (^)(NSArray *, NSError *))completion
{
    NSString *url = [self urlForPath:@"/notifications" query:[NSString stringWithFormat:@"count=%ld", (long)count]];
    if (!url) { if (completion) completion(nil, [self notConfigured]); return nil; }
    return [self directGET:url completion:^(id json, NSInteger status, NSError *error) {
        if (error) { if (completion) completion(nil, error); return; }
        NSArray *items = TKArr(TKDict(json)[@"items"]);
        if (completion) completion(items, nil);
    }];
}

// TikTok's current web write protocol is not verified on these devices. Keep this explicit.
+ (TKHTTPTask *)diggVideoId:(NSString *)videoId type:(NSInteger)type completion:(void (^)(BOOL, NSError *))completion
{
    if (completion) completion(NO, TKMakeError(TKErrorAPI, L(@"Account actions are not available in this version.")));
    return nil;
}
+ (TKHTTPTask *)followUserId:(NSString *)userId secUid:(NSString *)secUid type:(NSInteger)type completion:(void (^)(BOOL, NSError *))completion
{
    if (completion) completion(NO, TKMakeError(TKErrorAPI, L(@"Account actions are not available in this version.")));
    return nil;
}
+ (TKHTTPTask *)postCommentOnVideoId:(NSString *)videoId text:(NSString *)text completion:(void (^)(BOOL, NSDictionary *, NSError *))completion
{
    if (completion) completion(NO, nil, TKMakeError(TKErrorAPI, L(@"Account actions are not available in this version.")));
    return nil;
}
@end
