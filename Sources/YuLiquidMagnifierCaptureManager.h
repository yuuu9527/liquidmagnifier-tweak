#pragma once

#import <UIKit/UIKit.h>

@class YuLiquidMagnifierLensView;

// 以 30fps 把镜片覆盖区域放大渲染进镜片画面，实时同步屏幕内容。
@interface YuLiquidMagnifierCaptureManager : NSObject

@property (nonatomic, weak) YuLiquidMagnifierLensView *lens;
@property (nonatomic, weak) UIWindow *overlayWindow;

- (instancetype)yu_liquidmagnifier_initWithLens:(YuLiquidMagnifierLensView *)lens overlayWindow:(UIWindow *)overlayWindow;
- (void)yu_liquidmagnifier_start;
- (void)yu_liquidmagnifier_stop;

@end
