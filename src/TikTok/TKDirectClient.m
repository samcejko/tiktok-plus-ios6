#import "TKDirectClient.h"
#import "TKDirectParser.h"
#import "TKAccountAction.h"
#import "TKWebSignature.h"
#import "TKKeychain.h"
#import "TKSession.h"
#import "TKUtils.h"
#import "TKCommon.h"

static NSString * const TKDirectKey = @"direct.session.v1";
static NSString * const TKWebUA = @"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";

@interface TKDirectClient ()
@property (nonatomic, strong) NSMutableArray *anonymousCookies;
@property (nonatomic, strong) NSMutableArray *accountCookies;
@property (nonatomic, strong) NSDictionary *session;
@property (nonatomic, strong) NSDictionary *webContext;
@property (nonatomic, strong) TKHTTPTask *warmTask;
@property (nonatomic, strong) NSMutableArray *warmWaiters;
@property (nonatomic, strong) NSMutableDictionary *pending;
@property (nonatomic, strong) NSMutableDictionary *liveAuthors;
@property (nonatomic, strong) NSMutableSet *activeWrites;
@property (nonatomic, strong) NSDictionary *lastAction;
@end

@implementation TKDirectClient
+ (instancetype)shared
{
    static TKDirectClient *client; static dispatch_once_t once;
    dispatch_once(&once, ^{
        client = [[self alloc] init]; client.anonymousCookies = [NSMutableArray array]; client.pending = [NSMutableDictionary dictionary];
        client.liveAuthors = [NSMutableDictionary dictionary]; client.warmWaiters=[NSMutableArray array]; client.activeWrites=[NSMutableSet set];
        NSString *saved = [[NSUserDefaults standardUserDefaults] boolForKey:@"direct.signedOut"] ? nil : [TKKeychain secureStringForKey:TKDirectKey];
        NSDictionary *d = TKDict([TKUtils JSONObjectFromData:[saved dataUsingEncoding:NSUTF8StringEncoding]]);
        NSError *error = nil; NSArray *jar = [TKDirectParser cookiesFromString:TKStr(d[@"cookies"]) ?: @"" error:&error];
        if (jar.count && TKStr(d[@"token"]).length && TKStr(TKDict(d[@"user"])[@"userId"]).length && TKStr(TKDict(d[@"user"])[@"handle"]).length) {
            client.session=d; client.accountCookies=[jar mutableCopy];
        }
    });
    return client;
}
+ (NSError *)unavailable { return TKMakeError(TKErrorAPI, L(@"TikTok did not provide this content. Try again later or open the link in a browser.")); }
+ (NSString *)query:(NSDictionary *)params
{
    NSMutableArray *a = [NSMutableArray array];
    for (NSString *key in [[params allKeys] sortedArrayUsingSelector:@selector(compare:)])
        [a addObject:[NSString stringWithFormat:@"%@=%@", [TKUtils urlEncode:key], [TKUtils urlEncode:[params[key] description]]]];
    return [a componentsJoinedByString:@"&"];
}
+ (BOOL)tiktokHost:(NSString *)host
{
    NSString *h = host.lowercaseString;
    return [h isEqualToString:@"tiktok.com"] || [h hasSuffix:@".tiktok.com"];
}
+ (NSString *)cookieHeader:(NSArray *)jar URL:(NSURL *)url
{
    NSMutableArray *a = [NSMutableArray array];
    for (NSHTTPCookie *c in jar) {
        NSString *domain = c.domain.lowercaseString; BOOL sub = [domain hasPrefix:@"."];
        if (sub) domain = [domain substringFromIndex:1];
        BOOL hostMatches = [url.host.lowercaseString isEqualToString:domain] || (sub && [url.host.lowercaseString hasSuffix:[@"." stringByAppendingString:domain]]);
        NSString *path = url.path.length ? url.path : @"/";
        BOOL pathMatches = [path isEqualToString:c.path] || ([path hasPrefix:c.path] && ([c.path hasSuffix:@"/"] || (path.length > c.path.length && [path characterAtIndex:c.path.length]=='/')));
        if (hostMatches && pathMatches && (!c.expiresDate || [c.expiresDate timeIntervalSinceNow] > 0)) [a addObject:c];
    }
    [a sortUsingComparator:^NSComparisonResult(NSHTTPCookie *x, NSHTTPCookie *y) { return x.path.length > y.path.length ? NSOrderedAscending : (x.path.length < y.path.length ? NSOrderedDescending : NSOrderedSame); }];
    NSMutableArray *pairs = [NSMutableArray array];
    for (NSHTTPCookie *c in a) [pairs addObject:[NSString stringWithFormat:@"%@=%@", c.name,c.value]];
    return [pairs componentsJoinedByString:@"; "];
}
+ (void)mergeCookies:(NSArray *)values URL:(NSURL *)url jar:(NSMutableArray *)jar
{
    if (![self tiktokHost:url.host]) return;
    for (NSString *value in values) for (NSHTTPCookie *c in [NSHTTPCookie cookiesWithResponseHeaderFields:@{@"Set-Cookie":value} forURL:url]) {
        NSString *d = c.domain.lowercaseString; if ([d hasPrefix:@"."]) d=[d substringFromIndex:1];
        if (![self tiktokHost:d] || !([url.host.lowercaseString isEqualToString:d] || [url.host.lowercaseString hasSuffix:[@"." stringByAppendingString:d]])) continue;
        for (NSInteger i=(NSInteger)jar.count-1;i>=0;i--) { NSHTTPCookie *old=jar[(NSUInteger)i];
            if ([old.name isEqualToString:c.name] && [old.domain isEqualToString:c.domain] && [old.path isEqualToString:c.path]) [jar removeObjectAtIndex:(NSUInteger)i]; }
        if (!c.expiresDate || [c.expiresDate timeIntervalSinceNow]>0) [jar addObject:c];
    }
}
+ (TKHTTPTask *)requestURL:(NSString *)url jar:(NSMutableArray *)jar completion:(void (^)(id, NSDictionary *, NSError *))completion
{
    NSURL *u = [NSURL URLWithString:url];
    if (![self tiktokHost:u.host] || ![u.scheme.lowercaseString isEqualToString:@"https"]) {
        TKHTTPTask *t=[[TKHTTPTask alloc] init]; dispatch_async(dispatch_get_main_queue(), ^{ if (!t.isCancelled) completion(nil,nil,[self unavailable]); }); return t;
    }
    NSMutableDictionary *h=[@{@"User-Agent":TKWebUA, @"Referer":@"https://www.tiktok.com/", @"Accept-Language":@"en-US,en;q=0.9"} mutableCopy];
    NSString *cookie=[self cookieHeader:jar URL:u]; if (cookie.length) h[@"Cookie"]=cookie;
    return [TKHTTP request:@"GET" url:url headers:h body:nil retries:0 completion:^(NSInteger status, NSData *body, NSDictionary *headers, NSError *error) {
        NSURL *final = [NSURL URLWithString:TKStr(headers[@"tk-final-url"]) ?: url];
        if (!error) [self mergeCookies:TKArr(headers[@"tk-set-cookie"]) URL:final jar:jar];
        if (error || status < 200 || status >= 300 || ![self tiktokHost:final.host]) { completion(nil,headers,error ?: TKMakeError(status,[self unavailable].localizedDescription)); return; }
        if (!body.length || body.length > 12*1024*1024) { completion(nil,headers,[self unavailable]); return; }
        id json=[TKUtils JSONObjectFromData:body];
        if (!json) { json=[self scopeFromBody:body]; NSDictionary *context=TKDict(TKDict(json)[@"webapp.app-context"]); if (context.count) [self shared].webContext=context; }
        completion(json,headers,json ? nil : [self unavailable]);
    }];
}
+ (NSDictionary *)scopeFromBody:(NSData *)body { return [TKDirectParser scopeFromHTML:[[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding]]; }
+ (void)addDeviceParameters:(NSMutableDictionary *)q context:(NSDictionary *)ctx jar:(NSArray *)jar
{
    [q addEntriesFromDictionary:@{@"aid":@"1988",@"app_name":@"tiktok_web",@"device_platform":@"web_pc",@"language":@"en",@"app_language":@"en",@"browser_language":@"en-US",@"browser_name":@"Mozilla",@"browser_online":@"true",@"browser_platform":@"Win32",@"browser_version":[TKWebUA substringFromIndex:8],@"channel":@"tiktok_web",@"cookie_enabled":@"true",@"focus_state":@"true",@"history_len":@"1",@"is_fullscreen":@"false",@"is_page_visible":@"true",@"os":@"windows",@"priority_region":@"",@"referer":@"",@"region":TKStr(ctx[@"region"]) ?: @"CZ",@"screen_height":@"1080",@"screen_width":@"1920",@"tz_name":@"Europe/Prague",@"webcast_language":@"en",@"data_collection_enabled":@"true",@"user_is_login":[self shared].accountCookies.count ? @"true" : @"false"}];
    for (NSString *key in @[@"wid",@"odinId",@"webIdCreatedTime"]) {
        NSString *value=TKStr(ctx[key]); if (value.length) q[[@{@"wid":@"device_id",@"odinId":@"odinId",@"webIdCreatedTime":@"WebIdLastTime"} objectForKey:key]]=value;
    }
    for (NSHTTPCookie *cookie in jar) {
        if (cookie.expiresDate && [cookie.expiresDate timeIntervalSinceNow]<=0) continue;
        if ([cookie.name isEqualToString:@"msToken"]) q[@"msToken"]=cookie.value;
        if ([cookie.name isEqualToString:@"s_v_web_id"]) { q[@"verifyFp"]=cookie.value; q[@"fp"]=cookie.value; }
    }
}
+ (NSDictionary *)actionDiagnostics { return [self shared].lastAction ?: @{}; }
+ (TKHTTPTask *)checkActionReadiness:(void (^)(NSDictionary *))completion
{
    TKHTTPTask *outer=[[TKHTTPTask alloc] init]; __block TKHTTPTask *part=nil;
    TKDirectClient *c=[self shared]; NSString *token=TKStr(c.session[@"token"]);
    outer.cancelBlock=^{[part cancel];};
    part=[self validate:^(BOOL valid,NSDictionary *user,NSError *error){
        if(outer.isCancelled)return;
        if(!valid) { outer.cancelBlock=nil; completion(@{@"verified":@NO,@"errorCode":@(error.code)}); return; }
        NSMutableArray *jar=[c.accountCookies mutableCopy];
        part=[self requestURL:@"https://www.tiktok.com/explore" jar:jar completion:^(id scope,NSDictionary *h,NSError *pageError){
            if(outer.isCancelled)return; outer.cancelBlock=nil;
            NSDictionary *ctx=TKDict(TKDict(scope)[@"webapp.app-context"]); NSString *csrf=TKStr(ctx[@"csrfToken"]);
            if(!csrf.length)for(NSString *pair in [[self cookieHeader:jar URL:[NSURL URLWithString:@"https://www.tiktok.com/"]] componentsSeparatedByString:@"; "])if([pair hasPrefix:@"tt_csrf_token="]) { csrf=[pair substringFromIndex:14]; break; }
            BOOL same=[token isEqualToString:TKStr(c.session[@"token"])];
            BOOL contextMatches=!TKStr(TKDict(ctx[@"user"])[@"uid"]).length || [TKStr(TKDict(ctx[@"user"])[@"uid"]) isEqualToString:TKStr(user[@"userId"])];
            completion(@{@"verified":@(same),@"contextMatches":@(contextMatches),@"csrfAvailable":@(csrf.length>0),@"deviceContextAvailable":@(TKStr(ctx[@"wid"]).length>0),@"pageErrorCode":@(pageError.code),@"writesSent":@0});
        }];
    }]; return outer;
}

+ (TKHTTPTask *)performAction:(NSString *)action parameters:(NSDictionary *)parameters completion:(TKJSONCompletion)completion
{
    TKDirectClient *c=[self shared]; NSDictionary *spec=[TKAccountAction request:action parameters:parameters];
    NSString *token=TKStr(c.session[@"token"]), *uid=TKStr(TKDict(c.session[@"user"])[@"userId"]);
    NSError *invalid=nil;
    if (!spec) invalid=TKMakeError(TKErrorAPI,L(@"Invalid account action or comment. Comments can contain up to 2200 characters."));
    else if (!token.length || !uid.length || !c.accountCookies.count) invalid=TKMakeError(TKErrorAuth,L(@"Sign in to use TikTok account actions."));
    else if ([action isEqualToString:@"deleteComment"] && ![TKStr(parameters[@"owner"]) isEqualToString:uid]) invalid=TKMakeError(TKErrorAuth,L(@"Only your own comments can be deleted."));
    else if ([action isEqualToString:@"follow"] && [TKStr(parameters[@"user"]) isEqualToString:uid]) invalid=TKMakeError(TKErrorAPI,L(@"You cannot follow your own account."));
    NSString *lock=[NSString stringWithFormat:@"%@:%@:%@",token,action,spec[@"target"]];
    if (!invalid && [c.activeWrites containsObject:lock]) invalid=TKMakeError(TKErrorAPI,L(@"This action is already being sent."));
    if (invalid) return [self immediate:nil error:invalid completion:completion];
    [c.activeWrites addObject:lock];
    TKHTTPTask *outer=[[TKHTTPTask alloc] init]; __block TKHTTPTask *part=nil;
    // Cancel never retries or undoes an already transmitted POST.
    outer.cancelBlock=^{ [part cancel]; [c.activeWrites removeObject:lock]; };
    BOOL (^sameSession)(void)=^BOOL{ return [TKStr(c.session[@"token"]) isEqualToString:token]; };
    void (^finish)(id,NSError *)=^(id result,NSError *error){
        [c.activeWrites removeObject:lock]; if (outer.isCancelled) return; outer.cancelBlock=nil;
        if (!sameSession()) { completion(nil,0,TKMakeError(TKErrorCancelled,L(@"Session changed."))); return; }
        completion(result,error ? 0 : 200,error);
    };
    part=[self validate:^(BOOL valid,NSDictionary *user,NSError *error){
        if (outer.isCancelled) return;
        if (!sameSession() || !valid || ![TKStr(user[@"userId"]) isEqualToString:uid]) { finish(nil,error ?: TKMakeError(TKErrorAuth,L(@"TikTok could not verify this session. Export fresh cookies while signed in."))); return; }
        NSMutableArray *jar=[c.accountCookies mutableCopy];
        // Get a fresh token/device context with this exact account cookie snapshot.
        part=[self requestURL:@"https://www.tiktok.com/explore" jar:jar completion:^(id scope,NSDictionary *headers,NSError *pageError){
            if (outer.isCancelled) return;
            if (!sameSession()) { finish(nil,TKMakeError(TKErrorCancelled,L(@"Session changed."))); return; }
            NSDictionary *ctx=TKDict(TKDict(scope)[@"webapp.app-context"]);
            NSString *csrf=TKStr(ctx[@"csrfToken"]), *contextUID=TKStr(TKDict(ctx[@"user"])[@"uid"]);
            NSURL *base=[NSURL URLWithString:@"https://www.tiktok.com/"];
            if(!csrf.length)for(NSString *pair in [[self cookieHeader:jar URL:base] componentsSeparatedByString:@"; "])if([pair hasPrefix:@"tt_csrf_token="]) { csrf=[pair substringFromIndex:14]; break; }
            if (pageError || !csrf.length || csrf.length>4096 || [csrf rangeOfCharacterFromSet:[NSCharacterSet controlCharacterSet]].location!=NSNotFound || !TKStr(ctx[@"wid"]).length || (contextUID.length && ![contextUID isEqualToString:uid])) {
                finish(nil,pageError ?: TKMakeError(TKErrorAPI,L(@"TikTok did not provide the account action token. Open TikTok in your browser and refresh the session."))); return;
            }
            NSMutableDictionary *q=[NSMutableDictionary dictionary]; [self addDeviceParameters:q context:ctx jar:jar]; [q addEntriesFromDictionary:spec[@"params"]];
            NSString *encoded=[self query:q]; encoded=[encoded stringByAppendingFormat:@"&X-Bogus=%@",[TKUtils urlEncode:TKWebSignature(encoded,TKWebUA,(uint32_t)[[NSDate date] timeIntervalSince1970])]];
            NSString *url=[NSString stringWithFormat:@"https://www.tiktok.com%@?%@",spec[@"path"],encoded];
            NSDictionary *h=@{@"User-Agent":TKWebUA,@"Referer":@"https://www.tiktok.com/",@"Origin":@"https://www.tiktok.com",@"Accept":@"application/json",@"Content-Type":@"application/x-www-form-urlencoded",@"tt-csrf-token":csrf,@"Cookie":[self cookieHeader:jar URL:[NSURL URLWithString:url]]};
            part=[TKHTTP request:@"POST" url:url headers:h body:[NSData data] retries:0 completion:^(NSInteger status,NSData *body,NSDictionary *responseHeaders,NSError *writeError){
                if (outer.isCancelled) return;
                NSDictionary *response=TKDict([TKUtils JSONObjectFromData:body]);
                BOOL accepted=!writeError && status==200 && [TKAccountAction accepted:response request:spec userId:uid];
                if(sameSession())c.lastAction=@{@"action":action,@"httpStatus":@(status),@"errorCode":@(writeError.code),@"statusCode":@([response[@"status_code"] isKindOfClass:[NSNumber class]] ? TKInt(response[@"status_code"]) : -1),@"confirmed":@(accepted)};
                if (!accepted) {
                    finish(nil,TKMakeError(TKErrorAPI,L(@"TikTok did not confirm this action. Refresh before trying again; it may already have been received."))); return;
                }
                finish(response,nil);
            }];
        }];
    }];
    return outer;
}
+ (TKHTTPTask *)api:(NSString *)path params:(NSDictionary *)params jar:(NSMutableArray *)jar completion:(TKJSONCompletion)completion
{
    NSMutableDictionary *q=[@{@"aid":@"1988"} mutableCopy];
    // These public endpoints reject otherwise-valid requests with unrelated web parameters.
    BOOL minimal=[path hasPrefix:@"/api/comment/"] || [path isEqualToString:@"/api/search/general/sug/"] || [path isEqualToString:@"/api/explore/item_list/"];
    if (!minimal) [q addEntriesFromDictionary:@{@"app_name":@"tiktok_web",@"device_platform":@"web_pc",@"language":@"en"}];
    [q addEntriesFromDictionary:params ?: @{}];
    BOOL signedAPI = [path rangeOfString:@"/search/general/full/"].location!=NSNotFound || [path rangeOfString:@"/challenge/"].location!=NSNotFound || [path rangeOfString:@"/music/"].location!=NSNotFound || [path rangeOfString:@"/feed/"].location!=NSNotFound || [path rangeOfString:@"/recommend/"].location!=NSNotFound || [path rangeOfString:@"/favorite/"].location!=NSNotFound || [path hasPrefix:@"/api/following/"];
    if (signedAPI) {
        NSDictionary *ctx=[self shared].webContext;
        NSString *from=[path hasPrefix:@"/api/challenge/"]?@"hashtag":([path hasPrefix:@"/api/music/"]?@"music":([path rangeOfString:@"following"].location!=NSNotFound?@"following":([path rangeOfString:@"favorite"].location!=NSNotFound?@"profile":@"fyp")));
        [self addDeviceParameters:q context:ctx jar:jar]; q[@"from_page"]=from;
        [q addEntriesFromDictionary:params ?: @{}];
    }
    NSString *encoded=[self query:q];
    if (signedAPI) encoded=[encoded stringByAppendingFormat:@"&X-Bogus=%@",[TKUtils urlEncode:TKWebSignature(encoded,TKWebUA,(uint32_t)[[NSDate date] timeIntervalSince1970])]];
    return [self requestURL:[NSString stringWithFormat:@"https://www.tiktok.com%@?%@",path,encoded] jar:jar completion:^(id json, NSDictionary *headers, NSError *error) {
        if (!error && ![TKDirectParser successfulResponse:TKDict(json)]) error=[self unavailable];
        completion(error ? nil : json, error ? 0 : 200, error);
    }];
}
+ (NSDictionary *)mediaHeaders:(NSArray *)jar
{
    NSMutableDictionary *h=[@{@"User-Agent":TKWebUA,@"Referer":@"https://www.tiktok.com/"} mutableCopy];
    // A media CDN receives the chain token, never a TikTok account/session cookie.
    for (NSHTTPCookie *c in jar) if ([c.name isEqualToString:@"tt_chain_token"] && (!c.expiresDate || [c.expiresDate timeIntervalSinceNow]>0)) {
        h[@"Cookie"]=[NSString stringWithFormat:@"tt_chain_token=%@",c.value]; break;
    }
    return h;
}
+ (NSArray *)items:(NSArray *)raw jar:(NSArray *)jar height:(NSInteger)height
{
    NSMutableArray *items=[NSMutableArray array]; NSDictionary *headers=[self mediaHeaders:jar];
    for (id entry in raw) {
        NSDictionary *it=TKDict(TKDict(entry)[@"item"]) ?: TKDict(entry);
        NSMutableDictionary *v=[[TKDirectParser video:it maxHeight:height] mutableCopy];
        if (v) { v[@"headers"]=headers; [items addObject:v];
            NSString *room=TKStr(v[@"authorLive"]), *author=TKStr(v[@"author"]);
            if (room.length && ![room isEqualToString:@"0"] && author.length) [self shared].liveAuthors[room]=@{@"room":room,@"user":author,@"name":v[@"authorName"],@"avatar":v[@"authorAvatar"],@"seen":@([[NSDate date] timeIntervalSince1970])};
        }
    }
    return items;
}
+ (TKHTTPTask *)getPath:(NSString *)path query:(NSString *)query completion:(TKJSONCompletion)completion
{
    TKHTTPTask *outer=[[TKHTTPTask alloc] init]; TKDirectClient *c=[self shared];
    NSMutableArray *baseJar=c.accountCookies ?: c.anonymousCookies;
    __block NSMutableArray *jar=nil;
    NSString *requestedToken=TKStr(c.session[@"token"]);
    NSDictionary *q=[TKUtils parseQuery:query ?: @""]; NSInteger height=TKInt(q[@"maxh"]) ?: 1280;
    __block TKHTTPTask *current=nil;
    outer.cancelBlock=^{ [current cancel]; };
    void (^finish)(id,NSInteger,NSError *)=^(id json,NSInteger status,NSError *error) { if (!outer.isCancelled) { outer.cancelBlock=nil; if (![(requestedToken ?: @"") isEqualToString:TKStr([self shared].session[@"token"]) ?: @""]) { completion(nil,0,TKMakeError(TKErrorCancelled,L(@"Session changed."))); return; } completion(json,status,error); } };
    BOOL privatePath=[@[@"/following",@"/foryou",@"/liked",@"/notifications"] containsObject:path];
    void (^run)(void)=^{
        if (outer.isCancelled) return;
        if (![(requestedToken ?: @"") isEqualToString:TKStr(c.session[@"token"]) ?: @""]) { finish(nil,0,TKMakeError(TKErrorCancelled,L(@"Session changed."))); return; }
        jar=[baseJar mutableCopy]; // Each batch keeps the cookies used to obtain its media URLs.
        if (privatePath) {
            current=[self validate:^(BOOL valid,NSDictionary *user,NSError *error) {
                if (outer.isCancelled) return;
                if (!valid) { if (!error && [TKSession sharedSession].signedIn) [[TKSession sharedSession] signOut]; finish(nil,0,error ?: TKMakeError(TKErrorAuth,L(@"TikTok could not verify this session. Export fresh cookies while signed in."))); return; }
                current=[self route:path query:q jar:jar height:height completion:finish];
            }];
        } else current=[self route:path query:q jar:jar height:height completion:finish];
    };
    if ((!baseJar.count || !c.webContext.count) && ![path isEqualToString:@"/expand"]) {
        void (^ready)(NSError *)=^(NSError *error){ if (error) finish(nil,0,error); else run(); };
        [c.warmWaiters addObject:[ready copy]];
        if (!c.warmTask) c.warmTask=[self requestURL:@"https://www.tiktok.com/explore" jar:baseJar completion:^(id scope,NSDictionary *headers,NSError *error) {
            NSArray *waiters=[c.warmWaiters copy];[c.warmWaiters removeAllObjects];c.warmTask=nil;
            for (void (^waiter)(NSError *) in waiters) waiter(error);
        }];
    } else run();
    return outer;
}
+ (TKHTTPTask *)immediate:(id)json error:(NSError *)error completion:(TKJSONCompletion)completion
{
    TKHTTPTask *t=[[TKHTTPTask alloc] init]; dispatch_async(dispatch_get_main_queue(), ^{ if (!t.isCancelled) completion(json,error ? 0 : 200,error); }); return t;
}
+ (TKHTTPTask *)route:(NSString *)path query:(NSDictionary *)q jar:(NSMutableArray *)jar height:(NSInteger)height completion:(TKJSONCompletion)completion
{
    NSInteger count=MAX(1,MIN(30,TKInt(q[@"count"]) ?: 20));
    if ([path isEqualToString:@"/health"]) return [self immediate:@{@"ok":@YES,@"ytdlp":L(@"Direct connection to TikTok")} error:nil completion:completion];
    if ([path isEqualToString:@"/resolve"]) {
        NSString *vid=TKStr(q[@"id"]), *author=TKStr(q[@"user"]) ?: @"_";
        if (!vid.length || [vid rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location!=NSNotFound) return [self immediate:nil error:[self unavailable] completion:completion];
        NSString *url=[NSString stringWithFormat:@"https://www.tiktok.com/@%@/video/%@",[TKUtils urlEncode:author],vid];
        return [self requestURL:url jar:jar completion:^(id scope,NSDictionary *headers,NSError *error) {
            NSDictionary *detail=TKDict(TKDict(scope)[@"webapp.video-detail"]), *raw=TKDict(TKDict(detail[@"itemInfo"])[@"itemStruct"]);
            NSArray *items=[self items:raw ? @[raw] : @[] jar:jar height:height]; NSDictionary *v=TKFirst(items);
            if (![TKStr(v[@"id"]) isEqualToString:vid]) v=nil;
            completion(v,200,error ?: (v ? nil : [self unavailable]));
        }];
    }
    if ([path isEqualToString:@"/profile"] || [path isEqualToString:@"/user"]) {
        NSString *name=TKStr(q[@"name"]) ?: @"";
        if (!name.length) return [self immediate:nil error:[self unavailable] completion:completion];
        TKHTTPTask *outer=[[TKHTTPTask alloc] init]; __block TKHTTPTask *part=nil;
        outer.cancelBlock=^{[part cancel];};
        part=[self requestURL:[@"https://www.tiktok.com/@" stringByAppendingString:[TKUtils urlEncode:name]] jar:jar completion:^(id scope,NSDictionary *headers,NSError *error) {
            if (outer.isCancelled) return;
            NSDictionary *detail=TKDict(TKDict(scope)[@"webapp.user-detail"]), *info=TKDict(detail[@"userInfo"]), *user=[TKDirectParser profile:info];
            if (!user || [TKStr(user[@"handle"]) caseInsensitiveCompare:name]!=NSOrderedSame) { outer.cancelBlock=nil; completion(nil,0,error ?: [self unavailable]); return; }
            part=[self posts:TKStr(user[@"secUid"]) cursor:0 jar:jar height:height completion:^(id page,NSInteger status,NSError *postsError) {
                if (outer.isCancelled) return; outer.cancelBlock=nil;
                // Profile identity/stats remain usable when TikTok restricts its posts endpoint.
                NSMutableDictionary *result=[TKDict(page) mutableCopy] ?: [NSMutableDictionary dictionary]; result[@"user"]=user;
                if (postsError) result[@"postsUnavailable"]=@YES;
                completion(result,200,nil);
            }];
        }];
        return outer;
    }
    if ([path isEqualToString:@"/posts"]) return [self posts:TKStr(q[@"sec"]) cursor:TKDbl(q[@"cursor"]) jar:jar height:height completion:completion];
    if ([path isEqualToString:@"/comments"] || [path isEqualToString:@"/replies"]) {
        BOOL replies=[path isEqualToString:@"/replies"];
        NSMutableDictionary *p=[@{@"aweme_id":TKStr(q[@"id"]) ?: @"",@"count":@(count),@"cursor":@0} mutableCopy];
        if (replies) { p[@"item_id"]=p[@"aweme_id"];[p removeObjectForKey:@"aweme_id"];p[@"comment_id"]=TKStr(q[@"cid"]) ?: @""; }
        return [self api:replies ? @"/api/comment/list/reply/" : @"/api/comment/list/" params:p jar:jar completion:^(id json,NSInteger status,NSError *error) {
            NSMutableArray *items=[NSMutableArray array]; for (id raw in TKArr(TKDict(json)[@"comments"])) { NSDictionary *c=[TKDirectParser comment:TKDict(raw)];if(c)[items addObject:c]; }
            if (!error && ![TKDict(json)[@"comments"] isKindOfClass:[NSArray class]]) error=[self unavailable];
            completion(error ? nil : @{@"items":items},status,error);
        }];
    }
    if ([path isEqualToString:@"/suggest"]) return [self api:@"/api/search/general/sug/" params:@{@"keyword":TKStr(q[@"q"]) ?: @""} jar:jar completion:^(id json,NSInteger status,NSError *error) {
        NSMutableArray *words=[NSMutableArray array]; for (id raw in TKArr(TKDict(json)[@"sug_list"])) { NSString *s=TKStr(TKDict(raw)[@"content"]);if(s.length && ![words containsObject:s]) [words addObject:s];if(words.count==10)break; }
        completion(error ? nil : @{@"items":words},status,error);
    }];
    if ([path isEqualToString:@"/live"]) return [self live:TKStr(q[@"room"]) jar:jar completion:completion];
    if ([path isEqualToString:@"/lives"]) {
        NSMutableDictionary *rooms=[self shared].liveAuthors;NSTimeInterval cutoff=[[NSDate date] timeIntervalSince1970]-600;
        for (NSString *key in [rooms allKeys]) if (TKDbl(TKDict(rooms[key])[@"seen"])<cutoff) [rooms removeObjectForKey:key];
        return [self immediate:@{@"items":[rooms allValues]} error:nil completion:completion];
    }
    if ([path isEqualToString:@"/expand"]) {
        NSString *link=TKStr(q[@"u"]); NSURL *u=[NSURL URLWithString:link ?: @""];
        if (![self tiktokHost:u.host]) return [self immediate:nil error:[self unavailable] completion:completion];
        return [TKHTTP request:@"GET" url:link headers:@{@"User-Agent":TKWebUA} body:nil retries:0 completion:^(NSInteger status,NSData *body,NSDictionary *h,NSError *error) {
            NSString *final=TKStr(h[@"tk-final-url"]); NSURL *target=[NSURL URLWithString:final ?: @""];
            BOOL ok=!error && status>=200 && status<300 && [self tiktokHost:target.host] && [target.scheme.lowercaseString isEqualToString:@"https"];
            completion(ok ? @{@"url":final} : nil,status,ok ? nil : (error ?: [self unavailable]));
        }];
    }
    if ([path isEqualToString:@"/tag"] || [path isEqualToString:@"/sound"]) return [self collection:path query:q jar:jar height:height completion:completion];
    NSString *api=nil; NSMutableDictionary *p=[@{@"count":@(count)} mutableCopy]; BOOL account=NO;
    if ([path isEqualToString:@"/discover"]) { api=@"/api/explore/item_list/";p[@"categoryType"]=@(TKInt(q[@"cat"]) ?: 120); }
    else if ([path isEqualToString:@"/search"]) { api=@"/api/search/general/full/";p[@"keyword"]=TKStr(q[@"q"]) ?: @"";p[@"offset"]=q[@"offset"] ?: @0;p[@"search_source"]=@"normal_search";p[@"from_page"]=@"search"; }
    else if ([path isEqualToString:@"/following"]) {api=@"/api/following/item_list/";account=YES;[p addEntriesFromDictionary:@{@"cursor":@0,@"pullType":@1,@"level":@1,@"isResetCounterUsed":@"true",@"from_page":@"following"}];}
    else if ([path isEqualToString:@"/foryou"]) {api=@"/api/recommend/item_list/";account=YES;p[@"from_page"]=@"fyp";p[@"pull_type"]=@0;p[@"coverFormat"]=@2;}
    else if ([path isEqualToString:@"/liked"]) {api=@"/api/favorite/item_list/";account=YES;p[@"secUid"]=[TKSession sharedSession].secUid ?: @"";p[@"cursor"]=@0;}
    if (!api || (account && ![TKSession sharedSession].signedIn)) return [self immediate:nil error:[self unavailable] completion:completion];
    return [self api:api params:p jar:jar completion:^(id json,NSInteger status,NSError *error) {
        NSDictionary *d=TKDict(json); NSArray *raw=TKArr(d[@"itemList"]); NSMutableArray *users=[NSMutableArray array];
        if ([path isEqualToString:@"/search"]) {
            NSMutableArray *found=[NSMutableArray array]; for (id e in TKArr(d[@"data"])) {
                if(TKDict(TKDict(e)[@"item"])) [found addObject:TKDict(e)[@"item"]];
                for (id x in TKArr(TKDict(e)[@"user_list"])) { NSDictionary *u=TKDict(TKDict(x)[@"user_info"]); NSString *handle=TKStr(u[@"unique_id"]);
                    if(handle.length)[users addObject:@{@"handle":handle,@"name":TKStr(u[@"nickname"]) ?: handle,@"avatar":[TKDirectParser URLString:u[@"avatar_thumb"]],@"followers":u[@"follower_count"] ?: @0}]; }
            } raw=found; if(!error && ![d[@"data"] isKindOfClass:[NSArray class]])error=[self unavailable];
        } else if (!error && !raw) error=[self unavailable];
        NSArray *items=[self items:raw jar:jar height:height];
        BOOL more=TKBool(d[@"hasMore"]) || TKBool(d[@"has_more"]); long long cursor=TKDbl(d[@"cursor"]);
        if (!cursor) cursor=TKDbl(q[@"offset"])+raw.count;
        completion(error ? nil : @{@"items":items,@"users":users,@"hasMore":@(more && raw.count>0),@"cursor":@(cursor),@"offset":@(cursor)},status,error);
    }];
}
+ (TKHTTPTask *)live:(NSString *)room jar:(NSMutableArray *)jar completion:(TKJSONCompletion)completion
{
    if (!room.length || [room rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location!=NSNotFound) return [self immediate:nil error:[self unavailable] completion:completion];
    return [self requestURL:[@"https://webcast.tiktok.com/webcast/room/info/?aid=1988&room_id=" stringByAppendingString:room] jar:jar completion:^(id json,NSDictionary *h,NSError *error) {
        NSDictionary *j=TKDict(json), *d=TKDict(j[@"data"]), *su=TKDict(d[@"stream_url"]), *owner=TKDict(d[@"owner"]);
        if (!error && (![TKDirectParser successfulResponse:j] || !d[@"status"]))error=[self unavailable];
        NSMutableArray *streams=[NSMutableArray array];
        NSString *sd=TKStr(TKDict(TKDict(su[@"live_core_sdk_data"])[@"pull_data"])[@"stream_data"]);
        NSDictionary *qualities=TKDict(TKDict([TKUtils JSONObjectFromData:[sd dataUsingEncoding:NSUTF8StringEncoding]])[@"data"]);
        for (NSString *key in qualities) { NSDictionary *main=TKDict(TKDict(qualities[key])[@"main"]);
            NSString *flv=[TKDirectParser URLString:main[@"flv"]], *hls=[TKDirectParser URLString:main[@"hls"]];
            NSDictionary *params=TKDict([TKUtils JSONObjectFromData:[TKStr(main[@"sdk_params"]) dataUsingEncoding:NSUTF8StringEncoding]]);
            if (flv.length || hls.length) [streams addObject:@{@"quality":key,@"flv":flv,@"hls":hls,@"vcodec":TKStr(params[@"VCodec"]) ?: @"",@"resolution":TKStr(params[@"resolution"]) ?: @"",@"bitrate":params[@"vbitrate"] ?: @0}];
        }
        if (!streams.count) {
            NSDictionary *flvs=TKDict(su[@"flv_pull_url"]);
            for (NSString *key in flvs) { NSString *u=[TKDirectParser URLString:flvs[key]]; if(u.length)[streams addObject:@{@"quality":key,@"flv":u,@"hls":@"",@"vcodec":@"",@"resolution":@"",@"bitrate":@0}]; }
            NSString *hls=[TKDirectParser URLString:su[@"hls_pull_url"]];if(hls.length)[streams addObject:@{@"quality":@"hls",@"flv":@"",@"hls":hls,@"vcodec":@"",@"resolution":@"",@"bitrate":@0}];
        }
        completion(error?nil:@{@"room":room,@"live":@(TKInt(d[@"status"])==2),@"title":TKStr(d[@"title"]) ?: @"",@"viewers":d[@"user_count"] ?: @0,@"cover":[TKDirectParser URLString:d[@"cover"]],@"owner":@{@"handle":TKStr(owner[@"display_id"]) ?: @"",@"name":TKStr(owner[@"nickname"]) ?: @"",@"avatar":[TKDirectParser URLString:owner[@"avatar_thumb"]]},@"streams":streams,@"headers":[self mediaHeaders:jar]},200,error);
    }];
}
+ (TKHTTPTask *)posts:(NSString *)sec cursor:(long long)cursor jar:(NSMutableArray *)jar height:(NSInteger)height completion:(TKJSONCompletion)completion
{
    if(!sec.length)return [self immediate:nil error:[self unavailable] completion:completion];
    if(cursor<=0)cursor=(long long)([[NSDate date] timeIntervalSince1970]*1000);
    return [self api:@"/api/creator/item_list/" params:@{@"secUid":sec,@"count":@15,@"cursor":@(cursor),@"type":@1} jar:jar completion:^(id json,NSInteger status,NSError *error) {
        NSDictionary *d=TKDict(json);NSArray *raw=TKArr(d[@"itemList"]);
        if(!error && !raw)error=[self unavailable];
        long long next=TKDbl(TKDict(raw.lastObject)[@"createTime"])*1000;
        BOOL more=TKBool(d[@"hasMorePrevious"]) && next>0 && next<cursor;
        completion(error ? nil : @{@"items":[self items:raw jar:jar height:height],@"cursor":@(more?next:0),@"hasMore":@(more)},status,error);
    }];
}
+ (TKHTTPTask *)collection:(NSString *)path query:(NSDictionary *)q jar:(NSMutableArray *)jar height:(NSInteger)height completion:(TKJSONCompletion)completion
{
    BOOL tag=[path isEqualToString:@"/tag"];NSString *key=tag?@"name":@"id", *value=TKStr(q[key]) ?: @"";
    TKHTTPTask *outer=[[TKHTTPTask alloc] init];__block TKHTTPTask *part=nil;outer.cancelBlock=^{[part cancel];};
    part=[self api:tag?@"/api/challenge/detail/":@"/api/music/detail/" params:@{tag?@"challengeName":@"musicId":value} jar:jar completion:^(id json,NSInteger status,NSError *error) {
        if(outer.isCancelled)return;
        NSDictionary *info=TKDict(TKDict(json)[tag?@"challengeInfo":@"musicInfo"]), *entity=TKDict(info[tag?@"challenge":@"music"]), *stats=TKDict(info[@"statsV2"]) ?: TKDict(info[@"stats"]);
        NSString *eid=TKStr(entity[@"id"]);
        if(error || !eid.length){outer.cancelBlock=nil;completion(nil,status,error ?: [self unavailable]);return;}
        NSDictionary *meta=tag ? @{@"id":eid,@"name":TKStr(entity[@"title"]) ?: value,@"desc":TKStr(entity[@"desc"]) ?: @"",@"videos":stats[@"videoCount"] ?: @0,@"views":stats[@"viewCount"] ?: @0} :
            @{@"id":eid,@"title":TKStr(entity[@"title"]) ?: @"",@"author":TKStr(entity[@"authorName"]) ?: @"",@"original":entity[@"original"] ?: @NO,@"cover":[TKDirectParser URLString:entity[@"coverMedium"]],@"playUrl":[TKDirectParser URLString:entity[@"playUrl"]],@"duration":entity[@"duration"] ?: @0,@"videos":stats[@"videoCount"] ?: @0};
        part=[self api:tag?@"/api/challenge/item_list/":@"/api/music/item_list/" params:@{tag?@"challengeID":@"musicID":eid,@"cursor":q[@"cursor"] ?: @0,@"count":@30,@"coverFormat":@2} jar:jar completion:^(id page,NSInteger status,NSError *error) {
            if(outer.isCancelled)return;outer.cancelBlock=nil;NSDictionary *d=TKDict(page);NSArray *raw=TKArr(d[@"itemList"]);
            if(!error && !raw)error=[self unavailable];
            completion(error?nil:@{tag?@"tag":@"sound":meta,@"items":[self items:raw jar:jar height:height],@"cursor":d[@"cursor"] ?: @0,@"hasMore":@(TKBool(d[@"hasMore"]) && raw.count>0)},status,error);
        }];
    }];return outer;
}
+ (NSDictionary *)savedSession { return [self shared].session; }
+ (NSString *)serializeCookies:(NSArray *)jar
{
    NSMutableArray *a=[NSMutableArray array];for(NSHTTPCookie *c in jar){NSMutableDictionary *d=[@{@"name":c.name,@"value":c.value,@"domain":c.domain,@"path":c.path} mutableCopy];if(c.expiresDate)d[@"expirationDate"]=@([c.expiresDate timeIntervalSince1970]);[a addObject:d];}
    return [[NSString alloc] initWithData:[TKUtils JSONDataFromObject:a] encoding:NSUTF8StringEncoding];
}
+ (TKHTTPTask *)importCookies:(NSString *)input completion:(void (^)(BOOL,NSString *,NSDictionary *,NSError *))completion
{
    NSError *error=nil;NSMutableArray *jar=[[TKDirectParser cookiesFromString:input error:&error] mutableCopy];
    if(!jar){return [self immediate:nil error:error completion:^(id j,NSInteger s,NSError *e){completion(NO,nil,nil,e);}];}
    TKHTTPTask *outer=[[TKHTTPTask alloc] init];__block TKHTTPTask *part=nil;outer.cancelBlock=^{[part cancel];};
    part=[self requestURL:@"https://www.tiktok.com/passport/web/account/info/?aid=1988&app_name=tiktok_web" jar:jar completion:^(id json,NSDictionary *headers,NSError *error){
        if(outer.isCancelled)return;
        NSDictionary *user=[TKDirectParser verifiedAccount:TKDict(json) cookies:jar];
        if(error || !user){outer.cancelBlock=nil;completion(NO,nil,nil,error ?: TKMakeError(TKErrorAuth,L(@"TikTok could not verify this session. Export fresh cookies while signed in.")));return;}
        part=[self requestURL:[@"https://www.tiktok.com/@" stringByAppendingString:[TKUtils urlEncode:TKStr(user[@"handle"])]] jar:jar completion:^(id scope,NSDictionary *h,NSError *error){
            if(outer.isCancelled)return;outer.cancelBlock=nil;
            NSDictionary *profile=[TKDirectParser profile:TKDict(TKDict(TKDict(scope)[@"webapp.user-detail"])[@"userInfo"])];
            NSDictionary *verified=[TKDirectParser account:user matchingProfile:profile];
            if(error || !verified) {completion(NO,nil,nil,error ?: TKMakeError(TKErrorAuth,L(@"The verified account and profile do not match. Export fresh TikTok cookies.")));return;}
            NSString *token=[[NSProcessInfo processInfo] globallyUniqueString];
            [self shared].pending[token]=@{@"token":token,@"user":verified,@"cookies":[self serializeCookies:jar]};
            completion(YES,token,verified,nil);
            [[self shared].pending removeObjectForKey:token];
        }];
    }];return outer;
}

+ (BOOL)commitSession:(NSString *)token
{
    TKDirectClient *c=[self shared];NSDictionary *d=c.pending[token];if(!d)return NO;
    NSString *s=[[NSString alloc] initWithData:[TKUtils JSONDataFromObject:d] encoding:NSUTF8StringEncoding];
    if(![TKKeychain setSecureString:s forKey:TKDirectKey])return NO;
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"direct.signedOut"];[[NSUserDefaults standardUserDefaults] synchronize];
    c.session=d;c.webContext=nil;c.lastAction=nil;c.accountCookies=[[TKDirectParser cookiesFromString:d[@"cookies"] error:nil] mutableCopy];return YES;
}
+ (TKHTTPTask *)validate:(void (^)(BOOL,NSDictionary *,NSError *))completion
{
    TKDirectClient *c=[self shared];NSMutableArray *jar=c.accountCookies;NSString *token=TKStr(c.session[@"token"]);NSString *uid=TKStr(TKDict(c.session[@"user"])[@"userId"]);
    if(!jar.count)return [self immediate:nil error:nil completion:^(id j,NSInteger s,NSError *e){completion(NO,nil,nil);}];
    return [self requestURL:@"https://www.tiktok.com/passport/web/account/info/?aid=1988&app_name=tiktok_web" jar:jar completion:^(id json,NSDictionary *h,NSError *error){
        if(![TKStr(c.session[@"token"]) isEqualToString:token]){completion(NO,nil,TKMakeError(TKErrorCancelled,L(@"Session changed.")));return;}
        NSDictionary *user=[TKDirectParser verifiedAccount:TKDict(json) cookies:jar];
        if(user && ![TKStr(user[@"userId"]) isEqualToString:uid])user=nil;
        NSDictionary *data=TKDict(TKDict(json)[@"data"]);
        BOOL expired=TKInt(data[@"error_code"])==13 || [TKStr(data[@"name"]) isEqualToString:@"session_expired"];
        // A changed response schema/challenge is not an instruction to delete a valid session.
        completion(user!=nil,user,error ?: ((!user && !expired)?[self unavailable]:nil));
    }];
}
+ (void)signOut
{
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"direct.signedOut"];[[NSUserDefaults standardUserDefaults] synchronize];
    TKDirectClient *c=[self shared];c.session=nil;c.accountCookies=nil;c.webContext=nil;c.lastAction=nil;[c.pending removeAllObjects];[c.liveAuthors removeAllObjects];
    [TKKeychain setSecureString:nil forKey:TKDirectKey];
}
@end
