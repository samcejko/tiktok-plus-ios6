#import <Foundation/Foundation.h>
#import "TKDirectParser.h"
#import "TKAccountAction.h"
#import "TKWebSignature.h"
#import "TKGnarlySignature.h"
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
        NSDictionary *like=[TKAccountAction request:@"like" parameters:@{@"video":@"1234567890123456789",@"on":@YES}];
        NSDictionary *unlike=[TKAccountAction request:@"like" parameters:@{@"video":@"1234567890123456789",@"on":@NO}];
        check([like[@"params"][@"type"] isEqual:@"1"] && [unlike[@"params"][@"type"] isEqual:@"0"], "video like and unlike are different account actions");
        check([like[@"path"] isEqual:@"/api/commit/item/digg/"], "like uses allowlisted write endpoint");
        check(![TKAccountAction request:@"like" parameters:@{@"video":@"../evil",@"on":@YES}], "write rejects nonnumeric target");
        check(![TKAccountAction request:@"like" parameters:@{@"video":@"123"}], "missing desired state rejected");
        check(![TKAccountAction request:@"like" parameters:@{@"video":@"123",@"on":@"false"}], "string state cannot silently become true");
        check(![TKAccountAction request:@"arbitrary/path" parameters:@{}], "unknown action rejected");
        check(![TKAccountAction accepted:@{} request:like userId:@"42"], "empty write response is never success");
        check(![TKAccountAction accepted:@{@"success":@YES} request:like userId:@"42"], "missing explicit status rejected");
        check(![TKAccountAction accepted:@{@"status_code":@8} request:like userId:@"42"], "server-rejected write stays unsuccessful");
        check(![TKAccountAction accepted:@{@"status_code":@0,@"is_digg":@NO} request:like userId:@"42"], "contradictory like acknowledgement rejected");
        check([TKAccountAction accepted:@{@"status_code":@0,@"is_digg":@YES} request:like userId:@"42"], "explicit like acknowledgement accepted");
        check([TKAccountAction accepted:@{@"status_code":@0,@"is_digg":@NO} request:unlike userId:@"42"], "unlike acknowledgement accepted");
        check(![TKAccountAction accepted:@{@"status_code":@0} request:@{} userId:@"42"], "unknown acknowledgement contract rejected");
        NSDictionary *follow=[TKAccountAction request:@"follow" parameters:@{@"user":@"42",@"sec":@"MS4wLjAB_fixture",@"on":@YES}];
        check([follow[@"params"][@"action_type"] isEqual:@"1"] && [follow[@"params"][@"fromWeb"] isEqual:@"1"], "follow carries required web parameters");
        check(![TKAccountAction request:@"follow" parameters:@{@"user":@"42",@"sec":@"bad\nheader",@"on":@YES}], "follow secondary ID rejects injection");
        check(![TKAccountAction accepted:@{@"status_code":@0,@"follow_status":@0} request:follow userId:@"42"], "follow status must match requested action");
        check([TKAccountAction accepted:@{@"status_code":@0,@"follow_status":@3} request:follow userId:@"42"], "mutual follow counts as followed");
        NSDictionary *clike=[TKAccountAction request:@"commentLike" parameters:@{@"video":@"123",@"comment":@"456",@"on":@NO}];
        check([clike[@"params"][@"digg_type"] isEqual:@"2"], "comment unlike has its own protocol value");
        NSDictionary *publish=[TKAccountAction request:@"publish" parameters:@{@"video":@"123",@"text":@"  Český text 😀  ",@"comment":@"456"}];
        check([publish[@"params"][@"text"] isEqual:@"Český text 😀"], "Unicode draft text preserved and trimmed");
        check([publish[@"params"][@"reply_id"] isEqual:@"456"] && [publish[@"params"][@"text_extra"] isEqual:@"[]"], "reply targets actual parent comment");
        check(![TKAccountAction request:@"publish" parameters:@{@"video":@"123",@"text":@"  \n"}], "blank comment cannot be sent");
        check(![TKAccountAction request:@"publish" parameters:@{@"video":@"123",@"text":[@"x" stringByPaddingToLength:2201 withString:@"x" startingAtIndex:0]}], "overlong comment rejected before network");
        NSDictionary *posted=@{@"status_code":@0,@"comment":@{@"cid":@"789",@"text":@"Český text 😀",@"aweme_id":@"123",@"user":@{@"uid":@"42"}}};
        check([TKAccountAction accepted:posted request:publish userId:@"42"], "posted comment must include real ID and current author");
        check(![TKAccountAction accepted:posted request:publish userId:@"43"], "another account cannot acknowledge our comment");
        check(![TKAccountAction accepted:@{@"status_code":@0} request:publish userId:@"42"], "status-only comment response cannot create fake comment");
        check(![TKAccountAction request:@"deleteComment" parameters:@{@"comment":@"456"}], "delete requires verified ownership metadata");
        check([TKAccountAction request:@"deleteComment" parameters:@{@"comment":@"456",@"owner":@"42"}]!=nil, "own comment delete request supported");
        item[@"id"]=@"123";item[@"digged"]=@YES;
        check([[TKDirectParser video:item maxHeight:1280][@"liked"] boolValue], "TikTok liked state preserved separately from local save");
        [item removeObjectForKey:@"digged"];
        check(![TKDirectParser video:item maxHeight:1280][@"liked"], "missing liked state remains unknown");
        check([[TKDirectParser profile:@{@"user":@{@"uniqueId":@"fixture",@"id":@"42",@"relation":@3}}][@"relation"] intValue]==3, "profile relationship preserved");
        check(![TKDirectParser profile:@{@"user":@{@"uniqueId":@"fixture",@"id":@"42"}}][@"relation"], "missing relationship remains unknown");
        NSDictionary *commentState=[TKDirectParser comment:@{@"cid":@"456",@"text":@"test",@"user_digged":@1,@"user":@{@"uid":@"42"}}];
        check([commentState[@"userId"] isEqual:@"42"] && [commentState[@"liked"] boolValue], "comment owner and liked state preserved");
        NSDictionary *nested=[TKAccountAction request:@"publish" parameters:@{@"video":@"123",@"comment":@"456",@"parent":@"789",@"text":@"Reply"}];
        check([nested[@"params"][@"reply_id"] isEqual:@"789"] && [nested[@"params"][@"reply_to_reply_id"] isEqual:@"456"], "nested reply retains root and selected child IDs");
        check(![TKAccountAction request:@"publish" parameters:@{@"video":@"123",@"parent":@"789",@"text":@"Reply"}], "reply root cannot exist without reply target");
        uint8_t entropy96[96];for(unsigned i=0;i<96;i++)entropy96[i]=(uint8_t)i;
        NSData *currentEntropy=[NSData dataWithBytes:entropy96 length:sizeof(entropy96)];
        check([TKCurrentSignedQueryFixture(@"aid=1988&browser_version=5.0%20(Windows)&itemId=123",@"",@"fixture-browser",@"fixture_token-=",1700000000u,123456789u,987654321u,1u,currentEntropy) isEqual:@"aid=1988&browser_version=5.0%20(Windows)&itemId=123&X-Dynosaur=MPcWb5lNTZhTsNxiuc/mFb9lxN-I2xE2CZu0uIeb0ZAU9uWD9kk6tIwZbVvXS0zpS8Io3NfnUV/dv9bQvJZ4gQnGDMGjE9RiEkeBSQrVSeOHGOwnp4KFr2C1zoptlWqkX2wN/it3IGzgmGsJc/M0xxF44fhF7QyUi36IgNpnsD2bkBL9-t2x8AanOlgkai/s0MryEArAs6UTa2DhX0eprkcOAuPGL5iH6V0Rmm7wdLWrh3jjGM4hrhAvcTksqqPa7xwL0hLgeLHFmjskDNqYX4E61BX41xbGcJ1fS3OTXn6Kp6wYPHwqum2Kjzh6bN-jzwyGgDG0ezUoVrBpEEaWtvfbiFnKfe5Xp1eRpw-qhJS0GSEcE1vOlthzgnzBNbjInMfc6T4mUJuf&msToken=fixture_token-=&X-Bogus=1&X-Gnarly=MxYGKwI/poDT1H2rwhayDo0wVjUzPA0-pdECqt9ibPpAo0h9qGs0OtcUri0ADj4h8dTChDEF1wBJz7SES9GDIXnncmacNCnkeXvO6tzF6OIxrlfw-X/PZbS9ZRVSVW7vMzqEXbCrXC0Vz46zLLospS4hpC87s4cUVT/wNe6iU9WrpY8zkyZT5mYnrUnfdaOo5Io-vctj10bdZ9WWGmKf81xNHOJdYm4Evf9EDBXhfnIheFHPtRJAfWt7h8XKJvZApmARgRgsFQ--8eAHckpc0l/nJZvH/Dos3sqfF5gC95p2RkFAtnJkhDH63BFmKCsVLVk="], "current SDK exact wire reference vector 1");
        check([TKCurrentSignedQueryFixture(@"text=%C4%8Desk%C3%BD%20test",@"České tělo 😀",@"fixture-browser",@"",1777300000u,0u,4294967295u,3u,currentEntropy) isEqual:@"text=%C4%8Desk%C3%BD%20test&X-Dynosaur=MPcWb5TlPuhTs8xiuc/mFb9lxN-I2xE2CZeBSQrVSeOHGOwnp4KFr2C1Qo1toqgkX2wN/il3IGzgmGsJc/M0xxF44fhF7Iu0uIeb0ZAU9uWD9kk6tIwZbVvXS0zpS8Io3NfnUV/dv9bQvJZ4gQnGDMGjE9RiEJyUXg7RgNpnsD2bkBL9-t2x8AanOlgkai/s0MryEArAs6UTa2DhX0eprkcOAuPGL5iH6V0Rmm7wdLWrh3jjGM4hrhAv-Z8XGoPa7xnL0hLgeLHFmjskDNqYX4E61BX41xbGcJ1fS3OTXn6Kp6wYPHwqum2Kjzh6bN-jsydN6Us3xHf3WiBlpVNgB0mzyUm659CUpst5sdduz-9GZSXb8H5LLc4w8n-kAqzbYzT4oI==&msToken=&X-Bogus=1&X-Gnarly=MxYGKwI5ufX01H2rwhayDo0wVjUzP7RXpB2kqtsKSKhhA8muqYMVOFyXoHSAgi8LJyd/6hD21wBJuaAmSMbENFRZjHxwNCULSmxNlfe/V9ersAk31Pu75ranrUnfdaOo5Io-vctj10bdZ9WWGmKf81xNHOJdYm4Evf9EDBXhfnM1fbHPtRJdKXu8eleR6XA5rtWKrOka-lauZzgtVbL3VRNgMWYeXzx-zSSMzCVLL47ApLqTsSCms/5vh8XKJvZApmARgRgsFQ--8eAHckpc0l/nJZvH/DoL3sqfF50C95p2RRNDtnJkjAahLDFmKxVe2cw="], "current SDK exact wire reference vector 2");
        check([TKCurrentSignedQueryFixture(@"",@"",@"",@"",0u,4294967295u,0u,1u,currentEntropy) isEqual:@"&X-Dynosaur=MPcWbFllPuhTs8xiuc/mFb9lxN-I2xE2CZeBSQrVSeOHGOwnp4KFr2C1dTFdhWxkX2wN/it3IGzgmGsJc/M0xxF44fhFd0nQjbJjKuhlZmRhSFC9rwf2UEM9b-YkwVPg5XZv/kxEpJ6sr7UvzvyxSkfRKRUO15iPlwrYZl1NfSWg2TZkkts3R/WewJggVCtanblE5fVLjhjUdyazt72HNmHxKWN9pVXPDYLJkjHTMQiWIZu0uIeb0ZAU9uWD9kk6tIwZbVvXS0zpS8Io3NfnUV/dv9bQvJZ4gQnGDMGjE9RiEcXOvpkq0IAWdWChx0Inlc-/E0T3HEf3WiBlpVNgB0mzyUm659CUpst5sdduz-9GZSXb8H5LLc4w8n-kAqzbYzT4oI==&msToken=&X-Bogus=1&X-Gnarly=MxYGKwIKsgTE1H2rwhayDo0wVjUzPA7ep-EJw1XcbhsD603gG7mL2F3vTE7sDHNskByOhyp11wBJz7SES9GDIXnncmacNCmUVT/wNe6iU9WrpY8zkyZT5mYnrUnqm71gRZAhmciR1R0vbMYRPmXJOFaq/l9TYHY3vo9-dhXhfhCgk1HPtRkkeXvO6tzF6OIxrlfw-X/PZbS9ZRVSVW7vMzqEXbCrXC0Vz46zLLospS4hpC87s4aIS2v5h8XKJvZApmARgRgsFQ--8eAHckpc0l/nJZvH/Dos3sqfF5gC95p2RCrStnJkz294BKFmKPtaquG="], "current SDK exact wire reference vector 3");
        entropy96[0]++;entropy96[48]++;currentEntropy=[NSData dataWithBytes:entropy96 length:sizeof(entropy96)];
        check([TKCurrentSignedQueryFixture(@"aid=1988&itemId=123",@"",@"fixture-browser",@"",1700000000u,123456789u,987654321u,2u,currentEntropy) isEqual:@"aid=1988&itemId=123&X-Dynosaur=M/UCE/7y9x6YpDPrFatr9Ahy/RaDlcILJ/MHGStlVRor7DOIxpvXx1p94vBZrcx3YINenzRAXbvp/8zcTVId4bGPkpA45Yj8ouSnEqvAy9N/4hzZuxNuN85QeohTaeZxiLfhqzJ1FvDRcu8HB4VDXT0YUQ-Uxs8K7wHvPPNRSYiKb/iIs1CtkJ6l/RzxbRO519LL4-zipo4bwxX6Y8vM5ocEsbGt6hZYmezpFJtKPIb9LIreXCi1Ot3JQV3nZq1XVg48soPBDyPjSBUF5O3VIme0uZvt0uz30kIg9IfetZ/-b0bMb8ZLSNnA3VGTU0RmUJuNvQeWgMA2D9WBDJkYEQc9dSKqwUn3hZ-vyQ3ctGzH8L77n-SSlKhtv4LH/bNSiNKwVQHEG5Z1&msToken=&X-Bogus=1&X-Gnarly=MarMrwcWYTNxTqUxSzyoMGctdKpVYEzJMQd2w/yCk6YRo7akpDX5GbhYJGhd9l2YhjMDjephnJ1oDSwNePS9KJo1Mn33IYAWZ2Ca6Q2veFNv/DURmAzP4lkEKaSLKp0A3fcJhus3vYOtTB--jjICj78b5TIPvfk6dumoo08iT7tXHx-kAN2Xmp619rkGvtb8eleR6XA5rtWKrOka-lauZzgtVbL3VRNgMWYeXzx-zSSMzCVLL47ApLqTsSCmsFZPYU0veMqnh2jMoaV5PM4PD6LNiaRc0qDYW86AQrXjlFexM2W1ycrxd9I4smNbVV8KSD/="], "current SDK exact wire reference vector 4");
        check(!TKCurrentSignedQueryFixture(@"q=1",@"",@"UA",@"x&injected=1",0,0,0,1,currentEntropy), "session token cannot inject URL parameters");
        check(!TKCurrentSignedQueryFixture(@"q=1",@"",@"UA",@"",0,0,0,1,[NSData data]), "current signer requires full fresh entropy");
        NSString *browserQuery=TKCurrentBusinessQuery(@{@"browser_version":@"5.0 (Windows)",@"url":@"https://www.tiktok.com/",@"text":@"A&B=+%#"});
        check([browserQuery rangeOfString:@"browser_version=5.0%20(Windows)"].location!=NSNotFound && [browserQuery rangeOfString:@"url=https://www.tiktok.com/"].location!=NSNotFound, "browser punctuation preserved before signing");
        check([browserQuery rangeOfString:@"text=A%26B%3D%2B%25%23"].location!=NSNotFound, "comment punctuation remains within its parameter");
        NSString *wire=TKCurrentSignedQuery(browserQuery,@"",@"UA",@"");
        check([wire rangeOfString:@"&X-Bogus=1&X-Gnarly="].location!=NSNotFound && [wire rangeOfString:@"&X-Dynosaur="].location!=NSNotFound, "production signer emits the SDK parameter order");
        NSString *wireURL=[@"https://www.tiktok.com/api/commit/item/digg/?" stringByAppendingString:wire];
        check([[[NSURL URLWithString:wireURL] absoluteString] isEqual:wireURL], "Foundation preserves the exact signed wire URL");
        check(![wire isEqual:TKCurrentSignedQuery(browserQuery,@"",@"UA",@"")], "each request has fresh native signature entropy");
        fprintf(stdout,"Direct parser and library: %u checks, %u failures\n",checks,failures);
    }
    return failures ? 1 : 0;
}

#ifndef TK_TESTS_EMBEDDED
int main(int argc,char **argv) { return TKRunDirectParserTests(); }
#endif
