#import <Foundation/Foundation.h>

typedef void (^TKHTTPCompletion)(NSInteger status, NSData *body, NSDictionary *headers, NSError *error);
typedef void (^TKJSONCompletion)(id json, NSInteger status, NSError *error);

// A running request of TKHTTP. After -cancel the completion block is never called.
@interface TKHTTPTask : NSObject
@property (atomic, readonly) BOOL isCancelled;
@property (atomic, copy) dispatch_block_t cancelBlock;   // for chained requests: called by -cancel (once)
- (void)cancel;
@end

// Convenience layer over TKHTTPRequest for API calls: redirects are followed, GET requests are tried a second
// time after a network error, completion blocks run on the main thread.
@interface TKHTTP : NSObject

+ (TKHTTPTask *)request:(NSString *)method url:(NSString *)url headers:(NSDictionary *)headers body:(NSData *)body
                retries:(NSInteger)retries completion:(TKHTTPCompletion)completion;

+ (TKHTTPTask *)get:(NSString *)url headers:(NSDictionary *)headers completion:(TKHTTPCompletion)completion;

// JSON answers. `error` is set for network errors, for statuses >= 400 (code = the status, message from the body
// when it has one) and for bodies that are not JSON; `json` is passed even with an error when the body parsed.
+ (TKHTTPTask *)getJSON:(NSString *)url headers:(NSDictionary *)headers completion:(TKJSONCompletion)completion;
+ (TKHTTPTask *)postJSON:(NSString *)url headers:(NSDictionary *)headers object:(id)object retries:(NSInteger)retries
              completion:(TKJSONCompletion)completion;
+ (TKHTTPTask *)postForm:(NSString *)url fields:(NSDictionary *)fields completion:(TKJSONCompletion)completion;
+ (TKHTTPTask *)postForm:(NSString *)url headers:(NSDictionary *)headers fields:(NSDictionary *)fields completion:(TKJSONCompletion)completion;

@end
