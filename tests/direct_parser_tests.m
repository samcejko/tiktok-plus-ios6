#import <Foundation/Foundation.h>
#import "TKDirectParser.h"
#import "TKWebSignature.h"
#import "TKCommon.h"
#import "../src/Util/TKVideoLibrary.h"
#include <stdio.h>

static unsigned checks, failures;
static void check(BOOL ok, const char *label) { checks++; if(!ok){failures++;fprintf(stderr,"FAIL: %s\n",label);} }
static NSDictionary *format(NSString *codec,NSInteger w,NSInteger h,NSString *url) { return @{@"CodecType":codec,@"PlayAddr":@{@"Width":@(w),@"Height":@(h),@"UrlList":@[url]}}; }
int TKRunDirectParserTests(void)
{
    checks=failures=0;
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
        check([TKDirectParser verifiedAccount:account cookies:other]!=nil,"opaque tracking cookies cannot override authenticated identity");
        NSDictionary *auth=[TKDirectParser verifiedAccount:account cookies:cookies];
        check(![TKDirectParser account:auth matchingProfile:@{@"id":@"456",@"handle":@"someone_else"}],"different public profile cannot be committed");
        check(![TKDirectParser account:nil matchingProfile:@{@"id":@"123",@"handle":@"fixture"}],"profile without authenticated account rejected");
        check([TKDirectParser account:auth matchingProfile:@{@"id":@"123",@"handle":@"fixture",@"secUid":@"fixture-sec"}]!=nil,"matching authenticated ID can enrich profile");
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
        NSDictionary *first = @{@"id":@"123", @"author":@"Fixture", @"desc":@"Český příspěvek", @"music":@"Test Song", @"tags":@[@"Kočka"], @"playUrl":@"https://expired.invalid/video", @"sessionid":@"must-not-persist", @"watchedAt":@123};
        NSArray *library = [TKVideoLibrary addingVideo:first toList:@[] limit:200];
        check(library.count == 1, "first history entry is added");
        check(!library[0][@"playUrl"] && !library[0][@"sessionid"], "library keeps no playback URLs or session fields");
        check([library[0][@"watchedAt"] isEqual:@123], "viewing timestamp retained");
        library = [TKVideoLibrary addingVideo:@{@"id":@"456", @"author":@"Other"} toList:library limit:200];
        check([library[0][@"id"] isEqual:@"456"], "newest history entry is first");
        library = [TKVideoLibrary addingVideo:first toList:library limit:200];
        check(library.count == 2 && [library[0][@"id"] isEqual:@"123"], "revisit moves existing entry without duplicate");
        check([TKVideoLibrary videos:library matching:@"cesky"].count == 1, "library caption search ignores diacritics");
        check([TKVideoLibrary videos:library matching:@"@FIXTURE"].count == 1, "library author search ignores case");
        check([TKVideoLibrary videos:library matching:@"song"].count == 1, "library sound search");
        check([TKVideoLibrary videos:library matching:@"kocka"].count == 1, "library hashtag search");
        check([TKVideoLibrary videos:library matching:@"missing"].count == 0, "library no match stays empty");
        check([TKVideoLibrary videos:library matching:@"  \n"].count == 2, "blank query keeps all posts");
        check([TKVideoLibrary addingVideo:nil toList:@[[NSNull null], @{}, first, first] limit:200].count == 1, "corrupt and duplicate library records removed");
        check(![TKVideoLibrary metadata:@{@"id":@"../bad"}], "invalid library ID rejected");
        check([TKVideoLibrary addingVideo:first toList:library limit:0].count == 0, "zero library limit respected");
        NSMutableArray *many = [NSMutableArray array];
        for (NSUInteger i=0;i<250;i++) [many addObject:@{@"id":[NSString stringWithFormat:@"%lu",(unsigned long)i]}];
        check([TKVideoLibrary addingVideo:first toList:many limit:200].count == 200, "history limit bounds storage");
        check([TKVideoLibrary videos:@[[NSNull null],first] matching:@"fixture"].count == 1, "malformed filtered record ignored");
        check([[TKVideoLibrary normalizedHandle:@" @Fixture.Name \n"] isEqual:@"fixture.name"], "creator handle normalized");
        check([[TKVideoLibrary normalizedHandle:@"@ТЕСТ"] isEqual:@"тест"], "Unicode creator handle supported");
        check(![TKVideoLibrary normalizedHandle:@"https://tiktok.com/@fixture"], "URL cannot become a creator handle");
        check(![TKVideoLibrary normalizedHandle:@"bad/name"], "creator path separators rejected");
        check(![TKVideoLibrary normalizedHandle:@"  "], "empty creator handle rejected");
        check([TKVideoLibrary video:first blockedByCreators:@[@"fixture"] keywords:@[] hidePhotos:NO maxDuration:0], "hidden creator excluded case insensitively");
        check(![TKVideoLibrary video:first blockedByCreators:@[@"someone"] keywords:@[] hidePhotos:NO maxDuration:0], "other creators remain available");
        check([TKVideoLibrary video:first blockedByCreators:@[] keywords:@[@"CESKY"] hidePhotos:NO maxDuration:0], "caption filter ignores case and accents");
        check([TKVideoLibrary video:first blockedByCreators:@[] keywords:@[@"song"] hidePhotos:NO maxDuration:0], "sound keyword filter");
        check([TKVideoLibrary video:first blockedByCreators:@[] keywords:@[@"kocka"] hidePhotos:NO maxDuration:0], "hashtag keyword filter");
        check(![TKVideoLibrary video:first blockedByCreators:@[] keywords:@[@"",@"absent"] hidePhotos:NO maxDuration:0], "empty or absent keywords do not hide posts");
        check([TKVideoLibrary video:@{@"type":@"photo"} blockedByCreators:@[] keywords:@[] hidePhotos:YES maxDuration:0], "photo filter excludes slideshows");
        check(![TKVideoLibrary video:@{@"type":@"photo"} blockedByCreators:@[] keywords:@[] hidePhotos:NO maxDuration:0], "photo filter can be disabled");
        check([TKVideoLibrary video:@{@"duration":@61} blockedByCreators:@[] keywords:@[] hidePhotos:NO maxDuration:60], "long video excluded");
        check(![TKVideoLibrary video:@{@"duration":@60} blockedByCreators:@[] keywords:@[] hidePhotos:NO maxDuration:60], "duration limit boundary included");
        check(![TKVideoLibrary video:@{@"duration":@1000} blockedByCreators:@[] keywords:@[] hidePhotos:NO maxDuration:0], "unlimited duration supported");
        check([[TKVideoLibrary collectionName:@"  Česká kolekce  "] isEqual:@"Česká kolekce"], "collection name trimmed with Unicode retained");
        check(![TKVideoLibrary collectionName:@"\n"], "empty collection rejected");
        check(![TKVideoLibrary collectionName:@"bad\nname"], "collection control characters rejected");
        check(![TKVideoLibrary collectionName:[@"x" stringByPaddingToLength:61 withString:@"x" startingAtIndex:0]], "overlong collection name rejected");
        fprintf(stdout,"Direct parser and library: %u checks, %u failures\n",checks,failures);
    }
    return failures ? 1 : 0;
}

#ifndef TK_TESTS_EMBEDDED
int main(int argc,char **argv) { return TKRunDirectParserTests(); }
#endif
