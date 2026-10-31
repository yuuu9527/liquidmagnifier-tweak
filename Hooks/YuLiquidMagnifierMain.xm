#import <UIKit/UIKit.h>
#import "YuLiquidMagnifierConfig.h"
#import "YuLiquidMagnifierOverlayWindow.h"

// Darwin 通知名：供「快捷指令 → 通过 SSH 运行脚本」调用
//   notifyutil -p com.yu.liquidmagnifier.toggle   （显示/隐藏切换）
//   notifyutil -p com.yu.liquidmagnifier.show
//   notifyutil -p com.yu.liquidmagnifier.hide
static NSString *const YuLiquidMagnifierNotifyToggle = @"com.yu.liquidmagnifier.toggle";
static NSString *const YuLiquidMagnifierNotifyShow = @"com.yu.liquidmagnifier.show";
static NSString *const YuLiquidMagnifierNotifyHide = @"com.yu.liquidmagnifier.hide";

static BOOL YuLiquidMagnifierObserversInstalled = NO;

static void yu_liquidmagnifier_handleDarwinNotification(CFNotificationCenterRef center, void *observer,
                                                        CFStringRef name, const void *object,
                                                        CFDictionaryRef userInfo) {
    NSString *notificationName = (__bridge NSString *)name;
    dispatch_async(dispatch_get_main_queue(), ^{
        // 后台进程不响应，避免切回前台时出现残留镜片
        UIApplication *app = [UIApplication sharedApplication];
        if (!app || app.applicationState == UIApplicationStateBackground) return;

        YuLiquidMagnifierOverlayWindow *window =
            [YuLiquidMagnifierOverlayWindow yu_liquidmagnifier_ensureCreated];
        if (!window) return;

        if ([notificationName isEqualToString:YuLiquidMagnifierNotifyShow]) {
            [window yu_liquidmagnifier_setVisible:YES];
        } else if ([notificationName isEqualToString:YuLiquidMagnifierNotifyHide]) {
            [window yu_liquidmagnifier_setVisible:NO];
        } else {
            [YuLiquidMagnifierOverlayWindow yu_liquidmagnifier_toggleVisibility];
        }
    });
}

// 注入所有进程（悬浮放大镜需要在主屏和所有 App 内生效）。
// 镜片默认不显示，由「三指长按」或「快捷指令 / Darwin 通知」唤出。
static void yu_liquidmagnifier_installOverlay(void) {
    YuLiquidMagnifierConfig *config = [YuLiquidMagnifierConfig yu_liquidmagnifier_shared];
    if (![config yu_liquidmagnifier_isEnabled]) return;
    if (![UIApplication sharedApplication]) return;

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserverForName:UIApplicationDidFinishLaunchingNotification
                        object:nil queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
        [YuLiquidMagnifierOverlayWindow yu_liquidmagnifier_ensureCreated];
        [YuLiquidMagnifierOverlayWindow yu_liquidmagnifier_installTrigger];
    }];
    [center addObserverForName:UIApplicationDidBecomeActiveNotification
                        object:nil queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
        [YuLiquidMagnifierOverlayWindow yu_liquidmagnifier_installTrigger];
    }];
    [center addObserverForName:UIApplicationWillResignActiveNotification
                        object:nil queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
        [YuLiquidMagnifierOverlayWindow yu_liquidmagnifier_hideIfVisible];
    }];
    // 每个 App 的 key window 不同，换窗口后要重新挂手势
    [center addObserverForName:UIWindowDidBecomeKeyNotification
                        object:nil queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
        [YuLiquidMagnifierOverlayWindow yu_liquidmagnifier_installTrigger];
    }];

    if (!YuLiquidMagnifierObserversInstalled) {
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
    }

    // 注入较晚、通知已发过的兜底：直接准备窗口并挂手势
    dispatch_async(dispatch_get_main_queue(), ^{
        [YuLiquidMagnifierOverlayWindow yu_liquidmagnifier_ensureCreated];
        [YuLiquidMagnifierOverlayWindow yu_liquidmagnifier_installTrigger];
    });
}

%ctor {
    @autoreleasepool {
        // 配置快照只读加载，不写偏好文件
        [YuLiquidMagnifierConfig yu_liquidmagnifier_shared];
        yu_liquidmagnifier_installOverlay();
    }
}
