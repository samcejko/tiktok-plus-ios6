#import <Foundation/Foundation.h>
#import "TKDirectParser.h"
#import "TKWebSignature.h"
#import "TKCommon.h"
#include <stdio.h>

static unsigned checks, failures;
static void check(BOOL ok, const char *label) { checks++; if(!ok){failures++;fprintf(stderr,"FAIL: %s\n",label);} }
static NSDictionary *format(NSString *codec,NSInteger w,NSInteger h,NSString *url) { return @{@"CodecType":codec,@"PlayAddr":@{@"Width":@(w),@"Height":@(h),@"UrlList":@[url]}}; }
int main(int argc,char **argv)
{
    @autoreleasepool {
        check(![TKDirectParser successfulResponse:nil],"empty is not success");
        check(![TKDirectParser successfulResponse:@{}],"empty dictionary is not success");
        check(![TKDirectParser successfulResponse:@{@"status_code":@0,@"statusCode":@100001}],"conflicting status fails");
        check([TKDirectParser successfulResponse:@{@"status_code":@0,@"statusCode":@0}],"both statuses succeed");
        check(![TKDirectParser successfulResponse:@{@"status_code":@"oops"}],"malformed status fails");
        check(![TKDirectParser successfulResponse:@{@"status_code":[NSNull null]}],"null status fails");
        check(![TKDirectParser URLString:@"http://cdn.invalid/video"].length,"cleartext media rejected");
        check(![TKDirectParser URLString:@"file:///etc/passwd"].length,"file URL rejected");
        check([[TKDirectParser URLString:@[@"https://cdn.invalid/a.webp",@"https://cdn.invalid/a.jpeg"]] hasSuffix:@"jpeg"],"JPEG preferred");
        NSDictionary *scope=[TKDirectParser scopeFromHTML:@"<html><script type='application/json' id='__UNIVERSAL_DATA_FOR_REHYDRATION__'> {\"__DEFAULT_SCOPE__\":{\"fixture\":42}} </script></html>"];
        check(TKInt(scope[@"fixture"])==42,"HTML script attribute order");
        check(![TKDirectParser scopeFromHTML:@"<html>challenge</html>"],"challenge is not content");
        check(![TKDirectParser scopeFromHTML:@"<script id=\"__UNIVERSAL_DATA_FOR_REHYDRATION__\">not json</script>"],"broken hydration fails");
        NSDictionary *account=@{@"message":@"success",@"data":@{@"user_id_str":@"123",@"username":@"fixture",@"screen_name":@"Fixture"}};
        NSError *error=nil;
        NSArray *cookies=[TKDirectParser cookiesFromString:@"{\"sessionid\":\"fixture-session\",\"uid_tt\":\"123\"}" error:&error];
        check(cookies.count==2 && !error,"JSON object cookie import");
        check([TKDirectParser verifiedAccount:account cookies:cookies]!=nil,"passport identity verified");
        check(![TKDirectParser verifiedAccount:@{@"userInfo":@{@"user":@{@"uniqueId":@"someone_else"}}} cookies:cookies],"public profile never authenticates");
        check(![TKDirectParser verifiedAccount:@{@"message":@"error",@"data":@{@"user_id":@"123",@"username":@"fixture"}} cookies:cookies],"unsuccessful passport with fields rejected");
        NSArray *other=[TKDirectParser cookiesFromString:@"sessionid=fixture-session; uid_tt=456" error:nil];
        check(![TKDirectParser verifiedAccount:account cookies:other],"cookie identity mismatch rejected");
        check(![TKDirectParser verifiedAccount:@{@"message":@"success",@"data":@{@"user_id":@123}} cookies:cookies],"incomplete identity rejected");
        check([TKDirectParser cookiesFromString:@"{\"cookies\":[{\"name\":\"sessionid\",\"value\":\"fixture-session\",\"domain\":\".tiktok.com\"}]}" error:nil].count==1,"Cookie-Editor wrapper");
        check([TKDirectParser cookiesFromString:@"# Netscape HTTP Cookie File\n#HttpOnly_.tiktok.com\tTRUE\t/\tTRUE\t0\tsessionid\tfixture-session" error:nil].count==1,"Netscape HTTP-only cookie");
        check([TKDirectParser cookiesFromString:@"Cookie: sessionid=fixture-session; uid_tt=123" error:nil].count==2,"header import");
        check(![TKDirectParser cookiesFromString:@"{\"sessionid\":\"abc\\r\\nX-Test: injected\"}" error:nil],"header injection rejected");
        check(![TKDirectParser cookiesFromString:@"[{\"name\":\"sessionid\",\"value\":\"fixture\",\"domain\":\"tiktok.com.evil.invalid\"}]" error:nil],"lookalike domain rejected");
        check(![TKDirectParser cookiesFromString:@"[{\"name\":\"sessionid\",\"value\":\"fixture\",\"expirationDate\":1}]" error:nil],"expired session rejected");
        check(![TKDirectParser cookiesFromString:@"ttwid=anonymous" error:nil],"anonymous cookies cannot sign in");
        check(![TKDirectParser cookiesFromString:@"sessionid=a; sessionid=b" error:nil],"ambiguous duplicate rejected");
        check(![TKDirectParser cookiesFromString:@"[]" error:nil],"empty cookie export rejected");
        check(![TKDirectParser cookiesFromString:@"{broken" error:nil],"malformed export rejected");
        check(![TKDirectParser cookiesFromString:@"[{\"name\":\"sessionid\",\"value\":null}]" error:nil],"null value rejected");
        NSMutableDictionary *item=[@{@"id":@"1234567890123456789",@"desc":@"Fixture",@"author":@{@"uniqueId":@"fixture",@"nickname":@"Fixture"},@"statsV2":@{@"diggCount":@"2147483648"},@"video":@{@"duration":@12,@"cover":@"https://cdn.invalid/cover.jpg",@"bitrateInfo":@[format(@"h265_hvc1",1080,1920,@"https://cdn.invalid/hevc"),format(@"h264",576,1024,@"https://cdn.invalid/small"),format(@"h264",720,1280,@"https://cdn.invalid/large")]}} mutableCopy];
        NSDictionary *v=[TKDirectParser video:item maxHeight:1024];
        check([v[@"playUrl"] isEqual:@"https://cdn.invalid/small"],"H264 within device resolution");
        check([v[@"id"] isEqual:@"1234567890123456789"],"64-bit video ID remains exact");
        check([[TKDirectParser video:item maxHeight:1920][@"playUrl"] isEqual:@"https://cdn.invalid/large"],"highest compatible rendition");
        check([[TKDirectParser video:item maxHeight:480][@"playUrl"] isEqual:@"https://cdn.invalid/small"],"smallest when all exceed screen");
        item[@"video"]=@{@"bitrateInfo":@[format(@"h265_hvc1",720,1280,@"https://cdn.invalid/hevc")]};
        check(![TKDirectParser video:item maxHeight:1280],"HEVC-only video is not called playable");
        item[@"video"]=@{@"PlayAddrStruct":@{@"UrlKey":@"fixture_h264_540p",@"Width":@576,@"Height":@1024,@"UrlList":@[@"https://cdn.invalid/fallback"]}};
        check([[TKDirectParser video:item maxHeight:1280][@"playUrl"] isEqual:@"https://cdn.invalid/fallback"],"explicit H264 fallback");
        item[@"video"]=@{@"PlayAddrStruct":@{@"UrlList":@[@"https://cdn.invalid/unknown"]}};
        check(![TKDirectParser video:item maxHeight:1280],"unknown fallback codec rejected");
        item[@"imagePost"]=@{@"images":@[@{@"imageURL":@{@"urlList":@[@"https://cdn.invalid/photo.webp",@"https://cdn.invalid/photo.jpeg"]}}]};
        v=[TKDirectParser video:item maxHeight:1280];
        check([v[@"type"] isEqual:@"photo"] && [v[@"images"] count]==1,"photo post supported without video");
        item[@"id"]=@"../../bad";check(![TKDirectParser video:item maxHeight:1280],"invalid video ID rejected");
        check(![TKDirectParser profile:@{@"user":@{@"uniqueId":@"fixture"}}],"public profile requires ID");
        check([TKDirectParser profile:@{@"user":@{@"uniqueId":@"fixture",@"id":@"123"},@"stats":@{@"followerCount":@100}}]!=nil,"public profile normalization");
        check(![TKDirectParser comment:@{@"cid":@"1",@"text":[NSNull null]}],"invalid comment dropped");
        check(TKInt([TKDirectParser comment:@{@"cid":@"1",@"text":@"Český text",@"reply_comment_total":@3}][@"replies"])==3,"comment and reply normalization");
        check([TKWebSignature(@"aid=1988&keyword=cats",@"fixture-browser",1700000000) isEqual:@"DFSzswVY4mTAN9rntmWx-e9WX7jJ"],"signature ASCII vector");
        check([TKWebSignature(@"aid=1988&keyword=%C4%8Desk%C3%BD%20pes",@"fixture-browser",1700000000) isEqual:@"DFSzswVYfjiAN9rntmWx-e9WX7nQ"],"signature Unicode query vector");
        check([TKWebSignature(@"",@"fixture-browser",1700000000) isEqual:@"DFSzswVY0IJAN9rntmWx-e9WX7nR"],"signature empty query vector");
        fprintf(stdout,"Direct parser: %u checks, %u failures\n",checks,failures);
    }
    return failures ? 1 : 0;
}
