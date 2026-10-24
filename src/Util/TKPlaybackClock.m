#import "TKPlaybackClock.h"
#import <dispatch/dispatch.h>
#include <math.h>
NSString * const TKPlaybackClockDidChange = @"TKPlaybackClockDidChange";
@interface TKPlaybackClock ()
@property (nonatomic) NSTimeInterval deadline;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic) BOOL notified;
@end
@implementation TKPlaybackClock
+ (instancetype)shared { static TKPlaybackClock *clock; static dispatch_once_t once; dispatch_once(&once,^{ clock=[[self alloc] init]; }); return clock; }
- (instancetype)init
{
    if((self=[super init])) {
        _deadline=[[NSUserDefaults standardUserDefaults] doubleForKey:@"sleepDeadline"];
        if(_deadline>[[NSDate date] timeIntervalSince1970]) _timer=[NSTimer scheduledTimerWithTimeInterval:_deadline-[[NSDate date] timeIntervalSince1970] target:self selector:@selector(check) userInfo:nil repeats:NO];
    }
    return self;
}
- (BOOL)expired { return self.deadline>0 && self.deadline<=[[NSDate date] timeIntervalSince1970]; }
- (NSTimeInterval)remaining { return MAX(0,self.deadline-[[NSDate date] timeIntervalSince1970]); }
- (void)changed { [[NSNotificationCenter defaultCenter] postNotificationName:TKPlaybackClockDidChange object:self]; }
- (void)startForSeconds:(NSTimeInterval)seconds
{
    if(!isfinite(seconds) || seconds<0)seconds=0;
    [self.timer invalidate]; self.timer=nil; self.notified=NO;
    self.deadline=seconds>0 ? [[NSDate date] timeIntervalSince1970]+MIN(seconds,24*3600) : 0;
    [[NSUserDefaults standardUserDefaults] setDouble:self.deadline forKey:@"sleepDeadline"]; [[NSUserDefaults standardUserDefaults] synchronize];
    if(seconds>0)self.timer=[NSTimer scheduledTimerWithTimeInterval:MIN(seconds,24*3600) target:self selector:@selector(check) userInfo:nil repeats:NO];
    [self changed];
}
- (void)cancel { [self startForSeconds:0]; }
- (void)check
{
    if(self.expired && !self.notified) { self.notified=YES; [self.timer invalidate]; self.timer=nil; [self changed]; }
}
@end
