#import "TKSession.h"
#import "TKKeychain.h"
#import "TKTikTok.h"
#import "TKCommon.h"

NSString * const TKSessionDidChangeNotification = @"TKSessionDidChangeNotification";
static NSString * const TKSessionTokenKey = @"tikie.session";
static NSString * const TKSessionUserKey = @"tikie.user";

@interface TKSession ()
@property (nonatomic, copy, readwrite) NSString *token;
@property (nonatomic, strong, readwrite) NSDictionary *user;
@end

@implementation TKSession

+ (instancetype)sharedSession
{
    static TKSession *sShared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sShared = [[TKSession alloc] init];
    });
    return sShared;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _token = [TKKeychain stringForKey:TKSessionTokenKey];
        _user = [[NSUserDefaults standardUserDefaults] dictionaryForKey:TKSessionUserKey];
    }
    return self;
}

- (BOOL)signedIn
{
    return self.token.length > 0;
}

- (NSString *)handle
{
    return TKStr(self.user[@"handle"]);
}

- (NSString *)displayName
{
    NSString *name = TKStr(self.user[@"name"]);
    return name.length ? name : self.handle;
}

- (NSString *)avatarURL
{
    return TKStr(self.user[@"avatar"]);
}

- (NSString *)secUid
{
    return TKStr(self.user[@"secUid"]);
}

- (NSString *)userId
{
    return TKStr(self.user[@"userId"]);
}

+ (NSString *)pendingCookieFilePath
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docs = paths.firstObject;
    NSString *p1 = [docs stringByAppendingPathComponent:@"ttsession.json"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:p1]) return p1;
    NSString *p2 = [docs stringByAppendingPathComponent:@"ttcookies.json"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:p2]) return p2;
    return p1;
}

+ (BOOL)hasPendingCookieFile
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docs = paths.firstObject;
    if ([[NSFileManager defaultManager] fileExistsAtPath:[docs stringByAppendingPathComponent:@"ttsession.json"]]) return YES;
    if ([[NSFileManager defaultManager] fileExistsAtPath:[docs stringByAppendingPathComponent:@"ttcookies.json"]]) return YES;
    return NO;
}

+ (NSString *)pendingCookieFileContent
{
    NSString *path = [self pendingCookieFilePath];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return nil;
    NSError *err = nil;
    NSString *content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&err];
    if (!content && !err) {
        content = [NSString stringWithContentsOfFile:path encoding:NSASCIIStringEncoding error:nil];
    }
    return content;
}

+ (void)deletePendingCookieFile
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docs = paths.firstObject;
    NSString *p1 = [docs stringByAppendingPathComponent:@"ttsession.json"];
    NSString *p2 = [docs stringByAppendingPathComponent:@"ttcookies.json"];
    [[NSFileManager defaultManager] removeItemAtPath:p1 error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:p2 error:nil];
}

- (void)importCookiesWithCompletion:(void(^)(BOOL success, NSString *errorMessage))completion
{
    NSString *content = [[self class] pendingCookieFileContent];
    if (!content.length) {
        if (completion) completion(NO, L(@"No ttsession.json file found in Documents."));
        return;
    }
    [self importCookiesString:content completion:completion];
}

- (void)importCookiesString:(NSString *)cookieString completion:(void(^)(BOOL success, NSString *errorMessage))completion
{
    [TKTikTok sessionCreateWithCookies:cookieString completion:^(BOOL success, NSString *token, NSDictionary *user, NSError *error) {
        if (!success || !token.length) {
            NSString *msg = error.localizedDescription ?: L(@"Invalid or expired session.");
            if (completion) completion(NO, msg);
            return;
        }
        self.token = token;
        self.user = user ?: @{};
        [TKKeychain setString:token forKey:TKSessionTokenKey];
        if (user) {
            [[NSUserDefaults standardUserDefaults] setObject:user forKey:TKSessionUserKey];
            [[NSUserDefaults standardUserDefaults] synchronize];
        }
        [[self class] deletePendingCookieFile];
        [[NSNotificationCenter defaultCenter] postNotificationName:TKSessionDidChangeNotification object:self];
        if (completion) completion(YES, nil);
    }];
}

- (void)validateWithCompletion:(void(^)(BOOL valid))completion
{
    if (!self.signedIn) {
        if (completion) completion(NO);
        return;
    }
    [TKTikTok sessionValidateWithCompletion:^(BOOL valid, NSDictionary *user, NSError *error) {
        if (valid) {
            if (user.count) {
                self.user = user;
                [[NSUserDefaults standardUserDefaults] setObject:user forKey:TKSessionUserKey];
                [[NSUserDefaults standardUserDefaults] synchronize];
            }
            if (completion) completion(YES);
        } else {
            [self signOut];
            if (completion) completion(NO);
        }
    }];
}

- (void)signOut
{
    [TKTikTok sessionDeleteWithCompletion:nil];
    self.token = nil;
    self.user = nil;
    [TKKeychain setString:@"" forKey:TKSessionTokenKey];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:TKSessionUserKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:TKSessionDidChangeNotification object:self];
}

@end
