#import "TKVideoLibrary.h"
#import "TKCommon.h"
#include <math.h>

@implementation TKVideoLibrary
+ (NSString *)normalizedHandle:(NSString *)handle
{
    NSString *s = [[(TKStr(handle) ?: @"") stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    if ([s hasPrefix:@"@"]) s = [s substringFromIndex:1];
    NSMutableCharacterSet *allowed=[[NSCharacterSet alphanumericCharacterSet] mutableCopy]; [allowed addCharactersInString:@"._"];
    if (!s.length || s.length > 100 || [s rangeOfCharacterFromSet:[allowed invertedSet]].location != NSNotFound) return nil;
    return s;
}
+ (NSString *)collectionName:(NSString *)name
{
    NSString *s = [TKStr(name) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!s.length || s.length > 60 || [s rangeOfCharacterFromSet:[NSCharacterSet controlCharacterSet]].location != NSNotFound) return nil;
    return s;
}
+ (BOOL)video:(NSDictionary *)video blockedByCreators:(NSArray *)creators keywords:(NSArray *)keywords hidePhotos:(BOOL)photos maxDuration:(NSInteger)seconds
{
    if ([creators containsObject:[self normalizedHandle:TKStr(video[@"author"])] ?: @""]) return YES;
    if (photos && [TKStr(video[@"type"]) isEqual:@"photo"]) return YES;
    if (seconds > 0 && TKDbl(video[@"duration"]) > seconds) return YES;
    for (NSString *keyword in keywords) if (keyword.length && [self videos:@[video] matching:keyword].count) return YES;
    return NO;
}
+ (NSDictionary *)metadata:(NSDictionary *)video
{
    if (![video isKindOfClass:[NSDictionary class]]) return nil;
    NSString *vid = TKStr(video[@"id"]);
    if (!vid.length || [vid rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789"] invertedSet]].location != NSNotFound) return nil;
    NSMutableDictionary *out = [NSMutableDictionary dictionaryWithObject:vid forKey:@"id"];
    for (NSString *key in @[@"author", @"authorName", @"desc", @"cover", @"url", @"music", @"musicId", @"musicAuthor", @"musicCover", @"lang", @"authorAvatar", @"type"]) {
        NSString *value = TKStr(video[key]);
        if (value.length) out[key] = value;
    }
    for (NSString *key in @[@"likes", @"comments", @"plays", @"duration", @"width", @"height", @"category", @"musicOriginal", @"created", @"watchedAt"])
        if ([video[key] isKindOfClass:[NSNumber class]] && isfinite([video[key] doubleValue])) out[key] = video[key];
    NSMutableArray *tags = [NSMutableArray array];
    for (id tag in TKArr(video[@"tags"])) if (TKStr(tag).length) [tags addObject:TKStr(tag)];
    if (tags.count) out[@"tags"] = tags;
    return out;
}

+ (NSArray *)addingVideo:(NSDictionary *)video toList:(NSArray *)list limit:(NSUInteger)limit
{
    NSDictionary *entry = [self metadata:video];
    NSMutableArray *out = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    if (entry && limit) { [out addObject:entry]; [seen addObject:entry[@"id"]]; }
    for (id item in list) {
        if (out.count >= limit) break;
        NSDictionary *d = [self metadata:item];
        if (!d || [seen containsObject:d[@"id"]]) continue;
        [out addObject:d]; [seen addObject:d[@"id"]];
    }
    return out;
}

+ (NSArray *)videos:(NSArray *)videos matching:(NSString *)query
{
    NSString *q = [query stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!q.length) return videos ?: @[];
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *d in videos) {
        if (![d isKindOfClass:[NSDictionary class]]) continue;
        NSString *text = [NSString stringWithFormat:@"@%@ %@ %@ %@ %@", TKStr(d[@"author"]) ?: @"", TKStr(d[@"authorName"]) ?: @"", TKStr(d[@"desc"]) ?: @"", TKStr(d[@"music"]) ?: @"", [TKArr(d[@"tags"]) componentsJoinedByString:@" "] ?: @""];
        if ([text rangeOfString:q options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location != NSNotFound) [out addObject:d];
    }
    return out;
}
@end
