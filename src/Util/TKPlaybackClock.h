#import <Foundation/Foundation.h>
extern NSString * const TKPlaybackClockDidChange;
@interface TKPlaybackClock : NSObject
+ (instancetype)shared;
- (void)startForSeconds:(NSTimeInterval)seconds;
- (void)cancel;
- (void)check;
@property (nonatomic, readonly) BOOL expired;
@property (nonatomic, readonly) NSTimeInterval remaining;
@end
