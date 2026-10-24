#import "TKWebSignature.h"
#include <CommonCrypto/CommonDigest.h>
#include <string.h>

// Port of the checksum already used by pi/tikie_server.py; algorithm from f2
// (Apache-2.0, https://github.com/Johnserf-Seed/f2). See docs/third-party.md.
static NSData *TKRC4(NSData *input, const unsigned char *key, size_t keyLength)
{
    unsigned char s[256]; for (unsigned i=0;i<256;i++)s[i]=(unsigned char)i;
    unsigned j=0;for(unsigned i=0;i<256;i++){j=(j+s[i]+key[i%keyLength])&255;unsigned char x=s[i];s[i]=s[j];s[j]=x;}
    NSMutableData *out=[NSMutableData dataWithLength:input.length];const unsigned char *in=input.bytes;unsigned char *p=out.mutableBytes;
    unsigned i=0;j=0;for(NSUInteger k=0;k<input.length;k++){i=(i+1)&255;j=(j+s[i])&255;unsigned char x=s[i];s[i]=s[j];s[j]=x;p[k]=in[k]^s[(s[i]+s[j])&255];}return out;
}
static void TKMD5(NSData *data, unsigned char *out) { CC_MD5(data.bytes,(CC_LONG)data.length,out); }
static NSString *TKBase64(NSData *data)
{
    static const char *abc="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    const unsigned char *p=data.bytes;NSMutableString *s=[NSMutableString string];
    for(NSUInteger i=0;i<data.length;i+=3){uint32_t n=(uint32_t)p[i]<<16;if(i+1<data.length)n|=(uint32_t)p[i+1]<<8;if(i+2<data.length)n|=p[i+2];
        [s appendFormat:@"%c%c%c%c",abc[(n>>18)&63],abc[(n>>12)&63],i+1<data.length?abc[(n>>6)&63]:'=',i+2<data.length?abc[n&63]:'='];}return s;
}
NSString *TKWebSignature(NSString *query, NSString *ua, uint32_t t)
{
    unsigned char q[16],empty[16],u[16],first[16];
    TKMD5([query dataUsingEncoding:NSUTF8StringEncoding],first);TKMD5([NSData dataWithBytes:first length:16],q);
    TKMD5([NSData data],first);TKMD5([NSData dataWithBytes:first length:16],empty);
    const unsigned char key[]={0,1,12};NSString *b64=TKBase64(TKRC4([ua dataUsingEncoding:NSISOLatin1StringEncoding],key,3));
    TKMD5([b64 dataUsingEncoding:NSASCIIStringEncoding],u);
    uint32_t ct=536919696;unsigned char a[]={64,0,1,12,q[14],q[15],empty[14],empty[15],u[14],u[15],t>>24,t>>16,t>>8,t,ct>>24,ct>>16,ct>>8,ct,0};
    for(unsigned i=0;i<18;i++)a[18]^=a[i];const unsigned char ff=255;
    NSMutableData *garbled=[NSMutableData dataWithBytes:(unsigned char[]){2,255} length:2];[garbled appendData:TKRC4([NSData dataWithBytes:a length:19],&ff,1)];
    static const char *alphabet="Dkdpgh4ZKsQB80/Mfvw36XI1R25-WUAlEi7NLboqYTOPuzmFjJnryx9HVGcaStCe=";
    const unsigned char *p=garbled.bytes;NSMutableString *out=[NSMutableString string];
    for(unsigned i=0;i<21;i+=3){uint32_t n=((uint32_t)p[i]<<16)|((uint32_t)p[i+1]<<8)|p[i+2];[out appendFormat:@"%c%c%c%c",alphabet[(n>>18)&63],alphabet[(n>>12)&63],alphabet[(n>>6)&63],alphabet[n&63]];}return out;
}
