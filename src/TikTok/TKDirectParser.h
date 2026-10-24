#import <Foundation/Foundation.h>

// Pure parsing, shared by the direct client and the native fixture tests.
@interface TKDirectParser : NSObject
+ (NSDictionary *)scopeFromHTML:(NSString *)html;
+ (NSDictionary *)video:(NSDictionary *)item maxHeight:(NSInteger)height;
+ (NSDictionary *)profile:(NSDictionary *)info;
+ (NSDictionary *)comment:(NSDictionary *)item;
+ (NSArray *)cookiesFromString:(NSString *)input error:(NSError **)error;
+ (NSDictionary *)verifiedAccount:(NSDictionary *)response cookies:(NSArray *)cookies;
+ (NSDictionary *)account:(NSDictionary *)account matchingProfile:(NSDictionary *)profile;
+ (BOOL)successfulResponse:(NSDictionary *)response;
+ (NSString *)URLString:(id)value;
@end
