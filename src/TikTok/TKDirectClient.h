#import <Foundation/Foundation.h>
#import "TKHTTP.h"

@interface TKDirectClient : NSObject
+ (TKHTTPTask *)getPath:(NSString *)path query:(NSString *)query completion:(TKJSONCompletion)completion;
+ (TKHTTPTask *)importCookies:(NSString *)input completion:(void (^)(BOOL, NSString *, NSDictionary *, NSError *))completion;
+ (TKHTTPTask *)validate:(void (^)(BOOL, NSDictionary *, NSError *))completion;
+ (TKHTTPTask *)performAction:(NSString *)action parameters:(NSDictionary *)parameters completion:(TKJSONCompletion)completion;
+ (TKHTTPTask *)checkActionReadiness:(void (^)(NSDictionary *flags))completion; // GET only, no secrets
+ (NSDictionary *)actionDiagnostics;
+ (BOOL)commitSession:(NSString *)token;
+ (NSDictionary *)savedSession;
+ (void)signOut;
@end
