// The public installer can write a password or check its presence. Only a signed
// Godot parent can receive a password, through its already-open anonymous pipe.
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <sys/stat.h>
#import <pwd.h>
#import <readpassphrase.h>
#import <unistd.h>
#import <sys/resource.h>

static NSString * const service = @"com.zhijian.paper-castle.model-connection.v1";

static BOOL hexField(NSString *s, NSUInteger length) {
    return s.length == length && [s rangeOfCharacterFromSet:
        [[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"] invertedSet]].location == NSNotFound;
}

static BOOL gamePipe(void) {
    struct stat input, output;
    if (fstat(0, &input) || fstat(1, &output) ||
        !S_ISFIFO(input.st_mode) || !S_ISFIFO(output.st_mode)) return NO;
    NSDictionary *attributes = @{(__bridge NSString *)kSecGuestAttributePid: @(getppid())};
    SecCodeRef parent = NULL;
    SecRequirementRef required = NULL;
    OSStatus status = SecCodeCopyGuestWithAttributes(NULL, (__bridge CFDictionaryRef)attributes,
                                                    kSecCSDefaultFlags, &parent);
    if (!status) status = SecRequirementCreateWithString(
        CFSTR("anchor apple generic and identifier \"org.godotengine.godot\" and certificate leaf[subject.OU] = \"6K46PWY5DM\""),
        kSecCSDefaultFlags, &required);
    if (!status) status = SecCodeCheckValidity(parent, kSecCSDefaultFlags, required);
    if (parent) CFRelease(parent);
    if (required) CFRelease(required);
    return status == errSecSuccess;
}

static BOOL readKey(char *buf, size_t size) {
    if (isatty(STDIN_FILENO)) {
        if (!readpassphrase("API Key: ", buf, size, RPP_REQUIRE_TTY)) return NO;
    } else {
        if (!fgets(buf, (int)size, stdin)) return NO;
        buf[strcspn(buf, "\r\n")] = 0;
    }
    size_t len = strlen(buf);
    return len >= 8 && len <= 2048 &&
        strspn(buf, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._~+/=-") == len;
}

static int report(OSStatus status) {
    if (status == errSecSuccess) { puts("ok"); return 0; }
    if (status == errSecItemNotFound) { puts("missing"); return 3; }
    if (status == errSecInteractionNotAllowed || status == errSecAuthFailed ||
        status == errSecUserCanceled) { puts("locked"); return 4; }
    printf("unavailable %d\n", (int)status);
    return 5;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        struct rlimit core = {0, 0};
        setrlimit(RLIMIT_CORE, &core);
        if (argc != 6 || getuid() != geteuid()) return report(errSecParam);
        NSString *op = @(argv[1]), *profile = @(argv[2]), *cid = @(argv[3]);
        NSString *provider = @(argv[4]), *urlHash = @(argv[5]);
        if (!hexField(profile,64) || !hexField(cid,24) || !hexField(urlHash,64) ||
            !([provider isEqual:@"deepseek-official"] || [provider isEqual:@"compatible"]) ||
            !([@[@"store",@"restore",@"remove",@"status"] containsObject:op])) return report(errSecParam);
        BOOL restore = [op isEqual:@"restore"];
        if (restore && !gamePipe()) return report(errSecAuthFailed);
        NSString *account = [@[profile,cid,provider,urlHash] componentsJoinedByString:@"/"];
        struct passwd *user = getpwuid(getuid());
        if (!user) return report(errSecNoSuchKeychain);
        NSString *path = [@(user->pw_dir) stringByAppendingPathComponent:@"Library/Keychains/login.keychain-db"];
        SecKeychainSetUserInteractionAllowed(false);
        SecKeychainRef chain = NULL;
        OSStatus result = SecKeychainOpen(path.fileSystemRepresentation, &chain);
        if (result) return report(result);
        SecKeychainItemRef item = NULL;
        UInt32 count = 0;
        void *data = NULL;
        result = SecKeychainFindGenericPassword(chain, (UInt32)service.length, service.UTF8String,
            (UInt32)account.length, account.UTF8String, restore ? &count : NULL, restore ? &data : NULL, &item);
        if ([op isEqual:@"store"] && (result == errSecSuccess || result == errSecItemNotFound)) {
            char key[2052] = {0};
            if (!readKey(key,sizeof(key))) result = errSecParam;
            else if (item) result = SecKeychainItemModifyAttributesAndData(item, NULL, (UInt32)strlen(key), key);
            else {
                // Security.framework creates the default private ACL trusting the creator.
                result = SecKeychainAddGenericPassword(chain, (UInt32)service.length, service.UTF8String,
                    (UInt32)account.length, account.UTF8String, (UInt32)strlen(key), key, NULL);
            }
            memset_s(key,sizeof(key),0,sizeof(key));
        } else if ([op isEqual:@"remove"]) {
            if (result == errSecSuccess) result = SecKeychainItemDelete(item);
            else if (result == errSecItemNotFound) result = errSecSuccess;
        }
        if (restore && result == errSecSuccess) {
            if (count < 8 || count > 2048 || !data) result = errSecDecode;
            else { fputs("value ",stdout); fwrite(data,1,count,stdout); putchar('\n'); }
        }
        if (data) SecKeychainItemFreeContent(NULL,data);
        if (item) CFRelease(item);
        CFRelease(chain);
        if (restore && result == errSecSuccess) return 0;
        return report(result);
    }
}
