#import "TKSettings.h"
#import "TKKeychain.h"
#import "TKCommon.h"
#import "TKVideoLibrary.h"

#define DEF [NSUserDefaults standardUserDefaults]
static NSString * const TKServerKeyName = @"tikie.serverKey";
static const NSUInteger TKMaxSaved = 500;
static const NSUInteger TKMaxSeen = 4000;

@implementation TKSettings

+ (void)registerDefaults
{
    [DEF registerDefaults:@{
        @"serverBaseURL": @"",
        @"streamThroughServer": @NO,
        @"startMuted": @NO,
        @"autoAdvance": @NO,       // (the viewer swipes on; a video loops until then)
        @"showCaptions": @YES,
        @"topicsChosen": @NO,
        @"searchHistory": @[],
        @"darkTheme": @YES,
        @"verifyTLS": @YES,
        @"hiddenLanguages": @[],
        @"savedVideos": @[],
        @"seenVideos": @[],
        @"watchHistory": @[],
        @"recordWatchHistory": @YES,
        @"favoriteCreators": @[], @"favoriteSounds": @[], @"blockedCreators": @[], @"hiddenKeywords": @[], @"collections": @[],
        @"hidePhotoPosts": @NO, @"maxVideoDuration": @0, @"defaultPlaybackSpeed": @1, @"cleanVideo": @NO,
        @"allowAccountWrites": @NO,
    }];
}

+ (void)save { [DEF synchronize]; }

+ (void)notify
{
    TKMain(^{ [[NSNotificationCenter defaultCenter] postNotificationName:TKSettingsDidChangeNotification object:nil]; });
}

+ (void)notifyLibrary
{
    TKMain(^{ [[NSNotificationCenter defaultCenter] postNotificationName:TKLibraryDidChangeNotification object:nil]; });
}

#pragma mark - Server

+ (NSString *)serverBaseURL
{
    NSString *s = [DEF stringForKey:@"serverBaseURL"] ?: @"";
    s = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    while ([s hasSuffix:@"/"]) s = [s substringToIndex:s.length - 1];
    return s;
}

+ (void)setServerBaseURL:(NSString *)value
{
    NSString *s = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
    if (s.length && ![s hasPrefix:@"http://"] && ![s hasPrefix:@"https://"]) s = [@"https://" stringByAppendingString:s];
    [DEF setObject:s forKey:@"serverBaseURL"];
    [self notify];
}

+ (NSString *)serverKey { return [TKKeychain stringForKey:TKServerKeyName] ?: @""; }
+ (void)setServerKey:(NSString *)value { [TKKeychain setString:value forKey:TKServerKeyName]; }

+ (BOOL)serverConfigured { return [self serverBaseURL].length > 0; }

+ (BOOL)streamThroughServer { return NO; }
+ (void)setStreamThroughServer:(BOOL)value { [DEF setBool:value forKey:@"streamThroughServer"]; [self notify]; }

#pragma mark - Playback / appearance / network

+ (BOOL)startMuted { return [DEF boolForKey:@"startMuted"]; }
+ (void)setStartMuted:(BOOL)value { [DEF setBool:value forKey:@"startMuted"]; [self notify]; }
+ (BOOL)autoAdvance { return [DEF boolForKey:@"autoAdvance"]; }
+ (void)setAutoAdvance:(BOOL)value { [DEF setBool:value forKey:@"autoAdvance"]; [self notify]; }
+ (BOOL)showCaptions { return [DEF boolForKey:@"showCaptions"]; }
+ (void)setShowCaptions:(BOOL)value { [DEF setBool:value forKey:@"showCaptions"]; [self notify]; }
+ (BOOL)topicsChosen { return [DEF boolForKey:@"topicsChosen"]; }
+ (void)setTopicsChosen:(BOOL)value { [DEF setBool:value forKey:@"topicsChosen"]; }

#pragma mark - Search

+ (NSArray *)searchHistory
{
    NSMutableArray *out = [NSMutableArray array];
    for (id q in TKArr([DEF objectForKey:@"searchHistory"])) if (TKStr(q).length) [out addObject:TKStr(q)];
    return out;
}

+ (void)addSearch:(NSString *)query
{
    NSString *q = [query stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!q.length) return;
    NSMutableArray *list = [[self searchHistory] mutableCopy];
    for (NSInteger i = (NSInteger)list.count - 1; i >= 0; i--) if ([list[(NSUInteger)i] caseInsensitiveCompare:q] == NSOrderedSame) [list removeObjectAtIndex:(NSUInteger)i];
    [list insertObject:q atIndex:0];
    while (list.count > 20) [list removeLastObject];
    [DEF setObject:list forKey:@"searchHistory"];
}

+ (void)clearSearchHistory { [DEF setObject:@[] forKey:@"searchHistory"]; }
+ (BOOL)darkTheme { return [DEF boolForKey:@"darkTheme"]; }
+ (void)setDarkTheme:(BOOL)value { [DEF setBool:value forKey:@"darkTheme"]; }
+ (BOOL)verifyTLS { return YES; }
+ (void)setVerifyTLS:(BOOL)value { [DEF setBool:value forKey:@"verifyTLS"]; }

#pragma mark - Languages

+ (NSArray *)knownLanguages
{
    return @[ @"cs", @"sk", @"en", @"de", @"pl", @"ru", @"uk", @"es", @"pt", @"fr", @"it", @"ar", @"tr", @"id", @"vi" ];
}

+ (NSArray *)hiddenLanguages { return [DEF arrayForKey:@"hiddenLanguages"] ?: @[]; }

+ (void)setHiddenLanguages:(NSArray *)codes
{
    [DEF setObject:codes ?: @[] forKey:@"hiddenLanguages"];
    [self save];
    [self notify];
}

+ (BOOL)allowsLanguage:(NSString *)code
{
    NSArray *hidden = [self hiddenLanguages];
    if (!hidden.count) return YES;
    NSString *c = code.length ? [code lowercaseString] : @"un";
    if ([hidden containsObject:c]) return NO;
    if (![c isEqualToString:@"un"] && ![[self knownLanguages] containsObject:c] && [hidden containsObject:@"*"]) return NO;
    return YES;
}

#pragma mark - Saved

+ (NSArray *)savedVideos { return [TKVideoLibrary addingVideo:nil toList:[DEF arrayForKey:@"savedVideos"] limit:TKMaxSaved]; }

+ (BOOL)isSaved:(NSString *)videoId
{
    if (!videoId.length) return NO;
    for (NSDictionary *d in [self savedVideos]) if ([TKStr(d[@"id"]) isEqualToString:videoId]) return YES;
    return NO;
}

+ (void)saveVideoJSON:(NSDictionary *)json
{
    NSString *vid = TKStr(json[@"id"]);
    if (!vid.length) return;
    NSMutableArray *list = [[self savedVideos] mutableCopy];
    for (NSInteger i = (NSInteger)list.count - 1; i >= 0; i--) if ([TKStr(list[(NSUInteger)i][@"id"]) isEqualToString:vid]) [list removeObjectAtIndex:(NSUInteger)i];
    [list insertObject:json atIndex:0];
    while (list.count > TKMaxSaved) [list removeLastObject];
    [DEF setObject:list forKey:@"savedVideos"];
    [self pruneCollections];
    [self save];
    [self notifyLibrary];
}

+ (void)unsaveVideo:(NSString *)videoId
{
    NSMutableArray *list = [[self savedVideos] mutableCopy];
    for (NSInteger i = (NSInteger)list.count - 1; i >= 0; i--) if ([TKStr(list[(NSUInteger)i][@"id"]) isEqualToString:videoId]) [list removeObjectAtIndex:(NSUInteger)i];
    [DEF setObject:list forKey:@"savedVideos"];
    [self pruneCollections];
    [self save];
    [self notifyLibrary];
}

#pragma mark - Seen videos

+ (BOOL)recordWatchHistory { return [DEF boolForKey:@"recordWatchHistory"]; }
+ (void)setRecordWatchHistory:(BOOL)value { [DEF setBool:value forKey:@"recordWatchHistory"]; [self save]; [self notify]; }
+ (NSArray *)watchHistory { return [TKVideoLibrary addingVideo:nil toList:[DEF arrayForKey:@"watchHistory"] limit:200]; }
+ (void)recordWatchedVideo:(NSDictionary *)json
{
    if (![self recordWatchHistory] || ![TKVideoLibrary metadata:json]) return;
    NSMutableDictionary *entry = [json mutableCopy];
    entry[@"watchedAt"] = @([[NSDate date] timeIntervalSince1970]);
    [DEF setObject:[TKVideoLibrary addingVideo:entry toList:[self watchHistory] limit:200] forKey:@"watchHistory"];
    [self save]; [self notifyLibrary];
}
+ (void)removeFromWatchHistory:(NSString *)videoId
{
    NSMutableArray *list = [[self watchHistory] mutableCopy];
    for (NSInteger i = (NSInteger)list.count - 1; i >= 0; i--) if ([list[(NSUInteger)i][@"id"] isEqual:videoId]) [list removeObjectAtIndex:(NSUInteger)i];
    [DEF setObject:list forKey:@"watchHistory"]; [self save]; [self notifyLibrary];
}
+ (void)clearWatchHistory { [DEF setObject:@[] forKey:@"watchHistory"]; [self save]; [self notifyLibrary]; }

+ (BOOL)hasSeenVideo:(NSString *)videoId
{
    if (!videoId.length) return NO;
    return [[DEF arrayForKey:@"seenVideos"] containsObject:videoId];
}

+ (void)markVideoSeen:(NSString *)videoId
{
    if (!videoId.length) return;
    NSMutableArray *seen = [[DEF arrayForKey:@"seenVideos"] mutableCopy] ?: [NSMutableArray array];
    [seen removeObject:videoId];
    [seen addObject:videoId];
    while (seen.count > TKMaxSeen) [seen removeObjectAtIndex:0];
    [DEF setObject:seen forKey:@"seenVideos"];
}

+ (BOOL)allowAccountWrites { return YES; }

+ (void)setAllowAccountWrites:(BOOL)value
{
    [DEF setBool:value forKey:@"allowAccountWrites"];
    [self notify];
}

#pragma mark - Favorites and content preferences
+ (NSArray *)favoriteCreators { return [DEF arrayForKey:@"favoriteCreators"] ?: @[]; }
+ (NSArray *)favoriteSounds { return [DEF arrayForKey:@"favoriteSounds"] ?: @[]; }
+ (BOOL)isFavoriteCreator:(NSString *)handle
{
    NSString *h = [TKVideoLibrary normalizedHandle:handle];
    for (NSDictionary *d in [self favoriteCreators]) if ([d[@"handle"] isEqual:h]) return YES;
    return NO;
}
+ (BOOL)isFavoriteSound:(NSString *)soundId
{
    for (NSDictionary *d in [self favoriteSounds]) if ([d[@"id"] isEqual:soundId]) return YES;
    return NO;
}
+ (void)saveFavoriteCreator:(NSDictionary *)creator
{
    NSString *h = [TKVideoLibrary normalizedHandle:TKStr(creator[@"handle"])];
    if (!h) return;
    NSMutableArray *a = [[self favoriteCreators] mutableCopy];
    for (NSInteger i=(NSInteger)a.count-1;i>=0;i--) if ([a[(NSUInteger)i][@"handle"] isEqual:h]) [a removeObjectAtIndex:(NSUInteger)i];
    [a insertObject:@{@"handle":h, @"name":TKStr(creator[@"name"]) ?: h, @"avatar":TKStr(creator[@"avatar"]) ?: @""} atIndex:0];
    while (a.count > 500) [a removeLastObject];
    [DEF setObject:a forKey:@"favoriteCreators"]; [self save]; [self notifyLibrary];
}
+ (void)removeFavoriteCreator:(NSString *)handle
{
    NSString *h = [TKVideoLibrary normalizedHandle:handle];
    NSMutableArray *a = [[self favoriteCreators] mutableCopy];
    for (NSInteger i=(NSInteger)a.count-1;i>=0;i--) if ([a[(NSUInteger)i][@"handle"] isEqual:h]) [a removeObjectAtIndex:(NSUInteger)i];
    [DEF setObject:a forKey:@"favoriteCreators"]; [self save]; [self notifyLibrary];
}
+ (void)saveFavoriteSound:(NSDictionary *)sound
{
    NSString *sid = TKStr(sound[@"id"]);
    if (!sid.length || [sid rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789"] invertedSet]].location != NSNotFound) return;
    NSMutableArray *a = [[self favoriteSounds] mutableCopy];
    for (NSInteger i=(NSInteger)a.count-1;i>=0;i--) if ([a[(NSUInteger)i][@"id"] isEqual:sid]) [a removeObjectAtIndex:(NSUInteger)i];
    [a insertObject:@{@"id":sid, @"name":TKStr(sound[@"name"]) ?: @"", @"author":TKStr(sound[@"author"]) ?: @"", @"cover":TKStr(sound[@"cover"]) ?: @""} atIndex:0];
    while (a.count > 500) [a removeLastObject];
    [DEF setObject:a forKey:@"favoriteSounds"]; [self save]; [self notifyLibrary];
}
+ (void)removeFavoriteSound:(NSString *)soundId
{
    NSMutableArray *a = [[self favoriteSounds] mutableCopy];
    for (NSInteger i=(NSInteger)a.count-1;i>=0;i--) if ([a[(NSUInteger)i][@"id"] isEqual:soundId]) [a removeObjectAtIndex:(NSUInteger)i];
    [DEF setObject:a forKey:@"favoriteSounds"]; [self save]; [self notifyLibrary];
}
+ (NSArray *)blockedCreators { return [DEF arrayForKey:@"blockedCreators"] ?: @[]; }
+ (void)setCreator:(NSString *)handle blocked:(BOOL)blocked
{
    NSString *h = [TKVideoLibrary normalizedHandle:handle]; if (!h) return;
    NSMutableArray *a = [[self blockedCreators] mutableCopy]; [a removeObject:h];
    if (blocked) [a insertObject:h atIndex:0];
    while (a.count > 500) [a removeLastObject];
    [DEF setObject:a forKey:@"blockedCreators"]; [self save]; [self notify]; [self notifyLibrary];
}
+ (NSArray *)hiddenKeywords { return [DEF arrayForKey:@"hiddenKeywords"] ?: @[]; }
+ (void)setHiddenKeywords:(NSString *)text
{
    NSMutableArray *words = [NSMutableArray array];
    for (NSString *part in [text componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@",\n"]]) {
        NSString *word = [part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!word.length || word.length > 100 || [words containsObject:word]) continue;
        [words addObject:word]; if (words.count >= 100) break;
    }
    [DEF setObject:words forKey:@"hiddenKeywords"]; [self save]; [self notify];
}
+ (BOOL)allowsPost:(NSDictionary *)video { return ![TKVideoLibrary video:video blockedByCreators:[self blockedCreators] keywords:[self hiddenKeywords] hidePhotos:[self hidePhotoPosts] maxDuration:[self maxVideoDuration]]; }
+ (BOOL)hidePhotoPosts { return [DEF boolForKey:@"hidePhotoPosts"]; }
+ (void)setHidePhotoPosts:(BOOL)value { [DEF setBool:value forKey:@"hidePhotoPosts"]; [self save]; [self notify]; }
+ (NSInteger)maxVideoDuration { return [DEF integerForKey:@"maxVideoDuration"]; }
+ (void)setMaxVideoDuration:(NSInteger)seconds { [DEF setInteger:MAX(0,seconds) forKey:@"maxVideoDuration"]; [self save]; [self notify]; }
+ (float)defaultPlaybackSpeed { float s=[DEF floatForKey:@"defaultPlaybackSpeed"]; return (s==0.5f || s==1.5f || s==2) ? s : 1; }
+ (void)setDefaultPlaybackSpeed:(float)speed { if (!(speed==0.5f || speed==1 || speed==1.5f || speed==2)) return; [DEF setFloat:speed forKey:@"defaultPlaybackSpeed"]; [self save]; [self notify]; }
+ (BOOL)cleanVideo { return [DEF boolForKey:@"cleanVideo"]; }
+ (void)setCleanVideo:(BOOL)value { [DEF setBool:value forKey:@"cleanVideo"]; [self save]; [self notify]; }

#pragma mark - Collections
+ (void)pruneCollections
{
    NSMutableSet *saved=[NSMutableSet set]; for(NSDictionary *v in [self savedVideos])[saved addObject:v[@"id"]];
    NSMutableArray *out=[NSMutableArray array];
    for(NSDictionary *original in [self collections]) {
        NSMutableDictionary *c=[original mutableCopy]; NSMutableArray *ids=[NSMutableArray array];
        for(NSString *vid in TKArr(c[@"videos"]))if([saved containsObject:vid] && ![ids containsObject:vid])[ids addObject:vid];
        c[@"videos"]=ids; [out addObject:c];
    }
    [DEF setObject:out forKey:@"collections"];
}
+ (NSString *)watchLaterCollectionId
{
    NSString *existing=[DEF stringForKey:@"watchLaterCollectionId"];
    for(NSDictionary *c in [self collections]) if([c[@"id"] isEqual:existing])return existing;
    NSString *name=L(@"Watch later"), *cid=nil;
    for(NSDictionary *c in [self collections]) if([TKStr(c[@"name"]) caseInsensitiveCompare:name]==NSOrderedSame)cid=c[@"id"];
    if(!cid)cid=[self createCollection:name];
    if(cid) { [DEF setObject:cid forKey:@"watchLaterCollectionId"]; [self save]; }
    return cid;
}
+ (NSArray *)collections { return [DEF arrayForKey:@"collections"] ?: @[]; }
+ (NSString *)createCollection:(NSString *)name
{
    NSString *n=[TKVideoLibrary collectionName:name]; if (!n || [self collections].count >= 100) return nil;
    for (NSDictionary *c in [self collections]) if ([TKStr(c[@"name"]) caseInsensitiveCompare:n]==NSOrderedSame) return nil;
    NSString *cid=[[NSProcessInfo processInfo] globallyUniqueString];
    NSMutableArray *a=[[self collections] mutableCopy]; [a addObject:@{@"id":cid,@"name":n,@"videos":@[]}];
    [DEF setObject:a forKey:@"collections"]; [self save]; [self notifyLibrary]; return cid;
}
+ (BOOL)renameCollection:(NSString *)collectionId name:(NSString *)name
{
    NSString *n=[TKVideoLibrary collectionName:name]; if (!n) return NO;
    NSMutableArray *a=[[self collections] mutableCopy];
    for (NSDictionary *c in a) if (![c[@"id"] isEqual:collectionId] && [TKStr(c[@"name"]) caseInsensitiveCompare:n]==NSOrderedSame) return NO;
    for (NSUInteger i=0;i<a.count;i++) if ([a[i][@"id"] isEqual:collectionId]) {
        NSMutableDictionary *c=[a[i] mutableCopy]; c[@"name"]=n; a[i]=c;
        [DEF setObject:a forKey:@"collections"]; [self save]; [self notifyLibrary]; return YES;
    }
    return NO;
}
+ (void)deleteCollection:(NSString *)collectionId
{
    NSMutableArray *a=[[self collections] mutableCopy];
    for (NSInteger i=(NSInteger)a.count-1;i>=0;i--) if ([a[(NSUInteger)i][@"id"] isEqual:collectionId]) [a removeObjectAtIndex:(NSUInteger)i];
    [DEF setObject:a forKey:@"collections"]; [self save]; [self notifyLibrary];
}
+ (NSArray *)videosInCollection:(NSString *)collectionId
{
    NSArray *ids=nil; for (NSDictionary *c in [self collections]) if ([c[@"id"] isEqual:collectionId]) ids=TKArr(c[@"videos"]);
    NSMutableArray *out=[NSMutableArray array];
    for (NSDictionary *video in [self savedVideos]) if ([ids containsObject:video[@"id"]]) [out addObject:video];
    return out;
}
+ (void)addVideo:(NSDictionary *)video toCollection:(NSString *)collectionId
{
    if (![TKVideoLibrary metadata:video]) return;
    NSMutableArray *a=[[self collections] mutableCopy];
    for (NSUInteger i=0;i<a.count;i++) if ([a[i][@"id"] isEqual:collectionId]) {
        NSMutableDictionary *c=[a[i] mutableCopy]; NSMutableArray *ids=[TKArr(c[@"videos"]) mutableCopy] ?: [NSMutableArray array];
        NSString *vid=TKStr(video[@"id"]); [ids removeObject:vid]; [ids insertObject:vid atIndex:0]; while(ids.count>500)[ids removeLastObject];
        c[@"videos"]=ids; a[i]=c; [DEF setObject:a forKey:@"collections"]; [self saveVideoJSON:video]; return;
    }
}
+ (void)removeVideo:(NSString *)videoId fromCollection:(NSString *)collectionId
{
    NSMutableArray *a=[[self collections] mutableCopy];
    for (NSUInteger i=0;i<a.count;i++) if ([a[i][@"id"] isEqual:collectionId]) {
        NSMutableDictionary *c=[a[i] mutableCopy]; NSMutableArray *ids=[TKArr(c[@"videos"]) mutableCopy]; [ids removeObject:videoId]; c[@"videos"]=ids ?: @[]; a[i]=c;
        [DEF setObject:a forKey:@"collections"]; [self save]; [self notifyLibrary]; return;
    }
}
@end
