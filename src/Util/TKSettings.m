#import "TKSettings.h"
#import "TKKeychain.h"
#import "TKCommon.h"

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

+ (NSArray *)savedVideos { return [DEF arrayForKey:@"savedVideos"] ?: @[]; }

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
    [self save];
    [self notifyLibrary];
}

+ (void)unsaveVideo:(NSString *)videoId
{
    NSMutableArray *list = [[self savedVideos] mutableCopy];
    for (NSInteger i = (NSInteger)list.count - 1; i >= 0; i--) if ([TKStr(list[(NSUInteger)i][@"id"]) isEqualToString:videoId]) [list removeObjectAtIndex:(NSUInteger)i];
    [DEF setObject:list forKey:@"savedVideos"];
    [self save];
    [self notifyLibrary];
}

#pragma mark - Seen videos

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

+ (BOOL)allowAccountWrites { return NO; }

+ (void)setAllowAccountWrites:(BOOL)value
{
    [DEF setBool:value forKey:@"allowAccountWrites"];
    [self notify];
}

@end
