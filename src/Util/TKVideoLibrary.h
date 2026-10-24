#import <Foundation/Foundation.h>

// Local library metadata only: no expiring playback URLs or account credentials.
@interface TKVideoLibrary : NSObject
+ (NSDictionary *)metadata:(NSDictionary *)video;
+ (NSArray *)addingVideo:(NSDictionary *)video toList:(NSArray *)list limit:(NSUInteger)limit;
+ (NSArray *)videos:(NSArray *)videos matching:(NSString *)query;
@end
