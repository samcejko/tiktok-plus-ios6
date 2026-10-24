#import <Foundation/Foundation.h>

// Only explicit user gestures call the client. This pure protocol layer never sends requests.
@interface TKAccountAction : NSObject
+ (NSDictionary *)request:(NSString *)action parameters:(NSDictionary *)parameters;
+ (BOOL)accepted:(NSDictionary *)response request:(NSDictionary *)request userId:(NSString *)userId;
@end
