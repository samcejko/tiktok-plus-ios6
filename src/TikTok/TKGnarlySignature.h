#import <Foundation/Foundation.h>

// Native webmssdk 2.0.0.561 wire format. Return the exact query to transmit.
NSString *TKCurrentBusinessQuery(NSDictionary *parameters);
NSString *TKCurrentSignedQuery(NSString *query, NSString *body, NSString *userAgent, NSString *msToken);
NSString *TKCurrentSignedQueryFixture(NSString *query, NSString *body, NSString *userAgent, NSString *msToken, uint32_t timestamp, uint32_t nonce, uint32_t nonce2, uint32_t sequence, NSData *entropy96);
