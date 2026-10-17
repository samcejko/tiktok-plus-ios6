#import "TKSubtitles.h"
#import "TKTikTok.h"
#import "TKCommon.h"

@interface TKSubtitles ()
@property (nonatomic, strong) NSArray *cues;       // @[ start, end, text ]
@end

@implementation TKSubtitles

// TikTok names a track "eng-US", "ces-CZ"...: the first part is the ISO 639-2 code; the device speaks ISO 639-1
static NSString *TKThreeLetterLanguage(NSString *code)
{
    static NSDictionary *map;
    if (!map) map = @{ @"cs": @"ces", @"sk": @"slk", @"en": @"eng", @"de": @"deu", @"pl": @"pol", @"ru": @"rus", @"uk": @"ukr",
                       @"es": @"spa", @"pt": @"por", @"fr": @"fra", @"it": @"ita", @"hu": @"hun", @"tr": @"tur", @"nl": @"nld" };
    return map[[code lowercaseString]] ?: [code lowercaseString];
}

+ (NSDictionary *)bestTrackOf:(NSArray *)tracks
{
    if (!tracks.count) return nil;
    NSMutableArray *wanted = [NSMutableArray array];
    for (NSString *l in [NSLocale preferredLanguages]) {
        NSString *code = TKThreeLetterLanguage([[l componentsSeparatedByString:@"-"] firstObject]);
        if (code.length && ![wanted containsObject:code]) [wanted addObject:code];
        if (wanted.count >= 3) break;
    }
    if ([wanted containsObject:@"ces"] && ![wanted containsObject:@"slk"]) [wanted addObject:@"slk"];   // (close enough)
    NSString *(^langOf)(NSDictionary *) = ^NSString *(NSDictionary *t) {
        return [[[TKStr(t[@"lang"]) componentsSeparatedByString:@"-"] firstObject] lowercaseString] ?: @"";
    };
    for (NSString *code in wanted) {                       // the device's languages: what is spoken first, then a translation
        NSDictionary *mt = nil;
        for (NSDictionary *t in tracks) {
            if (![langOf(t) isEqualToString:code]) continue;
            if (![[TKStr(t[@"source"]) uppercaseString] isEqualToString:@"MT"]) return t;
            if (!mt) mt = t;
        }
        if (mt) return mt;
    }
    for (NSDictionary *t in tracks) if (![[TKStr(t[@"source"]) uppercaseString] isEqualToString:@"MT"]) return t;   // what is spoken
    for (NSDictionary *t in tracks) if ([langOf(t) isEqualToString:@"eng"]) return t;
    return tracks[0];
}

+ (NSCache *)cache
{
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [[NSCache alloc] init]; cache.countLimit = 40; });
    return cache;
}

+ (void)loadTrack:(NSDictionary *)track completion:(void (^)(TKSubtitles *))completion
{
    NSString *url = TKStr(track[@"url"]);
    if (!url.length) { completion(nil); return; }
    TKSubtitles *known = [[self cache] objectForKey:url];
    if (known) { completion(known); return; }
    [TKTikTok fetchText:url completion:^(NSString *text, NSError *error) {
        TKSubtitles *subs = text.length ? [self subtitlesFromWebVTT:text] : nil;
        if (subs.count) [[self cache] setObject:subs forKey:url];
        completion(subs.count ? subs : nil);
    }];
}

// "00:01:02.345" or "01:02.345"
static NSTimeInterval TKCueTime(NSString *s)
{
    NSArray *parts = [[s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] componentsSeparatedByString:@":"];
    double t = 0;
    for (NSString *p in parts) t = t * 60 + [[p stringByReplacingOccurrencesOfString:@"," withString:@"."] doubleValue];
    return t;
}

+ (TKSubtitles *)subtitlesFromWebVTT:(NSString *)text
{
    NSMutableArray *cues = [NSMutableArray array];
    NSString *normal = [[text stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"] stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
    static NSRegularExpression *tags;
    if (!tags) tags = [NSRegularExpression regularExpressionWithPattern:@"<[^>]*>" options:0 error:NULL];
    for (NSString *block in [normal componentsSeparatedByString:@"\n\n"]) {
        NSArray *lines = [block componentsSeparatedByString:@"\n"];
        for (NSUInteger i = 0; i < lines.count; i++) {
            NSRange arrow = [lines[i] rangeOfString:@"-->"];
            if (arrow.location == NSNotFound) continue;
            NSTimeInterval start = TKCueTime([lines[i] substringToIndex:arrow.location]);
            NSString *after = [[[lines[i] substringFromIndex:NSMaxRange(arrow)] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]
                               componentsSeparatedByString:@" "][0];        // (cue settings follow the time)
            NSTimeInterval end = TKCueTime(after);
            NSArray *textLines = [lines subarrayWithRange:NSMakeRange(i + 1, lines.count - i - 1)];
            NSString *cue = [[textLines componentsJoinedByString:@"\n"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            cue = [tags stringByReplacingMatchesInString:cue options:0 range:NSMakeRange(0, cue.length) withTemplate:@""];
            if (cue.length && end > start) [cues addObject:@[ @(start), @(end), cue ]];
            break;
        }
    }
    TKSubtitles *subs = [[TKSubtitles alloc] init];
    subs.cues = cues;
    return subs;
}

- (NSUInteger)count { return self.cues.count; }

- (NSString *)textAt:(NSTimeInterval)t
{
    for (NSArray *c in self.cues) {
        if (t < [c[0] doubleValue]) return nil;
        if (t <= [c[1] doubleValue]) return c[2];
    }
    return nil;
}

@end
