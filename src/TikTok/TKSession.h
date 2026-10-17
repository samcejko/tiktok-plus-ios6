#import <Foundation/Foundation.h>

extern NSString * const TKSessionDidChangeNotification;

@interface TKSession : NSObject

+ (instancetype)sharedSession;

@property (nonatomic, readonly) BOOL signedIn;
@property (nonatomic, copy, readonly) NSString *token;
@property (nonatomic, strong, readonly) NSDictionary *user;
@property (nonatomic, readonly) NSString *handle;
@property (nonatomic, readonly) NSString *displayName;
@property (nonatomic, readonly) NSString *avatarURL;
@property (nonatomic, readonly) NSString *secUid;
@property (nonatomic, readonly) NSString *userId;

// Method A: Check for ttsession.json or ttcookies.json in Documents/
+ (BOOL)hasPendingCookieFile;
+ (NSString *)pendingCookieFilePath;
+ (NSString *)pendingCookieFileContent;
+ (void)deletePendingCookieFile;

- (void)importCookiesWithCompletion:(void(^)(BOOL success, NSString *errorMessage))completion;
- (void)importCookiesString:(NSString *)cookieString completion:(void(^)(BOOL success, NSString *errorMessage))completion;
- (void)validateWithCompletion:(void(^)(BOOL valid))completion;
- (void)signOut;

@end
