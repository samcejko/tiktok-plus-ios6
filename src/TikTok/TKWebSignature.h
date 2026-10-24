#import <Foundation/Foundation.h>
// Web request checksum. Timestamp is explicit so fixture tests are deterministic.
NSString *TKWebSignature(NSString *query, NSString *userAgent, uint32_t timestamp);
