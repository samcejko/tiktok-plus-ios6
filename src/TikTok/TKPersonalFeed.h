#import <Foundation/Foundation.h>
#import "TKFeedSource.h"

@interface TKPersonalFeed : NSObject <TKFeedSource>

@property (nonatomic) BOOL isFollowingMode;
@property (nonatomic, readonly) NSArray *videos;
@property (nonatomic, readonly) BOOL loading;

- (instancetype)initWithFollowingMode:(BOOL)followingMode;

@end
