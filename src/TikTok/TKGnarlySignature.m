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
NSString *TKGnarlySignature(NSString *query,NSString *body,NSString *userAgent)
{
    uint8_t entropy[54]; if(SecRandomCopyBytes(kSecRandomDefault,sizeof(entropy),entropy)!=errSecSuccess)return nil;
    static uint32_t requests=0; uint32_t counter; @synchronized([NSDate class]) { counter=++requests; }
    return TKGnarlySignatureFixture(query,body,userAgent,(uint64_t)([[NSDate date] timeIntervalSince1970]*1000),[NSData dataWithBytes:entropy length:sizeof(entropy)],counter,counter);
}
