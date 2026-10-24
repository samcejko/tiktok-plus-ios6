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
static void TKGfield(NSMutableData *out,uint8_t key,id value)
{
    NSData *data=nil; uint8_t bytes[4];
    if([value isKindOfClass:[NSNumber class]]) {
        uint32_t n=[value unsignedIntValue]; NSUInteger size=n>0xffffff ? 4 : (n>0xffff ? 3 : (n>0xff ? 2 : 1));
        for(NSUInteger i=0;i<size;i++)bytes[i]=(uint8_t)(n>>(8*(size-i-1))); data=[NSData dataWithBytes:bytes length:size];
    } else data=[value dataUsingEncoding:NSUTF8StringEncoding];
    uint8_t header[]={key,(uint8_t)(data.length>>8),(uint8_t)data.length}; [out appendBytes:header length:3]; [out appendData:data];
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
NSString *TKGnarlySignatureFixture(NSString *query,NSString *body,NSString *userAgent,uint64_t ms,NSData *entropy,uint32_t total,uint32_t intercepted)
{
    if(entropy.length!=54 || query.length>65536 || body.length>16384 || userAgent.length>2048)return nil;
    const uint8_t *e=entropy.bytes;
    uint32_t field14=(65u<<16)|((uint32_t)e[48]<<8)|e[49];
    uint32_t field15=((uint32_t)e[50]<<24)|((uint32_t)e[51]<<16)|((uint32_t)e[52]<<8)|e[53];
    NSMutableDictionary *fields=[@{@1:@65,@2:@4,@3:TKGmd5(query),@4:TKGmd5(body),@5:TKGmd5(userAgent),@6:@((uint32_t)(ms/1000)),@7:@3181061566u,@8:@((uint32_t)(ms%0x80000000ULL)),@9:@"5.1.3-ZTCA",@10:@"1.0.0.368",@11:@1,@12:@(total),@13:@(intercepted),@14:@(field14),@15:@(field15)} mutableCopy];
    uint32_t checksum=0; for(id value in fields.allValues)if([value isKindOfClass:[NSNumber class]])checksum^=[value unsignedIntValue]; fields[@0]=@(checksum);
    uint8_t count=16; NSMutableData *cipher=[NSMutableData dataWithBytes:&count length:1];
    for(NSNumber *key in @[@1,@2,@6,@7,@8,@9,@10,@11,@4,@5,@3,@12,@13,@14,@15,@0])TKGfield(cipher,[key unsignedCharValue],fields[key]);
    return TKGseal(cipher,entropy);
}
NSString *TKGnarlySignature(NSString *query,NSString *body,NSString *userAgent)
{
    uint8_t entropy[54]; if(SecRandomCopyBytes(kSecRandomDefault,sizeof(entropy),entropy)!=errSecSuccess)return nil;
    static uint32_t requests=0; uint32_t counter; @synchronized([NSDate class]) { counter=++requests; }
    return TKGnarlySignatureFixture(query,body,userAgent,(uint64_t)([[NSDate date] timeIntervalSince1970]*1000),[NSData dataWithBytes:entropy length:sizeof(entropy)],counter,counter);
}

// 5.3.2 record layouts adapted from n1tr00's MIT-licensed implementation,
// preserved by lunar-me/tiktok-web-signature. Its full license is bundled too.
static NSData *TKGpack(uint32_t n)
{
    uint8_t b[4]={(uint8_t)(n>>24),(uint8_t)(n>>16),(uint8_t)(n>>8),(uint8_t)n};
    return n<0xfe01 ? [NSData dataWithBytes:b+2 length:2] : [NSData dataWithBytes:b length:4];
}
static uint32_t TKGprefix(NSString *s)
{
    NSData *d=[s dataUsingEncoding:NSUTF8StringEncoding]; const uint8_t *p=d.bytes; uint32_t n=0;
    for(NSUInteger i=0;i<MIN((NSUInteger)4,d.length);i++)n=(n<<8)|p[i]; return n;
}
static uint32_t TKGhash(NSString *s)
{
    NSData *d=[(s ?: @"") dataUsingEncoding:NSUTF8StringEncoding]; const uint8_t *p=d.bytes; uint32_t n=2166136260u;
    for(NSUInteger i=0;i<d.length;i++)n=((n^p[i])*16777619u)*33u; return n;
}
static NSData *TKGhashData(NSString *s)
{
    uint32_t n=TKGhash(s); uint8_t b[]={(uint8_t)(n>>24),(uint8_t)(n>>16),(uint8_t)(n>>8),(uint8_t)n}; return [NSData dataWithBytes:b length:4];
}
static NSData *TKGencodedField(id value,BOOL nonce)
{
    NSString *s=[value description]; NSUInteger length=s.length; NSMutableData *d=[NSMutableData dataWithLength:MAX(length,(NSUInteger)4)+2]; uint8_t *p=d.mutableBytes;
    for(NSUInteger i=0;i<length;i++) {
        uint32_t c=[s characterAtIndex:i],v;
        if(nonce) { v=((c^(102u+(uint32_t)i))+(i&0xaa))^0xa5; v=(v<<1)+((v<<1)>>8); p[i]=(uint8_t)v^0xbb; }
        else { v=((c^((103u+(uint32_t)i)&0xff))+((i&0xaa)+1))&0xff; v=(v<<2)|(v>>6); p[i]=(uint8_t)(((v&0xff)^0xbb)+1); }
    }
    for(NSUInteger i=length;i<4;i++)p[i]=(uint8_t)(0xdd+i);
    p[d.length-2]=(uint8_t)(length>>8); p[d.length-1]=(uint8_t)length; return d;
}
NSDictionary *TKModernWebSignaturesFixture(NSString *query,NSString *body,NSString *ua,uint32_t ts,uint32_t f8,NSData *entropy,uint32_t total,uint32_t intercepted)
{
    if(entropy.length!=96 || query.length>65536 || body.length>16384 || ua.length>2048)return nil;
    uint32_t canvas=2316120563u,half=(ts>>16)^(f8>>16)^(ts&0xffff)^(f8&0xffff),field14=(65u<<16)|half;
    uint32_t field15=((((canvas&0xffff)^(f8>>16))&0xffff)<<16)|((ts&0xffff)^(f8&0xffff));
    NSMutableDictionary *fields=[@{@1:@65,@2:@0,@3:TKGmd5(query),@4:TKGmd5(body),@5:TKGmd5(ua),@6:@(ts),@7:@(canvas),@8:@(f8),@9:@"5.3.2",@10:@"1.0.0.417",@11:@1,@12:@(total),@13:@(intercepted),@14:@(field14),@15:@(field15)} mutableCopy];
    uint32_t all=0,ints=0; for(NSNumber *key in fields.allKeys) { id v=fields[key]; if([v isKindOfClass:[NSNumber class]]) { all^=[v unsignedIntValue]; ints^=[v unsignedIntValue]; } else all^=TKGprefix(v); }
    fields[@16]=@(all); fields[@0]=@(ints^all);
    uint8_t order[17];for(unsigned i=0;i<17;i++)order[i]=(uint8_t)i;
    uint32_t shuffle=f8; for(unsigned i=16;i>0;i--) { shuffle=1664525u*shuffle+1013904223u; unsigned j=(unsigned)(((uint64_t)shuffle*(i+1))>>32); uint8_t x=order[i];order[i]=order[j];order[j]=x; }
    uint8_t count=17;NSMutableData *gnarly=[NSMutableData dataWithBytes:&count length:1];
    for(unsigned i=0;i<17;i++) {
        uint8_t key=order[i];id v=fields[@(key)];NSData *value=[v isKindOfClass:[NSNumber class]] ? TKGpack([v unsignedIntValue]) : [v dataUsingEncoding:NSUTF8StringEncoding];
        [gnarly appendBytes:&key length:1];[gnarly appendData:TKGpack((uint32_t)value.length)];[gnarly appendData:value];
    }
    const uint8_t fixed[]={94,222,223,224,0,1};NSData *fixedData=[NSData dataWithBytes:fixed length:6];
    NSMutableArray *values=[@[
        fixedData,fixedData,fixedData,TKGencodedField(@"0",NO),TKGencodedField(@(field14),NO),TKGencodedField(@(intercepted),NO),TKGencodedField(@65,NO),TKGencodedField(@(ts),NO),TKGencodedField(@"0",NO),TKGencodedField(@"0",NO),TKGencodedField(@"5.3.2",NO),TKGhashData(body),TKGencodedField(@(canvas),NO),TKGencodedField(@"0",NO),TKGhashData(query),TKGencodedField(@(total),NO),TKGhashData(ua),TKGencodedField(@"1.0.0.417",NO),TKGencodedField(@"1.0.0.2858",NO),TKGencodedField(@"0",NO),TKGencodedField(@(f8),NO),TKGencodedField(@"www.tiktok.com/",NO),TKGencodedField(@0,NO),TKGencodedField(@"0",NO),TKGhashData(@"")
    ] mutableCopy];
    uint32_t checksum=0;for(NSData *v in values)if(v.length>1)checksum^=((const uint8_t *)v.bytes)[1];values[0]=TKGencodedField(@(checksum),YES);
    NSMutableData *dynosaur=[NSMutableData data];for(unsigned i=0;i<values.count;i++) { uint8_t tag=0x20+i;NSData *value=values[i];[dynosaur appendBytes:&tag length:1];[dynosaur appendData:TKGpack((uint32_t)value.length)];[dynosaur appendData:value]; }
    return @{@"X-Gnarly":TKGseal(gnarly,[entropy subdataWithRange:NSMakeRange(0,48)]),@"X-Dynosaur":TKGseal(dynosaur,[entropy subdataWithRange:NSMakeRange(48,48)])};
}
NSDictionary *TKModernWebSignatures(NSString *query,NSString *body,NSString *ua)
{
    uint8_t entropy[96];if(SecRandomCopyBytes(kSecRandomDefault,sizeof(entropy),entropy)!=errSecSuccess)return nil;
    uint32_t entropySeed=entropy[0]*7;
    static uint32_t sessionValue;static dispatch_once_t once;dispatch_once(&once,^{uint64_t ms=(uint64_t)([[NSDate date] timeIntervalSince1970]*1000);sessionValue=(uint32_t)((ms*1000+entropySeed)%0x80000000ULL);});
    static uint32_t requests;uint32_t counter;@synchronized([NSDate class]){counter=++requests;}
    return TKModernWebSignaturesFixture(query,body,ua,(uint32_t)[[NSDate date] timeIntervalSince1970],sessionValue,[NSData dataWithBytes:entropy length:sizeof(entropy)],counter,counter);
}
