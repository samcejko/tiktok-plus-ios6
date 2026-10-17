#import "TKCommon.h"

#include <stdio.h>
#include <string.h>
#include <time.h>

NSString * const TKErrorDomain                   = @"com.samcejko.Tikie";
NSString * const TKThemeDidChangeNotification     = @"TKThemeDidChangeNotification";
NSString * const TKSettingsDidChangeNotification  = @"TKSettingsDidChangeNotification";
NSString * const TKLibraryDidChangeNotification   = @"TKLibraryDidChangeNotification";

NSError *TKMakeError(NSInteger code, NSString *message)
{
    if (!message) message = @"Unknown error";
    return [NSError errorWithDomain:TKErrorDomain code:code userInfo:@{ NSLocalizedDescriptionKey: message }];
}

NSString *TKStr(id value)
{
    if ([value isKindOfClass:[NSString class]]) return value;
    if ([value isKindOfClass:[NSNumber class]]) return [value stringValue];
    return nil;
}

NSDictionary *TKDict(id value)
{
    return [value isKindOfClass:[NSDictionary class]] ? value : nil;
}

NSArray *TKArr(id value)
{
    return [value isKindOfClass:[NSArray class]] ? value : nil;
}

NSInteger TKInt(id value)
{
    if ([value isKindOfClass:[NSNumber class]] || [value isKindOfClass:[NSString class]]) return [value integerValue];
    return 0;
}

double TKDbl(id value)
{
    if ([value isKindOfClass:[NSNumber class]] || [value isKindOfClass:[NSString class]]) return [value doubleValue];
    return 0;
}

BOOL TKBool(id value)
{
    if ([value isKindOfClass:[NSNumber class]] || [value isKindOfClass:[NSString class]]) return [value boolValue];
    return NO;
}

NSDate *TKDateFromISO(NSString *string)
{
    if (![string isKindOfClass:[NSString class]] || string.length < 19) return nil;
    // (NSDateFormatter is slow and not thread safe; the format is fixed, so the fields are read directly)
    int y = 0, mo = 0, d = 0, h = 0, mi = 0;
    double s = 0;
    if (sscanf([string UTF8String], "%d-%d-%dT%d:%d:%lf", &y, &mo, &d, &h, &mi, &s) != 6) return nil;
    struct tm t;
    memset(&t, 0, sizeof(t));
    t.tm_year = y - 1900;
    t.tm_mon = mo - 1;
    t.tm_mday = d;
    t.tm_hour = h;
    t.tm_min = mi;
    t.tm_sec = (int)s;
    time_t seconds = timegm(&t);
    if (seconds == (time_t)-1) return nil;
    return [NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)seconds + (s - (int)s)];
}
