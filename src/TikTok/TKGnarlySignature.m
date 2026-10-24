// Native adaptation of SuperDuperNoob/tiktok-xgnarly-decoded (MIT, copyright 2026).
// See docs/licenses/tiktok-xgnarly-LICENSE.txt for the complete upstream notice.
#import "TKGnarlySignature.h"
#import <CommonCrypto/CommonDigest.h>
#import <Security/Security.h>
#include <string.h>

static uint32_t TKGrot(uint32_t x, unsigned n) { return (x<<n)|(x>>(32-n)); }
static void TKGquarter(uint32_t s[16],unsigned a,unsigned b,unsigned c,unsigned d)
{
    s[a]+=s[b]; s[d]=TKGrot(s[d]^s[a],16); s[c]+=s[d]; s[b]=TKGrot(s[b]^s[c],12);
    s[a]+=s[b]; s[d]=TKGrot(s[d]^s[a],8); s[c]+=s[d]; s[b]=TKGrot(s[b]^s[c],7);
}
static void TKGblock(uint32_t state[16],unsigned rounds,uint32_t output[16])
{
    memcpy(output,state,16*sizeof(uint32_t));
    for(unsigned r=0;r<rounds;) {
        TKGquarter(output,0,4,8,12); TKGquarter(output,1,5,9,13); TKGquarter(output,2,6,10,14); TKGquarter(output,3,7,11,15);
        if(++r>=rounds)break;
        TKGquarter(output,0,5,10,15); TKGquarter(output,1,6,11,12); TKGquarter(output,2,7,12,13); TKGquarter(output,3,4,13,14); r++;
    }
    for(unsigned i=0;i<16;i++)output[i]+=state[i];
}
static NSString *TKGmd5(NSString *s)
{
    NSData *d=[(s ?: @"") dataUsingEncoding:NSUTF8StringEncoding]; uint8_t hash[CC_MD5_DIGEST_LENGTH];
    CC_MD5(d.bytes,(CC_LONG)d.length,hash); NSMutableString *hex=[NSMutableString string];
    for(unsigned i=0;i<sizeof(hash);i++)[hex appendFormat:@"%02x",hash[i]]; return hex;
}
static NSString *TKGbase64(NSData *data)
{
    static const char alphabet[]="u09tbS3UvgDEe6r-ZVMXzLpsAohTn7mdINQlW412GqBjfYiyk8JORCF5/xKHwacP=";
    const uint8_t *p=data.bytes; NSMutableString *s=[NSMutableString string];
    for(NSUInteger i=0;i<data.length;i+=3) {
        NSUInteger left=data.length-i; uint32_t n=((uint32_t)p[i]<<16)|(left>1 ? ((uint32_t)p[i+1]<<8) : 0)|(left>2 ? p[i+2] : 0);
        [s appendFormat:@"%c%c%c%c",alphabet[(n>>18)&63],alphabet[(n>>12)&63],left>1 ? alphabet[(n>>6)&63] : '=',left>2 ? alphabet[n&63] : '='];
    } return s;
}
static NSString *TKGseal(NSMutableData *cipher,NSData *entropy)
{
    const uint8_t *e=entropy.bytes;
    uint32_t state[16]={1196819126u,600974999u,3863347763u,1451689750u}; unsigned nibbleSum=0;
    for(unsigned i=0;i<12;i++) { unsigned o=i*4; state[i+4]=(uint32_t)e[o]|((uint32_t)e[o+1]<<8)|((uint32_t)e[o+2]<<16)|((uint32_t)e[o+3]<<24); nibbleSum+=state[i+4]&15; }
    unsigned rounds=(nibbleSum&15)+5; uint8_t *bytes=cipher.mutableBytes;
    for(NSUInteger off=0;off<cipher.length;off+=64) {
        uint32_t stream[16]; TKGblock(state,rounds,stream); state[12]++;
        for(NSUInteger i=0;i<MIN((NSUInteger)64,cipher.length-off);i++)bytes[off+i]^=(uint8_t)(stream[i/4]>>(8*(i%4)));
    }
    NSUInteger sum=0,mod=cipher.length+1; for(unsigned i=0;i<48;i++)sum=(sum+e[i])%mod;
    for(NSUInteger i=0;i<cipher.length;i++)sum=(sum+bytes[i])%mod;
    uint8_t magic=75; NSMutableData *out=[NSMutableData dataWithBytes:&magic length:1];
    [out appendBytes:bytes length:sum]; [out appendBytes:e length:48]; [out appendBytes:bytes+sum length:cipher.length-sum];
    return TKGbase64(out);
}

// Record layout/query binding adapted from Evil0ctal/Douyin_TikTok_Download_API,
// Apache-2.0. See docs/licenses/tiktok-signature-Apache-2.0.txt and attribution.
static NSData *TKGbe(uint32_t n,NSUInteger size)
{
    uint8_t b[]={(uint8_t)(n>>24),(uint8_t)(n>>16),(uint8_t)(n>>8),(uint8_t)n};return [NSData dataWithBytes:b+4-size length:size];
}
static uint32_t TKGhash(NSString *s)
{
    NSData *d=[(s ?: @"") dataUsingEncoding:NSUTF8StringEncoding];const uint8_t *p=d.bytes;uint32_t n=2166136260u;
    for(NSUInteger i=0;i<d.length;i++)n=((n^p[i])*16777619u)*33u;return n;
}
static uint32_t TKGprefix(NSString *s)
{
    NSData *d=[s dataUsingEncoding:NSUTF8StringEncoding];const uint8_t *p=d.bytes;uint32_t n=0;
    for(NSUInteger i=0;i<MIN((NSUInteger)4,d.length);i++)n=(n<<8)|p[i];return n;
}
static NSData *TKGfield(id value,BOOL nonce)
{
    NSString *s=[value description];NSUInteger length=s.length;NSMutableData *d=[NSMutableData dataWithLength:MAX(length+2,(NSUInteger)6)];uint8_t *p=d.mutableBytes;
    for(NSUInteger i=0;i<length;i++) {
        uint32_t v=([s characterAtIndex:i]^((nonce?102u:103u)+(uint32_t)i));v=(v+(nonce?0:1)+(i&170))&255;
        if(nonce)v^=165;unsigned rotation=nonce?1:2;v=((v<<rotation)|(v>>(8-rotation)))&255;
        p[i]=(uint8_t)((v^187)+(nonce?0:1));
    }
    for(NSUInteger i=length;i<d.length-2;i++)p[i]=(uint8_t)(221+i);
    p[d.length-2]=0;p[d.length-1]=(uint8_t)length;return d;
}
static NSMutableData *TKGpack(NSDictionary *fields,BOOL count)
{
    NSMutableData *out=[NSMutableData data];if(count){uint8_t size=(uint8_t)fields.count;[out appendBytes:&size length:1];}
    for(NSNumber *key in [fields.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        NSData *value=fields[key];uint8_t h[]={[key unsignedCharValue],0,(uint8_t)value.length};[out appendBytes:h length:3];[out appendData:value];
    }return out;
}
static NSString *TKGescape(NSString *value)
{
    NSData *d=[value dataUsingEncoding:NSUTF8StringEncoding];const uint8_t *p=d.bytes;NSMutableString *s=[NSMutableString string];
    for(NSUInteger i=0;i<d.length;i++) {
        uint8_t c=p[i];
        // Preserve browser punctuation while keeping user text inside its own parameter.
        if(c>32 && c<=126 && !strchr("\"<>`#%&=+?\\",c))[s appendFormat:@"%c",c];
        else [s appendFormat:@"%%%02X",c];
    }return s;
}
NSString *TKCurrentBusinessQuery(NSDictionary *parameters)
{
    NSMutableArray *pairs=[NSMutableArray array];for(NSString *key in [parameters.allKeys sortedArrayUsingSelector:@selector(compare:)])
        [pairs addObject:[NSString stringWithFormat:@"%@=%@",TKGescape(key),TKGescape([parameters[key] description])]];
    return [pairs componentsJoinedByString:@"&"];
}
NSString *TKCurrentSignedQueryFixture(NSString *query,NSString *body,NSString *ua,NSString *msToken,uint32_t ts,uint32_t nonce,uint32_t nonce2,uint32_t sequence,NSData *entropy)
{
    NSString *token=msToken ?: @"";
    if(entropy.length!=96 || query.length>65536 || body.length>16384 || ua.length>2048 || token.length>4096 || [token rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-/+="] invertedSet]].location!=NSNotFound)return nil;
    uint32_t mixed=(((ts>>16)^(nonce>>16)^ts^nonce)&0xffff)|(65u<<16);
    NSMutableDictionary *dyn=[@{
        @0x20:TKGfield(@"0",NO),@0x21:TKGfield(@"1",YES),@0x22:TKGfield(@"1",YES),@0x23:TKGfield(@"0",NO),@0x24:TKGfield(@(mixed),NO),@0x25:TKGfield(@(sequence),NO),@0x26:TKGfield(@65,NO),@0x27:TKGfield(@(ts),NO),@0x28:TKGfield(@"0",NO),@0x29:TKGfield(@"0",NO),@0x2a:TKGfield(@"5.3.2",NO),@0x2b:TKGbe(TKGhash(@""),4),@0x2c:TKGfield(@"-1",NO),@0x2d:TKGfield(@"0",NO),@0x2e:TKGbe(TKGhash(query),4),@0x2f:TKGfield(@(sequence),NO),@0x30:TKGbe(TKGhash(ua),4),@0x31:TKGfield(@"2.0.0.561",NO),@0x32:TKGfield(@"0",NO),@0x33:TKGfield(@"0",NO),@0x34:TKGfield(@(nonce),NO),@0x35:TKGfield(@"www.tiktok.com/",NO),@0x36:TKGfield(@8,NO),@0x37:TKGfield(@"0",NO),@0x38:TKGbe(0xc46ce353u,4)
    } mutableCopy];
    uint32_t checksum=0;for(NSData *v in dyn.allValues)checksum^=((const uint8_t *)v.bytes)[1];dyn[@0x20]=TKGfield(@(checksum),YES);
    NSString *dynosaur=TKGseal(TKGpack(dyn,NO),[entropy subdataWithRange:NSMakeRange(0,48)]);
    // The request seal covers these two parameters, before the literal X-Bogus=1.
    NSString *covered=[NSString stringWithFormat:@"%@&X-Dynosaur=%@&msToken=%@",query,dynosaur,token];
    NSString *qm=TKGmd5(covered),*bm=TKGmd5(body),*um=TKGmd5(ua);
    NSArray *logical=@[@0,@65,@8,qm,bm,um,@(ts),@0,@(nonce),@"5.3.2",@"2.0.0.561",@1,@(sequence),@(sequence),@(mixed),@(nonce2)];
    uint32_t first=0xffffffffu,second=0xffffffffu;
    for(id v in logical)if([v isKindOfClass:[NSNumber class]]){first^=[v unsignedIntValue];second^=[v unsignedIntValue];}else first^=TKGprefix(v);
    second^=first;
    NSDictionary *gnarly=@{@0:TKGbe(second,4),@1:TKGbe(65,2),@2:TKGbe(8,2),@3:[qm dataUsingEncoding:NSUTF8StringEncoding],@4:[bm dataUsingEncoding:NSUTF8StringEncoding],@5:[um dataUsingEncoding:NSUTF8StringEncoding],@6:TKGbe(ts,4),@8:TKGbe(nonce,4),@9:[@"5.3.2" dataUsingEncoding:NSUTF8StringEncoding],@10:[@"2.0.0.561" dataUsingEncoding:NSUTF8StringEncoding],@11:TKGbe(1,2),@12:TKGbe(sequence,2),@13:TKGbe(sequence,2),@14:TKGbe(mixed,4),@15:TKGbe(nonce2,4),@16:TKGbe(first,4)};
    NSString *seal=TKGseal(TKGpack(gnarly,YES),[entropy subdataWithRange:NSMakeRange(48,48)]);
    return [covered stringByAppendingFormat:@"&X-Bogus=1&X-Gnarly=%@",seal];
}
NSString *TKCurrentSignedQuery(NSString *query,NSString *body,NSString *ua,NSString *msToken)
{
    uint8_t entropy[96];if(SecRandomCopyBytes(kSecRandomDefault,sizeof(entropy),entropy)!=errSecSuccess)return nil;
    NSTimeInterval now=[[NSDate date] timeIntervalSince1970];uint32_t nonce=(uint32_t)((uint64_t)(now*1000000)&0xffffffffULL);
    static uint32_t sequence;uint32_t call;@synchronized([NSDate class]){call=++sequence;}
    return TKCurrentSignedQueryFixture(query,body,ua,msToken,(uint32_t)now,nonce,~nonce,call,[NSData dataWithBytes:entropy length:sizeof(entropy)]);
}
