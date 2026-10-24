#import <Foundation/Foundation.h>

// Native interoperability implementation; no browser runtime or signing server.
NSString *TKGnarlySignature(NSString *query, NSString *body, NSString *userAgent);
// Pinned clock/entropy for offline reference vectors (48 key bytes + 6 field bytes).
NSString *TKGnarlySignatureFixture(NSString *query, NSString *body, NSString *userAgent, uint64_t milliseconds, NSData *entropy, uint32_t totalRequests, uint32_t interceptedRequests);
