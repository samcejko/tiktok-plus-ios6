#import "TKSession.h"
#import "TKKeychain.h"
#import "TKDirectClient.h"
#import "TKTikTok.h"
#import "TKCommon.h"

NSString * const TKSessionDidChangeNotification = @"TKSessionDidChangeNotification";
static NSString * const TKSessionTokenKey = @"tikie.session";
static NSString * const TKSessionUserKey = @"tikie.user";

@interface TKSession ()
@property (nonatomic) NSUInteger generation;
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
        NSDictionary *saved = [TKDirectClient savedSession];
        _token = TKStr(saved[@"token"]);
        _user = TKDict(saved[@"user"]);
        // Legacy helper tokens/public profiles do not prove a direct session.
        [TKKeychain setString:nil forKey:TKSessionTokenKey];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:TKSessionUserKey];
    }
    return self;
}

- (BOOL)signedIn
{
    return self.token.length > 0 && self.handle.length > 0 && self.userId.length > 0;
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
    NSString *docs = TKFirst(paths);
    NSString *p1 = [docs stringByAppendingPathComponent:@"ttsession.json"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:p1]) return p1;
    NSString *p2 = [docs stringByAppendingPathComponent:@"ttcookies.json"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:p2]) return p2;
    return p1;
}

+ (BOOL)hasPendingCookieFile
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docs = TKFirst(paths);
    if ([[NSFileManager defaultManager] fileExistsAtPath:[docs stringByAppendingPathComponent:@"ttsession.json"]]) return YES;
    if ([[NSFileManager defaultManager] fileExistsAtPath:[docs stringByAppendingPathComponent:@"ttcookies.json"]]) return YES;
    return NO;
}

+ (NSString *)pendingCookieFileContent
{
    NSString *path = [self pendingCookieFilePath];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return nil;
    NSDictionary *attributes=[[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    if ([attributes[NSFileSize] unsignedLongLongValue] > 1024*1024) return nil;
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
    NSString *docs = TKFirst(paths);
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
    NSUInteger generation = ++self.generation;
    [TKTikTok sessionCreateWithCookies:cookieString completion:^(BOOL success, NSString *token, NSDictionary *user, NSError *error) {
        if (generation != self.generation) { if (completion) completion(NO, L(@"Session changed.")); return; }
        if (success && ![TKDirectClient commitSession:token]) { if (completion) completion(NO, L(@"The session could not be saved securely. Check the app installation.")); return; }
        if (!success || !token.length || !TKStr(user[@"userId"]).length || !TKStr(user[@"handle"]).length) {
            NSString *msg = error.localizedDescription ?: L(@"Invalid or expired session.");
            if (completion) completion(NO, msg);
            return;
        }
        self.token = token;
        self.user = user ?: @{};
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
    NSString *validatedToken = [self.token copy];
    [TKTikTok sessionValidateWithCompletion:^(BOOL valid, NSDictionary *user, NSError *error) {
        if (![self.token isEqualToString:validatedToken]) {
            if (completion) completion(NO);
            return;
        }
        if (error) {
            // A temporary network failure does not invalidate saved credentials.
            if (completion) completion(NO);
            return;
        }
        if (valid) {
            if (user.count) {
                self.user = user;

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
    ++self.generation;
    [TKTikTok sessionDeleteWithCompletion:nil];
    self.token = nil;
    self.user = nil;
    [TKKeychain setString:@"" forKey:TKSessionTokenKey];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:TKSessionUserKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:TKSessionDidChangeNotification object:self];
}

@end
