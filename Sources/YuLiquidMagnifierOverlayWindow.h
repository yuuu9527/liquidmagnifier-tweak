#pragma once

#import <UIKit/UIKit.h>
#import "YuLiquidMagnifierLensView.h"

// 悬浮在一切之上的透明窗口，只在镜片圆内接收触摸，其余触摸透传。
@interface YuLiquidMagnifierOverlayWindow : UIWindow

@property (nonatomic, strong, readonly) YuLiquidMagnifierLensView *lens;

+ (instancetype)yu_liquidmagnifier_ensureCreated;
+ (void)yu_liquidmagnifier_toggleVisibility;
+ (void)yu_liquidmagnifier_hideIfVisible;
- (void)yu_liquidmagnifier_setVisible:(BOOL)visible;

@end
