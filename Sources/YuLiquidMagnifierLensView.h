#pragma once

#import <UIKit/UIKit.h>

@interface YuLiquidMagnifierLensView : UIView

@property (nonatomic, assign) CGFloat diameter;            // 镜片直径，110 ~ 430
@property (nonatomic, assign) CGFloat zoom;                // 倍率 1.9 / 2.6 / 3.6
@property (nonatomic, strong, readonly) UIImageView *imageView; // 承载实时放大画面
@property (nonatomic, copy) void (^onSingleTap)(void);      // 单击镜片（收起）

- (void)yu_liquidmagnifier_setDiameter:(CGFloat)diameter;
- (void)yu_liquidmagnifier_setZoom:(CGFloat)zoom;
- (void)yu_liquidmagnifier_cycleZoom;
- (void)yu_liquidmagnifier_clampToSuperviewBounds;

@end
