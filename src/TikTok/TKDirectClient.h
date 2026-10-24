#import <Foundation/Foundation.h>
#import "TKHTTP.h"

@interface TKDirectClient : NSObject
+ (TKHTTPTask *)getPath:(NSString *)path query:(NSString *)query completion:(TKJSONCompletion)completion;
+ (TKHTTPTask *)importCookies:(NSString *)input completion:(void (^)(BOOL, NSString *, NSDictionary *, NSError *))completion;
+ (TKHTTPTask *)validate:(void (^)(BOOL, NSDictionary *, NSError *))completion;
+ (BOOL)commitSession:(NSString *)token;
+ (NSDictionary *)savedSession;
+ (void)signOut;
@end
