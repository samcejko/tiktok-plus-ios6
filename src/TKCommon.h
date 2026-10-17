// Shared macros and constants. Everything here must be iOS 6.0 safe.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// Any API newer than the iOS 6.0 deployment target is a hard error in files that include this header.
#pragma clang diagnostic error "-Wunguarded-availability"

#define L(key) NSLocalizedString((key), nil)
#define TKIsPad() (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)
#define TKLog(fmt, ...) NSLog((@"[Tikie] " fmt), ##__VA_ARGS__)

// Runs a block on the main thread (immediately if already there).
static inline void TKMain(dispatch_block_t block)
{
    if ([NSThread isMainThread]) block();
    else dispatch_async(dispatch_get_main_queue(), block);
}

extern NSString * const TKErrorDomain;
extern NSString * const TKThemeDidChangeNotification;
extern NSString * const TKSettingsDidChangeNotification;
extern NSString * const TKLibraryDidChangeNotification;     // subscriptions, history or watch later changed

// NSError codes in TKErrorDomain (HTTP errors use the HTTP status as code)
enum {
    TKErrorNetwork        = -1,
    TKErrorTLS            = -2,
    TKErrorCertificate    = -3,
    TKErrorTimeout        = -4,
    TKErrorCancelled      = -5,
    TKErrorBadResponse    = -6,
    TKErrorDNS            = -7,
    TKErrorConnect        = -8,
    TKErrorConnectionLost = -9,
    TKErrorAPI            = -10,   // YouTube answered, but with an error
    TKErrorOffline        = -11,   // the live stream has not started
    TKErrorAuth           = -12,   // a signed-in viewer is required (age restriction)
    TKErrorRestricted     = -13,   // private, blocked in this country...
};

NSError *TKMakeError(NSInteger code, NSString *message);

// JSON values as the type the caller expects, nil/0 for anything else (NSNull, wrong type)
NSString *TKStr(id value);         // numbers become their decimal string
NSDictionary *TKDict(id value);
NSArray *TKArr(id value);
NSInteger TKInt(id value);
double TKDbl(id value);
BOOL TKBool(id value);

// "2026-10-02T17:31:00Z" and "2026-10-02T17:31:05.042684Z"
NSDate *TKDateFromISO(NSString *string);
