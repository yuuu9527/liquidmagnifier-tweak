#import <UIKit/UIKit.h>
#import "YuLiquidMagnifierConfig.h"
#import "YuLiquidMagnifierOverlayWindow.h"

// 注入所有进程（悬浮放大镜需要在主屏和所有 App 内生效）。
// 只在前台活跃的进程里显示镜片，避免主屏与前台 App 同时出现两个镜片。
static void yu_liquidmagnifier_installOverlay(void) {
    YuLiquidMagnifierConfig *config = [YuLiquidMagnifierConfig yu_liquidmagnifier_shared];
    if (![config yu_liquidmagnifier_isEnabled]) return;
    if (![UIApplication sharedApplication]) return;

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserverForName:UIApplicationDidFinishLaunchingNotification
                        object:nil queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
        [YuLiquidMagnifierOverlayWindow yu_liquidmagnifier_ensureVisible];
    }];
    [center addObserverForName:UIApplicationDidBecomeActiveNotification
                        object:nil queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
        [YuLiquidMagnifierOverlayWindow yu_liquidmagnifier_ensureVisible];
    }];
    [center addObserverForName:UIApplicationWillResignActiveNotification
                        object:nil queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
        [YuLiquidMagnifierOverlayWindow yu_liquidmagnifier_setVisible:NO];
    }];

    // 注入较晚、通知已发过的兜底：直接创建
    if (UIApplication.sharedApplication.windows.count > 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [YuLiquidMagnifierOverlayWindow yu_liquidmagnifier_ensureVisible];
        });
    }
}

%ctor {
    @autoreleasepool {
        // 配置快照只读加载，不写偏好文件
        [YuLiquidMagnifierConfig yu_liquidmagnifier_shared];
        yu_liquidmagnifier_installOverlay();
    }
}
