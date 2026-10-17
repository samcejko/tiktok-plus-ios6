#import "TKHTTP.h"
#import "TKHTTPRequest.h"
#import "TKSettings.h"
#import "TKUtils.h"
#import "TKCommon.h"

static const NSInteger TKMaxRedirects = 5;

@interface TKHTTPTask ()
@property (atomic, strong) TKHTTPRequest *request;
@property (atomic) BOOL isCancelled;
@end

@implementation TKHTTPTask

- (void)cancel
{
    if (self.isCancelled) return;
    self.isCancelled = YES;
    [self.request cancel];
    dispatch_block_t block = self.cancelBlock;
    self.cancelBlock = nil;
    if (block) block();
}

@end

@implementation TKHTTP

+ (void)run:(TKHTTPTask *)task method:(NSString *)method url:(NSURL *)url headers:(NSDictionary *)headers body:(NSData *)body
       hops:(NSInteger)hops retries:(NSInteger)retries completion:(TKHTTPCompletion)completion
{
    TKHTTPRequest *r = [[TKHTTPRequest alloc] initWithMethod:method URL:url];
    r.headers = headers;
    r.body = body;
    r.connectTimeout = 15;
    r.readTimeout = 30;
    r.verifyTLS = [TKSettings verifyTLS];
    __weak TKHTTPRequest *weakRequest = r;
    r.onComplete = ^(NSError *error) {
        TKHTTPRequest *request = weakRequest;
        if (task.isCancelled) return;
        NSInteger status = request.statusCode;
        NSDictionary *responseHeaders = request.responseHeaders;
        if (!error && status >= 300 && status < 400 && status != 304 && hops < TKMaxRedirects) {
            NSString *location = responseHeaders[@"location"];
            NSURL *next = location.length ? [[NSURL URLWithString:location relativeToURL:url] absoluteURL] : nil;
            if (next.host.length) {
                BOOL safe = [method isEqualToString:@"GET"] || [method isEqualToString:@"HEAD"];
                BOOL toGet = status == 303 || ((status == 301 || status == 302) && !safe);
                NSDictionary *nextHeaders = headers;
                if (![[next.host lowercaseString] isEqualToString:[url.host lowercaseString]]) {
                    // credentials stay with the host they were meant for
                    NSMutableDictionary *trimmed = [NSMutableDictionary dictionary];
                    for (NSString *key in headers) {
                        NSString *lower = [key lowercaseString];
                        if ([lower isEqualToString:@"authorization"] || [lower isEqualToString:@"client-id"]) continue;
                        trimmed[key] = headers[key];
                    }
                    nextHeaders = trimmed;
                }
                [self run:task method:toGet ? @"GET" : method url:next headers:nextHeaders body:toGet ? nil : body
                     hops:hops + 1 retries:retries completion:completion];
                return;
            }
        }
        if (error && retries > 0 && error.code != TKErrorCancelled && error.code != TKErrorCertificate) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.7 * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                if (task.isCancelled) return;
                [self run:task method:method url:url headers:headers body:body hops:hops retries:retries - 1 completion:completion];
            });
            return;
        }
        NSData *responseBody = request.responseBody;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (task.isCancelled) return;
            if (completion) completion(error ? 0 : status, responseBody, responseHeaders, error);
        });
    };
    task.request = r;
    if (task.isCancelled) return;
    [r start];
}

+ (TKHTTPTask *)request:(NSString *)method url:(NSString *)url headers:(NSDictionary *)headers body:(NSData *)body
                retries:(NSInteger)retries completion:(TKHTTPCompletion)completion
{
    TKHTTPTask *task = [[TKHTTPTask alloc] init];
    NSURL *u = url.length ? [NSURL URLWithString:url] : nil;
    if (!u.host.length) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (task.isCancelled) return;
            if (completion) completion(0, nil, nil, TKMakeError(TKErrorNetwork, [NSString stringWithFormat:@"Bad address: %@", url ?: @""]));
        });
        return task;
    }
    [self run:task method:method.length ? [method uppercaseString] : @"GET" url:u headers:headers body:body hops:0 retries:retries completion:completion];
    return task;
}

+ (TKHTTPTask *)get:(NSString *)url headers:(NSDictionary *)headers completion:(TKHTTPCompletion)completion
{
    return [self request:@"GET" url:url headers:headers body:nil retries:1 completion:completion];
}

// What an error body says: {"message": ...}, {"error": ..., "message": ...}, {"error_description": ...}, {"errors": [{"message": ...}]}
+ (NSString *)messageFromErrorJSON:(id)json
{
    NSDictionary *d = TKDict(json);
    if (!d) {
        NSDictionary *first = TKDict([TKArr(json) firstObject]);
        return TKStr(first[@"error"]) ?: TKStr(first[@"message"]);
    }
    NSString *message = TKStr(d[@"message"]);
    if (!message.length) message = TKStr(d[@"error_description"]);
    if (!message.length) message = TKStr(TKDict([TKArr(d[@"errors"]) firstObject])[@"message"]);
    if (!message.length && [d[@"error"] isKindOfClass:[NSString class]]) message = d[@"error"];
    return message.length ? message : nil;
}

+ (TKHTTPCompletion)jsonHandler:(TKJSONCompletion)completion
{
    return ^(NSInteger status, NSData *body, NSDictionary *headers, NSError *error) {
        if (!completion) return;
        if (error) { completion(nil, 0, error); return; }
        id json = [TKUtils JSONObjectFromData:body];
        if (status >= 400) {
            NSString *message = [self messageFromErrorJSON:json] ?: [NSString stringWithFormat:L(@"Request failed (HTTP %ld)."), (long)status];
            completion(json, status, TKMakeError(status, message));
            return;
        }
        if (!json && body.length) {
            completion(nil, status, TKMakeError(TKErrorBadResponse, L(@"Unexpected response format.")));
            return;
        }
        completion(json, status, nil);
    };
}

+ (TKHTTPTask *)getJSON:(NSString *)url headers:(NSDictionary *)headers completion:(TKJSONCompletion)completion
{
    NSMutableDictionary *h = [NSMutableDictionary dictionaryWithDictionary:headers ?: @{}];
    if (!h[@"Accept"]) h[@"Accept"] = @"application/json";
    return [self request:@"GET" url:url headers:h body:nil retries:1 completion:[self jsonHandler:completion]];
}

+ (TKHTTPTask *)postJSON:(NSString *)url headers:(NSDictionary *)headers object:(id)object retries:(NSInteger)retries
              completion:(TKJSONCompletion)completion
{
    NSMutableDictionary *h = [NSMutableDictionary dictionaryWithDictionary:headers ?: @{}];
    if (!h[@"Accept"]) h[@"Accept"] = @"application/json";
    if (!h[@"Content-Type"]) h[@"Content-Type"] = @"application/json";
    NSData *body = [TKUtils JSONDataFromObject:object] ?: [NSData data];
    return [self request:@"POST" url:url headers:h body:body retries:retries completion:[self jsonHandler:completion]];
}

+ (TKHTTPTask *)postForm:(NSString *)url headers:(NSDictionary *)headers fields:(NSDictionary *)fields completion:(TKJSONCompletion)completion
{
    NSMutableArray *pairs = [NSMutableArray array];
    for (NSString *key in fields) {
        [pairs addObject:[NSString stringWithFormat:@"%@=%@", [TKUtils urlEncode:key], [TKUtils urlEncode:[fields[key] description]]]];
    }
    NSData *body = [[pairs componentsJoinedByString:@"&"] dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableDictionary *h = [NSMutableDictionary dictionaryWithDictionary:headers ?: @{}];
    if (!h[@"Content-Type"]) h[@"Content-Type"] = @"application/x-www-form-urlencoded";
    if (!h[@"Accept"]) h[@"Accept"] = @"application/json";
    return [self request:@"POST" url:url headers:h body:body retries:0 completion:[self jsonHandler:completion]];
}

+ (TKHTTPTask *)postForm:(NSString *)url fields:(NSDictionary *)fields completion:(TKJSONCompletion)completion
{
    return [self postForm:url headers:nil fields:fields completion:completion];
}

@end
