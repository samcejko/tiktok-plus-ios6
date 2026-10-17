#import "TKConnectionPool.h"
#import "TKTLSSocket.h"
#import "TKCommon.h"

static const NSTimeInterval TKIdleTimeout = 25;     // most servers drop idle connections after 5 to 60 s
static const NSUInteger TKMaxIdlePerKey = 6;
static const NSUInteger TKMaxIdleTotal = 24;

@interface TKPooledConnection : NSObject
@property (nonatomic, strong) TKTLSSocket *socket;
@property (nonatomic) NSTimeInterval lastUsed;
@end

@implementation TKPooledConnection
@end

@implementation TKConnectionPool {
    NSMutableDictionary *_idle;     // key -> NSMutableArray<TKPooledConnection>
    NSUInteger _count;
    NSUInteger _reuses;
}

+ (instancetype)shared
{
    static TKConnectionPool *pool;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ pool = [[TKConnectionPool alloc] init]; });
    return pool;
}

- (instancetype)init
{
    self = [super init];
    if (self) _idle = [NSMutableDictionary dictionary];
    return self;
}

// Must be called with the lock held. Moves expired connections into `dead`.
- (void)pruneLocked:(NSMutableArray *)dead
{
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    NSMutableArray *emptyKeys = [NSMutableArray array];
    for (NSString *key in _idle) {
        NSMutableArray *list = _idle[key];
        for (NSInteger i = (NSInteger)list.count - 1; i >= 0; i--) {
            TKPooledConnection *c = list[(NSUInteger)i];
            if (now - c.lastUsed > TKIdleTimeout) {
                [dead addObject:c.socket];
                [list removeObjectAtIndex:(NSUInteger)i];
                _count--;
            }
        }
        if (!list.count) [emptyKeys addObject:key];
    }
    [_idle removeObjectsForKeys:emptyKeys];
}

- (TKTLSSocket *)checkoutSocketForKey:(NSString *)key
{
    if (!key) return nil;
    NSMutableArray *dead = [NSMutableArray array];
    TKTLSSocket *result = nil;
    @synchronized (self) {
        [self pruneLocked:dead];
        NSMutableArray *list = _idle[key];
        while (list.count && !result) {
            TKPooledConnection *c = [list lastObject];
            [list removeLastObject];
            _count--;
            if ([c.socket isLikelyAlive]) result = c.socket;
            else [dead addObject:c.socket];
        }
        if (result) _reuses++;
    }
    for (TKTLSSocket *s in dead) [s close];
    return result;
}

- (void)checkinSocket:(TKTLSSocket *)socket forKey:(NSString *)key
{
    if (!socket || !key) return;
    NSMutableArray *dead = [NSMutableArray array];
    @synchronized (self) {
        [self pruneLocked:dead];
        NSMutableArray *list = _idle[key];
        if (!list) {
            list = [NSMutableArray array];
            _idle[key] = list;
        }
        if (list.count >= TKMaxIdlePerKey || _count >= TKMaxIdleTotal) {
            [dead addObject:socket];
        } else {
            TKPooledConnection *c = [[TKPooledConnection alloc] init];
            c.socket = socket;
            c.lastUsed = [NSDate timeIntervalSinceReferenceDate];
            [list addObject:c];
            _count++;
        }
    }
    for (TKTLSSocket *s in dead) [s close];
}

- (void)drain
{
    NSMutableArray *dead = [NSMutableArray array];
    @synchronized (self) {
        for (NSString *key in _idle) {
            for (TKPooledConnection *c in _idle[key]) [dead addObject:c.socket];
        }
        [_idle removeAllObjects];
        _count = 0;
    }
    for (TKTLSSocket *s in dead) [s close];
    if (dead.count) TKLog(@"Connection pool drained (%lu closed)", (unsigned long)dead.count);
}

- (NSUInteger)idleCount
{
    @synchronized (self) { return _count; }
}

- (NSUInteger)reuseCount
{
    @synchronized (self) { return _reuses; }
}

@end
