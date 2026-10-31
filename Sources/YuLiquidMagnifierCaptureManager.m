#import "YuLiquidMagnifierCaptureManager.h"
#import <QuartzCore/QuartzCore.h>
#import "YuLiquidMagnifierLensView.h"

@implementation YuLiquidMagnifierCaptureManager {
    CADisplayLink *_displayLink;
    BOOL _running;
}

- (instancetype)initWithLens:(YuLiquidMagnifierLensView *)lens overlayWindow:(UIWindow *)overlayWindow {
    self = [super init];
    if (self) {
        _lens = lens;
        _overlayWindow = overlayWindow;
    }
    return self;
}

- (void)yu_liquidmagnifier_start {
    if (_running) return;
    _running = YES;
    _displayLink = [CADisplayLink displayLinkWithTarget:self
        selector:@selector(yu_liquidmagnifier_tick:)];
    _displayLink.preferredFramesPerSecond = 30;
    [_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)yu_liquidmagnifier_stop {
    if (!_running) return;
    _running = NO;
    [_displayLink invalidate];
    _displayLink = nil;
}

- (void)yu_liquidmagnifier_tick:(CADisplayLink *)link {
    YuLiquidMagnifierLensView *lens = self.lens;
    UIWindow *overlay = self.overlayWindow;
    if (!lens || !overlay) return;
    if (lens.hidden) return;

    UIImage *image = [self yu_liquidmagnifier_captureLensArea];
    if (image) {
        lens.imageView.image = image;
    }
}

// 镜片可见区域（屏幕点坐标）
static CGRect YuLiquidMagnifierSourceRect(YuLiquidMagnifierLensView *lens, CGPoint center) {
    CGFloat srcSize = lens.diameter / MAX(lens.zoom, 0.1);
    CGRect screen = [UIScreen mainScreen].bounds;
    CGRect rect = CGRectMake(center.x - srcSize / 2.0, center.y - srcSize / 2.0, srcSize, srcSize);
    rect = CGRectIntersection(rect, screen);
    return rect;
}

- (UIImage *)yu_liquidmagnifier_captureLensArea {
    YuLiquidMagnifierLensView *lens = self.lens;
    UIWindow *overlay = self.overlayWindow;
    CGFloat diameter = lens.diameter;
    if (diameter <= 0.0 || lens.zoom <= 0.0) return nil;

    // 镜片中心换算成屏幕坐标
    UIView *host = lens.superview;
    CGPoint center = host ? [host convertPoint:lens.center toView:nil] : CGPointZero;

    CGRect srcRect = YuLiquidMagnifierSourceRect(lens, center);
    if (CGRectIsEmpty(srcRect)) return nil;

    CGRect screen = [UIScreen mainScreen].bounds;
    CGFloat scale = [UIScreen mainScreen].scale;

    // 1) 按 1:1 合成当前屏幕（drawViewHierarchyInRect 会忽略外部缩放矩阵，
    //    所以这里绝不能在缩放过的上下文里画，必须先合成再裁剪。）
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.opaque = NO;
    format.scale = scale;
    UIGraphicsImageRenderer *screenRenderer =
        [[UIGraphicsImageRenderer alloc] initWithSize:screen.size format:format];

    NSArray<UIWindow *> *windows = [UIApplication sharedApplication].windows;
    NSArray<UIWindow *> *sorted = [windows sortedArrayUsingComparator:
        ^NSComparisonResult(UIWindow *window1, UIWindow *window2) {
            CGFloat level1 = window1.windowLevel;
            CGFloat level2 = window2.windowLevel;
            if (level1 < level2) return NSOrderedAscending;
            if (level1 > level2) return NSOrderedDescending;
            return NSOrderedSame;
        }];

    UIImage *screenImage = [screenRenderer imageWithActions:^(UIGraphicsImageRendererContext *renderContext) {
        for (UIWindow *window in sorted) {
            if (window == overlay) continue;          // 不把自己画进去
            if (window.hidden || window.alpha < 0.01) continue;
            if (window.frame.size.width <= 0.0 || window.frame.size.height <= 0.0) continue;
            if (CGRectIsEmpty(CGRectIntersection(window.frame, srcRect))) continue;
            [window drawViewHierarchyInRect:window.frame afterScreenUpdates:NO];
        }
    }];

    // 2) 从合成图里裁出镜片正下方那块，交给镜片按 zoom 拉伸
    CGRect pixelRect = CGRectMake(srcRect.origin.x * scale,
                                  srcRect.origin.y * scale,
                                  srcRect.size.width * scale,
                                  srcRect.size.height * scale);
    CGImageRef cropped = CGImageCreateWithImageInRect(screenImage.CGImage, pixelRect);
    if (!cropped) return nil;

    UIImage *image = [UIImage imageWithCGImage:cropped
                                         scale:scale
                                   orientation:UIImageOrientationUp];
    CGImageRelease(cropped);
    return image;
}

@end
