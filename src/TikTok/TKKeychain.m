#import "TKKeychain.h"
#import "TKCommon.h"
#import <Security/Security.h>

static NSString * const TKKeychainService = @"com.samcejko.tikieplus";

@implementation TKKeychain

+ (NSMutableDictionary *)queryForKey:(NSString *)key
{
    return [@{ (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
               (__bridge id)kSecAttrService: TKKeychainService,
               (__bridge id)kSecAttrAccount: key ?: @"" } mutableCopy];
}

+ (NSString *)stringForKey:(NSString *)key
{
    NSMutableDictionary *q = [self queryForKey:key];
    q[(__bridge id)kSecReturnData] = (__bridge id)kCFBooleanTrue;
    q[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    CFTypeRef result = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)q, &result) == errSecSuccess && result) {
        NSData *data = (__bridge_transfer NSData *)result;
        return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    }
    NSString *fallback = [[NSUserDefaults standardUserDefaults] stringForKey:[@"kc." stringByAppendingString:key]];
    return fallback;
}

 + (NSString *)secureStringForKey:(NSString *)key
{
    NSMutableDictionary *q = [self queryForKey:key];
    q[(__bridge id)kSecReturnData] = (__bridge id)kCFBooleanTrue;
    q[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    CFTypeRef result = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)q, &result) != errSecSuccess || !result) return nil;
    return [[NSString alloc] initWithData:(__bridge_transfer NSData *)result encoding:NSUTF8StringEncoding];
}
+ (BOOL)setSecureString:(NSString *)value forKey:(NSString *)key
{
    NSMutableDictionary *q = [self queryForKey:key];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:[@"kc." stringByAppendingString:key]];
    if (!value.length) { OSStatus s = SecItemDelete((__bridge CFDictionaryRef)q); return s == errSecSuccess || s == errSecItemNotFound; }
    NSDictionary *attrs = @{(__bridge id)kSecValueData:[value dataUsingEncoding:NSUTF8StringEncoding],
        (__bridge id)kSecAttrAccessible:(__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly};
    OSStatus s = SecItemUpdate((__bridge CFDictionaryRef)q, (__bridge CFDictionaryRef)attrs);
    if (s == errSecItemNotFound) { [q addEntriesFromDictionary:attrs]; s = SecItemAdd((__bridge CFDictionaryRef)q, NULL); }
    return s == errSecSuccess;
}

+ (void)setString:(NSString *)value forKey:(NSString *)key
{
    NSMutableDictionary *q = [self queryForKey:key];
    SecItemDelete((__bridge CFDictionaryRef)q);
    if (!value.length) {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:[@"kc." stringByAppendingString:key]];
        return;
    }
    q[(__bridge id)kSecValueData] = [value dataUsingEncoding:NSUTF8StringEncoding];
    q[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlock;
    OSStatus status = SecItemAdd((__bridge CFDictionaryRef)q, NULL);
    if (status != errSecSuccess) {
        [[NSUserDefaults standardUserDefaults] setObject:value forKey:[@"kc." stringByAppendingString:key]];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}

@end
