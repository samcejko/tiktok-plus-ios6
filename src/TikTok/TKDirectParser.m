#import "TKDirectParser.h"
#import "TKCommon.h"

@implementation TKDirectParser

+ (NSString *)URLString:(id)value
{
    if ([value isKindOfClass:[NSDictionary class]]) value = value[@"urlList"] ?: value[@"url_list"];
    if ([value isKindOfClass:[NSArray class]]) {
        // Legacy ImageIO cannot decode WebP/AVIF. Prefer an actual JPEG alternative.
        for (id s in value) if ([s isKindOfClass:[NSString class]] &&
            ([s rangeOfString:@".jpg"].location != NSNotFound || [s rangeOfString:@".jpeg"].location != NSNotFound)) return [self URLString:s];
        for (id s in value) { NSString *u = [self URLString:s]; if (u.length) return u; }
        return @"";
    }
    NSString *s = TKStr(value);
    NSURL *u = s.length ? [NSURL URLWithString:s] : nil;
    return [u.scheme.lowercaseString isEqualToString:@"https"] && u.host.length ? s : @"";
}

+ (NSDictionary *)scopeFromHTML:(NSString *)html
{
    if (!html.length) return nil;
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"<script\\b[^>]*\\bid=[\"']__UNIVERSAL_DATA_FOR_REHYDRATION__[\"'][^>]*>([\\s\\S]*?)</script>" options:0 error:nil];
    NSTextCheckingResult *m = [re firstMatchInString:html options:0 range:NSMakeRange(0, html.length)];
    if (!m) return nil;
    NSData *data = [[html substringWithRange:[m rangeAtIndex:1]] dataUsingEncoding:NSUTF8StringEncoding];
    return TKDict(TKDict([NSJSONSerialization JSONObjectWithData:data options:0 error:nil])[@"__DEFAULT_SCOPE__"]);
}

+ (BOOL)successfulResponse:(NSDictionary *)response
{
    if (!TKDict(response).count) return NO;
    BOOL hasStatus = NO;
    for (NSString *key in @[@"status_code", @"statusCode"]) {
        id n = response[key];
        if (n) { if (![n isKindOfClass:[NSNumber class]] || [n longLongValue] != 0) return NO; hasStatus = YES; }
    }
    return hasStatus;
}

+ (NSDictionary *)video:(NSDictionary *)item maxHeight:(NSInteger)height
{
    NSDictionary *it = TKDict(item), *a = TKDict(it[@"author"]), *v = TKDict(it[@"video"]), *music = TKDict(it[@"music"]);
    NSString *vid = TKStr(it[@"id"]);
    if (!vid.length || [vid rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location != NSNotFound) return nil;
    NSDictionary *st = TKDict(it[@"statsV2"]) ?: TKDict(it[@"stats"]);
    NSMutableArray *tags = [NSMutableArray array], *subs = [NSMutableArray array], *images = [NSMutableArray array];
    for (id e in TKArr(it[@"textExtra"])) { NSString *s = TKStr(TKDict(e)[@"hashtagName"]); if (s.length) [tags addObject:s.lowercaseString]; }
    for (id e in TKArr(it[@"challenges"])) { NSString *s = TKStr(TKDict(e)[@"title"]); if (s.length && ![tags containsObject:s.lowercaseString]) [tags addObject:s.lowercaseString]; }
    for (id e in TKArr(v[@"subtitleInfos"])) {
        NSDictionary *d = TKDict(e); NSString *u = [self URLString:d[@"Url"]];
        if (u.length && (!TKStr(d[@"Format"]).length || [TKStr(d[@"Format"]).lowercaseString isEqualToString:@"webvtt"]))
            [subs addObject:@{@"url":u, @"lang":TKStr(d[@"LanguageCodeName"]) ?: @"", @"source":TKStr(d[@"Source"]) ?: @""}];
    }
    for (id e in TKArr(TKDict(it[@"imagePost"])[@"images"])) {
        NSString *u = [self URLString:TKDict(TKDict(e)[@"imageURL"])]; if (u.length) [images addObject:u];
    }
    NSMutableDictionary *out = [@{@"id":vid, @"author":TKStr(a[@"uniqueId"]) ?: @"", @"authorName":TKStr(a[@"nickname"]) ?: @"",
        @"desc":TKStr(it[@"desc"]) ?: @"", @"cover":[self URLString:v[@"cover"] ?: v[@"originCover"]],
        @"url":[NSString stringWithFormat:@"https://www.tiktok.com/@%@/video/%@", TKStr(a[@"uniqueId"]) ?: @"_", vid],
        @"authorAvatar":[self URLString:a[@"avatarMedium"] ?: a[@"avatarThumb"]], @"authorLive":TKStr(a[@"roomId"]) ?: @"",
        @"likes":st[@"diggCount"] ?: @0, @"comments":st[@"commentCount"] ?: @0, @"plays":st[@"playCount"] ?: @0,
        @"created":it[@"createTime"] ?: @0, @"duration":v[@"duration"] ?: @0, @"category":it[@"CategoryType"] ?: @0,
        @"lang":TKStr(it[@"textLanguage"]) ?: @"un", @"tags":tags, @"subtitles":subs,
        @"music":TKStr(music[@"title"]) ?: @"", @"musicId":TKStr(music[@"id"]) ?: @"", @"musicOriginal":music[@"original"] ?: @NO,
        @"musicAuthor":TKStr(music[@"authorName"]) ?: @"", @"musicCover":[self URLString:music[@"coverMedium"] ?: music[@"coverThumb"]]} mutableCopy];
    if (images.count) {
        out[@"type"] = @"photo"; out[@"images"] = images; out[@"musicUrl"] = [self URLString:music[@"playUrl"]];
        if (![out[@"cover"] length]) out[@"cover"] = images[0];
        return out;
    }
    NSDictionary *best = nil; NSInteger bestHeight = 0; BOOL bestFits = NO;
    NSMutableArray *formats = [TKArr(v[@"bitrateInfo"]) mutableCopy] ?: [NSMutableArray array];
    NSDictionary *fallback = TKDict(v[@"PlayAddrStruct"]);
    // Only use a fallback whose codec is explicitly identified. HEVC fails on iOS 6.
    if (TKStr(fallback[@"UrlKey"]).length && [TKStr(fallback[@"UrlKey"]).lowercaseString rangeOfString:@"h264"].location != NSNotFound)
        [formats addObject:@{@"CodecType":@"h264", @"PlayAddr":fallback}];
    for (id e in formats) {
        NSDictionary *f = TKDict(e), *addr = TKDict(f[@"PlayAddr"]);
        if (![TKStr(f[@"CodecType"]).lowercaseString isEqualToString:@"h264"]) continue;
        if (![self URLString:addr[@"UrlList"]].length) continue;
        NSInteger h = MAX(TKInt(addr[@"Height"]), TKInt(addr[@"Width"])); BOOL fits = h > 0 && h <= MAX(height, 480);
        if (!best || (fits && !bestFits) || (fits == bestFits && (fits ? h > bestHeight : h < bestHeight))) { best=addr; bestHeight=h; bestFits=fits; }
    }
    if (!best) return nil;
    out[@"type"] = @"video"; out[@"playUrl"] = [self URLString:best[@"UrlList"]];
    out[@"width"] = best[@"Width"] ?: @0; out[@"height"] = best[@"Height"] ?: @0;
    return out;
}

+ (NSDictionary *)profile:(NSDictionary *)info
{
    NSDictionary *u = TKDict(info[@"user"]), *s = TKDict(info[@"statsV2"]) ?: TKDict(info[@"stats"]);
    if (!TKStr(u[@"uniqueId"]).length || !TKStr(u[@"id"]).length) return nil;
    return @{@"handle":u[@"uniqueId"], @"id":u[@"id"], @"secUid":TKStr(u[@"secUid"]) ?: @"", @"name":TKStr(u[@"nickname"]) ?: @"",
        @"bio":TKStr(u[@"signature"]) ?: @"", @"avatar":[self URLString:u[@"avatarLarger"] ?: u[@"avatarMedium"]],
        @"verified":u[@"verified"] ?: @NO, @"private":u[@"privateAccount"] ?: @NO, @"liveRoom":TKStr(u[@"roomId"]) ?: @"",
        @"followers":s[@"followerCount"] ?: @0, @"following":s[@"followingCount"] ?: @0, @"likes":s[@"heartCount"] ?: s[@"heart"] ?: @0,
        @"videos":s[@"videoCount"] ?: @0, @"link":[self URLString:TKDict(u[@"bioLink"])[@"link"]]};
}

+ (NSDictionary *)comment:(NSDictionary *)item
{
    NSDictionary *c = TKDict(item), *u = TKDict(c[@"user"]);
    if (!TKStr(c[@"cid"]).length || !TKStr(c[@"text"]).length) return nil;
    return @{@"cid":c[@"cid"], @"text":c[@"text"], @"author":TKStr(u[@"unique_id"]) ?: @"", @"authorName":TKStr(u[@"nickname"]) ?: @"",
        @"avatar":[self URLString:u[@"avatar_thumb"]], @"time":c[@"create_time"] ?: @0, @"likes":c[@"digg_count"] ?: @0,
        @"replies":c[@"reply_comment_total"] ?: @0, @"pinned":c[@"author_pin"] ?: @NO};
}

+ (NSArray *)cookiesFromString:(NSString *)input error:(NSError **)error
{
    NSMutableArray *raw = [NSMutableArray array], *cookies = [NSMutableArray array];
    if (input.length > 1024*1024) goto invalid;
    {
        id json = [NSJSONSerialization JSONObjectWithData:[input dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        if ([json isKindOfClass:[NSDictionary class]] && [json[@"cookies"] isKindOfClass:[NSArray class]]) json = json[@"cookies"];
        if ([json isKindOfClass:[NSArray class]]) [raw addObjectsFromArray:json];
        else if ([json isKindOfClass:[NSDictionary class]]) {
            for (NSString *key in json) if ([json[key] isKindOfClass:[NSString class]]) [raw addObject:@{@"name":key, @"value":json[key]}];
        } else if ([input rangeOfString:@"\t"].location != NSNotFound) {
            for (NSString *line in [input componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
                NSString *s = [line hasPrefix:@"#HttpOnly_"] ? [line substringFromIndex:10] : line;
                if ([s hasPrefix:@"#"] || !s.length) continue;
                NSArray *f = [s componentsSeparatedByString:@"\t"]; if (f.count != 7) goto invalid;
                [raw addObject:@{@"domain":f[0], @"path":f[2], @"expirationDate":@([f[4] doubleValue]), @"name":f[5], @"value":f[6]}];
            }
        } else {
            NSString *s = [input hasPrefix:@"Cookie:"] ? [input substringFromIndex:7] : input;
            for (NSString *pair in [s componentsSeparatedByString:@";"]) {
                NSRange eq = [pair rangeOfString:@"="]; if (eq.location == NSNotFound) goto invalid;
                [raw addObject:@{@"name":[[pair substringToIndex:eq.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]],
                    @"value":[[pair substringFromIndex:eq.location+1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]}];
            }
        }
        BOOL hasSession = NO; NSMutableSet *keys = [NSMutableSet set];
        for (id entry in raw) {
            NSDictionary *d = TKDict(entry); if (!d) goto invalid;
            NSString *n = TKStr(d[@"name"]), *v = TKStr(d[@"value"]), *domain = TKStr(d[@"domain"]) ?: @".tiktok.com", *path = TKStr(d[@"path"]) ?: @"/";
            NSString *host = domain.lowercaseString; if ([host hasPrefix:@"."]) host = [host substringFromIndex:1];
            if (![host isEqualToString:@"tiktok.com"] && ![host hasSuffix:@".tiktok.com"]) continue;
            if (!n.length || !v.length || n.length > 256 || v.length > 16384 || ![path hasPrefix:@"/"]) goto invalid;
            NSCharacterSet *badName = [NSCharacterSet characterSetWithCharactersInString:@"\r\n\t ;=,\"\\"];
            NSCharacterSet *badValue = [NSCharacterSet characterSetWithCharactersInString:@"\r\n\t;\x00"];
            if ([n rangeOfCharacterFromSet:badName].location != NSNotFound || [v rangeOfCharacterFromSet:badValue].location != NSNotFound) goto invalid;
            NSTimeInterval expiry = TKDbl(d[@"expirationDate"] ?: d[@"expires"]);
            if (expiry > 0 && expiry < [[NSDate date] timeIntervalSince1970]) continue;
            NSString *key = [NSString stringWithFormat:@"%@|%@|%@", host, path, n];
            if ([keys containsObject:key]) goto invalid; [keys addObject:key];
            NSMutableDictionary *props = [@{NSHTTPCookieName:n, NSHTTPCookieValue:v, NSHTTPCookieDomain:domain, NSHTTPCookiePath:path, NSHTTPCookieSecure:@"TRUE"} mutableCopy];
            if (expiry > 0) props[NSHTTPCookieExpires] = [NSDate dateWithTimeIntervalSince1970:expiry];
            NSHTTPCookie *c = [NSHTTPCookie cookieWithProperties:props]; if (!c) goto invalid;
            [cookies addObject:c];
            if ([n isEqualToString:@"sessionid"] || [n isEqualToString:@"sessionid_ss"] || [n isEqualToString:@"sid_tt"]) hasSession = YES;
        }
        if (hasSession && cookies.count <= 300) return cookies;
    }
invalid:
    if (error) *error = TKMakeError(TKErrorAPI, L(@"Invalid or expired TikTok cookies. Export cookies for tiktok.com while signed in."));
    return nil;
}

+ (NSDictionary *)verifiedAccount:(NSDictionary *)response cookies:(NSArray *)cookies
{
    NSDictionary *r = TKDict(response), *d = TKDict(r[@"data"]);
    // Public hydration/profile data is never authentication evidence.
    if (![TKStr(r[@"message"]) isEqualToString:@"success"] || TKInt(d[@"error_code"]) != 0) return nil;
    NSString *uid = TKStr(d[@"user_id_str"]) ?: TKStr(d[@"user_id"]), *handle = TKStr(d[@"username"]);
    if (!uid.length || !handle.length) return nil;
    for (NSHTTPCookie *c in cookies) if (([c.name isEqualToString:@"uid_tt"] || [c.name isEqualToString:@"uid_tt_ss"]) && ![c.value isEqualToString:uid]) return nil;
    return @{@"userId":uid, @"handle":handle, @"name":TKStr(d[@"screen_name"]) ?: handle,
        @"avatar":[self URLString:d[@"avatar_url"]], @"secUid":TKStr(d[@"sec_user_id"]) ?: @""};
}
@end
