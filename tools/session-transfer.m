// Explicit developer-side session migration between the owner's devices.
// Standalone artifact only: never bundled in the application or packages.
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

int main(int argc,char **argv)
{
    @autoreleasepool {
        if(argc!=2 || strcmp(argv[1],"--owner-authorized-pipe") || isatty(STDOUT_FILENO)) {
            fprintf(stderr,"Use only an owner-authorized encrypted transfer pipe.\n");return 2;
        }
        // Access exactly one item in TikTak+'s own group, never enumerate Keychain.
        NSDictionary *query=@{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
            (__bridge id)kSecAttrService:@"com.samcejko.tikieplus",
            (__bridge id)kSecAttrAccount:@"direct.session.v1",
            (__bridge id)kSecAttrAccessGroup:@"com.samcejko.tikieplus",
            (__bridge id)kSecReturnData:@YES,(__bridge id)kSecMatchLimit:(__bridge id)kSecMatchLimitOne};
        CFTypeRef result=NULL;OSStatus status=SecItemCopyMatching((__bridge CFDictionaryRef)query,&result);
        if(status!=errSecSuccess || !result) { fprintf(stderr,"Session unavailable (%ld).\n",(long)status);return 3; }
        NSData *data=(__bridge_transfer NSData *)result;
        if(data.length>1024*1024)return 4;
        id session=[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
        if(![session isKindOfClass:[NSDictionary class]] || ![session[@"cookies"] isKindOfClass:[NSString class]] || ![session[@"user"] isKindOfClass:[NSDictionary class]])return 4;
        return fwrite(data.bytes,1,data.length,stdout)==data.length ? 0 : 5;
    }
}
