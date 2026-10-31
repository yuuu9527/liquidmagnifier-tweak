#pragma once

#import <UIKit/UIKit.h>
#import "YuLiquidMagnifierLensView.h"

// 悬浮在一切之上的透明窗口，只在镜片圆内接收触摸，其余触摸透传。
@interface YuLiquidMagnifierOverlayWindow : UIWindow

@property (nonatomic, strong, readonly) YuLiquidMagnifierLensView *lens;

+ (instancetype)yu_liquidmagnifier_ensureCreated;
+ (void)yu_liquidmagnifier_toggleVisibility;
+ (void)yu_liquidmagnifier_hideIfVisible;
// 设置面板改动后重新应用（白名单 / 圆点开关 / 总开关）
+ (void)yu_liquidmagnifier_refreshForPreferences;
- (void)yu_liquidmagnifier_setVisible:(BOOL)visible;
- (void)yu_liquidmagnifier_applyHandleVisibility;

@end
