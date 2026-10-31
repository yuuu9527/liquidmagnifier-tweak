#import <UIKit/UIKit.h>
#import "YuLiquidMagnifierConfig.h"
#import "YuLiquidMagnifierOverlayWindow.h"

// 唯一入口：Darwin 通知（快捷指令「通过 SSH 运行脚本」调用）
//   notifyutil -p com.yu.liquidmagnifier.toggle   切换显示/隐藏
//   notifyutil -p com.yu.liquidmagnifier.show     显示
//   notifyutil -p com.yu.liquidmagnifier.hide     隐藏
static NSString *const YuLiquidMagnifierNotifyToggle = @"com.yu.liquidmagnifier.toggle";
static NSString *const YuLiquidMagnifierNotifyShow = @"com.yu.liquidmagnifier.show";
static NSString *const YuLiquidMagnifierNotifyHide = @"com.yu.liquidmagnifier.hide";

static BOOL YuLiquidMagnifierObserversInstalled = NO;

// 诊断用：每加载一个进程就往 /var/mobile/Library/Caches/com.yu.liquidmagnifier/loaded.log 记一行。
static NSString *yu_liquidmagnifier_cacheDir(void) {
    return @"/var/mobile/Library/Caches/com.yu.liquidmagnifier";
}

static void yu_liquidmagnifier_appendLog(NSString *fileName, NSString *line) {
    NSString *dir = yu_liquidmagnifier_cacheDir();
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
    NSString *file = [dir stringByAppendingPathComponent:fileName];
    NSString *existing = [NSString stringWithContentsOfFile:file
                                                   encoding:NSUTF8StringEncoding
                                                      error:NULL] ?: @"";
    [[existing stringByAppendingString:line] writeToFile:file
                                               atomically:YES
                                                 encoding:NSUTF8StringEncoding
                                                    error:NULL];
}

static void yu_liquidmagnifier_writeLoadMarker(void) {
    NSString *line = [NSString stringWithFormat:@"%@ pid=%d %@ %@\n",
                      [NSDate date], getpid(),
                      NSProcessInfo.processInfo.processName,
                      [NSBundle mainBundle].bundleIdentifier ?: @"-"];
    yu_liquidmagnifier_appendLog(@"loaded.log", line);
}

// 判断本进程是不是当前最前台的那个（避免 SpringBoard 与前台 App 同时出现两个镜片）
static BOOL yu_liquidmagnifier_isForemost(void) {
    UIApplication *app = [UIApplication sharedApplication];
    if (!app) return NO;
    if (app.applicationState == UIApplicationStateBackground) return NO;

    NSMutableArray<UIWindow *> *windows = [NSMutableArray array];
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in app.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            [windows addObjectsFromArray:((UIWindowScene *)scene).windows];
        }
    }
    if (windows.count == 0) [windows addObjectsFromArray:app.windows];

    for (UIWindow *window in windows) {
        if ([window isKindOfClass:[YuLiquidMagnifierOverlayWindow class]]) continue;
        if (window.hidden || window.alpha < 0.01) continue;
        if (window.isKeyWindow) return YES;
    }
    return NO;
}

static void yu_liquidmagnifier_handleDarwinNotification(CFNotificationCenterRef center, void *observer,
                                                        CFStringRef name, const void *object,
                                                        CFDictionaryRef userInfo) {
    NSString *notificationName = (__bridge NSString *)name;
    dispatch_async(dispatch_get_main_queue(), ^{
        // 只有前台进程响应
        if (!yu_liquidmagnifier_isForemost()) return;

        YuLiquidMagnifierOverlayWindow *window =
            [YuLiquidMagnifierOverlayWindow yu_liquidmagnifier_ensureCreated];

        if ([notificationName isEqualToString:YuLiquidMagnifierNotifyShow]) {
            [window yu_liquidmagnifier_setVisible:YES];
        } else if ([notificationName isEqualToString:YuLiquidMagnifierNotifyHide]) {
            [window yu_liquidmagnifier_setVisible:NO];
        } else {
            [YuLiquidMagnifierOverlayWindow yu_liquidmagnifier_toggleVisibility];
        }
        yu_liquidmagnifier_appendLog(@"trigger.log",
            [NSString stringWithFormat:@"%@ %@ %@\n", [NSDate date],
                                       NSProcessInfo.processInfo.processName, notificationName]);
    });
}

static void yu_liquidmagnifier_installOverlay(void) {
    yu_liquidmagnifier_writeLoadMarker();

    // 注意：%ctor 执行时 UIApplication 往往还不存在，这里绝对不能用它做门槛，
    // 否则后面所有通知监听都不会注册（曾因此完全无响应）。
    if (![[YuLiquidMagnifierConfig yu_liquidmagnifier_shared] yu_liquidmagnifier_isEnabled]) return;

    if (YuLiquidMagnifierObserversInstalled) return;
    YuLiquidMagnifierObserversInstalled = YES;

    CFNotificationCenterRef darwin = CFNotificationCenterGetDarwinNotifyCenter();
    for (NSString *name in @[ YuLiquidMagnifierNotifyToggle,
                              YuLiquidMagnifierNotifyShow,
                              YuLiquidMagnifierNotifyHide ]) {
        CFNotificationCenterAddObserver(darwin, NULL,
            yu_liquidmagnifier_handleDarwinNotification,
            (__bridge CFStringRef)name, NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
    }

    // 前台激活时准备好悬浮层，让小圆点出现
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) {
        [YuLiquidMagnifierOverlayWindow yu_liquidmagnifier_ensureCreated];
    }];

    // 切后台时收起镜片，避免镜片残留到下一次前台
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillResignActiveNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) {
        [YuLiquidMagnifierOverlayWindow yu_liquidmagnifier_hideIfVisible];
    }];
}

%ctor {
    @autoreleasepool {
        [YuLiquidMagnifierConfig yu_liquidmagnifier_shared];
        yu_liquidmagnifier_installOverlay();
    }
}
