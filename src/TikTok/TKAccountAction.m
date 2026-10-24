#import "TKAccountAction.h"
#import "TKDirectParser.h"
#import "TKCommon.h"

static BOOL TKActionID(NSString *s)
{
    return s.length > 0 && s.length <= 30 && [s rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789"] invertedSet]].location == NSNotFound;
}

@implementation TKAccountAction
+ (NSDictionary *)request:(NSString *)action parameters:(NSDictionary *)parameters
{
    NSDictionary *p = TKDict(parameters); NSString *video = TKStr(p[@"video"]), *cid = TKStr(p[@"comment"]);
    BOOL on = [p[@"on"] isKindOfClass:[NSNumber class]] && [p[@"on"] boolValue];
    NSString *path = nil, *target = nil; NSMutableDictionary *q = [@{@"from_page":@"video"} mutableCopy];
    if ([action isEqualToString:@"like"]) {
        if (!TKActionID(video) || ![p[@"on"] isKindOfClass:[NSNumber class]]) return nil;
        path = @"/api/commit/item/digg/"; target = video;
        q[@"aweme_id"] = video; q[@"type"] = on ? @"1" : @"0";
    } else if ([action isEqualToString:@"follow"]) {
        NSString *uid = TKStr(p[@"user"]), *sec = TKStr(p[@"sec"]);
        if (!TKActionID(uid) || !sec.length || sec.length > 256 || [sec rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-=."] invertedSet]].location != NSNotFound || ![p[@"on"] isKindOfClass:[NSNumber class]]) return nil;
        path = @"/api/commit/follow/user/"; target = uid;
        [q addEntriesFromDictionary:@{@"user_id":uid,@"sec_user_id":sec,@"type":on ? @"1" : @"0",@"action_type":on ? @"1" : @"0",@"channel_id":@"0",@"from":@"18",@"fromWeb":@"1",@"from_pre":@"0",@"from_page":@"fyp"}];
    } else if ([action isEqualToString:@"commentLike"]) {
        if (!TKActionID(video) || !TKActionID(cid) || ![p[@"on"] isKindOfClass:[NSNumber class]]) return nil;
        path = @"/api/comment/digg/"; target = cid;
        [q addEntriesFromDictionary:@{@"aweme_id":video,@"cid":cid,@"digg_type":on ? @"1" : @"2",@"channel_id":@"0"}];
    } else if ([action isEqualToString:@"publish"]) {
        NSString *text = [TKStr(p[@"text"]) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!TKActionID(video) || !text.length || text.length > 2200 || [text rangeOfString:[NSString stringWithFormat:@"%C",(unichar)0]].location != NSNotFound || (cid.length && !TKActionID(cid))) return nil;
        path = @"/api/comment/publish/"; target = video;
        [q addEntriesFromDictionary:@{@"aweme_id":video,@"text":text,@"text_extra":@"[]"}];
        NSString *parent=TKStr(p[@"parent"]);
        if(parent.length && (!cid.length || !TKActionID(parent)))return nil;
        if (cid.length) { q[@"reply_id"] = parent.length ? parent : cid; q[@"reply_to_reply_id"] = parent.length ? cid : @"0"; }
    } else if ([action isEqualToString:@"deleteComment"]) {
        if (!TKActionID(cid) || !TKActionID(TKStr(p[@"owner"]))) return nil;
        path = @"/api/comment/delete/"; target = cid; q[@"cid"] = cid;
    } else return nil;
    return @{@"action":action,@"path":path,@"params":q,@"target":target,@"on":@(on)};
}

+ (BOOL)accepted:(NSDictionary *)response request:(NSDictionary *)request userId:(NSString *)userId
{
    if (![TKDirectParser successfulResponse:response] || !TKDict(request[@"params"]) || ![@[@"like",@"follow",@"publish",@"commentLike",@"deleteComment"] containsObject:request[@"action"]]) return NO;
    NSString *action = request[@"action"]; NSDictionary *q = request[@"params"];
    if ([action isEqualToString:@"publish"]) {
        NSDictionary *c = TKDict(response[@"comment"]), *u = TKDict(c[@"user"]);
        NSString *vid = TKStr(c[@"aweme_id"]);
        return TKActionID(TKStr(c[@"cid"])) && [TKStr(u[@"uid"]) isEqualToString:userId] &&
            [TKStr(c[@"text"]) isEqualToString:q[@"text"]] && (!vid.length || [vid isEqualToString:q[@"aweme_id"]]);
    }
    NSString *stateKey = [action isEqualToString:@"like"] ? @"is_digg" : ([action isEqualToString:@"commentLike"] ? @"is_digg" : nil);
    if (stateKey && response[stateKey] && (![response[stateKey] isKindOfClass:[NSNumber class]] || [response[stateKey] boolValue] != [request[@"on"] boolValue])) return NO;
    if ([action isEqualToString:@"follow"] && response[@"follow_status"] && (![response[@"follow_status"] isKindOfClass:[NSNumber class]] || ((TKInt(response[@"follow_status"]) == 1 || TKInt(response[@"follow_status"]) == 3) != [request[@"on"] boolValue]))) return NO;
    return YES;
}
@end
