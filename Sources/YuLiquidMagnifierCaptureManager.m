#import "YuLiquidMagnifierCaptureManager.h"
#import "YuLiquidMagnifierLensView.h"
#import <QuartzCore/QuartzCore.h>

@implementation YuLiquidMagnifierCaptureManager {
    CADisplayLink *_displayLink;
    BOOL _running;
}

- (instancetype)yu_liquidmagnifier_initWithLens:(YuLiquidMagnifierLensView *)lens overlayWindow:(UIWindow *)overlayWindow {
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
    if (@available(iOS 10.0, *)) {
        _displayLink.preferredFramesPerSecond = 30;
    } else {
        _displayLink.frameInterval = 2;
    }
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
    if (!lens || !overlay || overlay.hidden) return;

    UIImage *image = [self yu_liquidmagnifier_captureLensArea];
    if (image) {
        lens.imageView.image = image;
    }
}

- (UIImage *)yu_liquidmagnifier_captureLensArea {
    YuLiquidMagnifierLensView *lens = self.lens;
    UIWindow *overlay = self.overlayWindow;
    CGFloat diameter = lens.diameter;
    CGFloat zoom = lens.zoom;
    if (diameter <= 0.0 || zoom <= 0.0) return nil;

    UIView *host = lens.superview;
    CGPoint center = host ? [host convertPoint:lens.center toView:nil] : CGPointZero;

    CGFloat srcSize = diameter / zoom;
    CGRect screen = [UIScreen mainScreen].bounds;
    CGRect srcRect = CGRectMake(center.x - srcSize / 2.0, center.y - srcSize / 2.0, srcSize, srcSize);
    srcRect = CGRectIntersection(srcRect, screen);
    if (CGRectIsEmpty(srcRect)) return nil;

    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.opaque = NO;
    format.scale = [UIScreen mainScreen].scale;

    UIGraphicsImageRenderer *renderer =
        [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(diameter, diameter) format:format];

    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *renderContext) {
        CGContextRef context = renderContext.CGContext;
        CGContextScaleCTM(context, diameter / srcRect.size.width, diameter / srcRect.size.height);
        CGContextTranslateCTM(context, -srcRect.origin.x, -srcRect.origin.y);

        NSArray<UIWindow *> *windows = [UIApplication sharedApplication].windows;
        NSArray<UIWindow *> *sorted = [windows sortedArrayUsingComparator:
            ^NSComparisonResult(UIWindow *window1, UIWindow *window2) {
                CGFloat level1 = window1.windowLevel;
                CGFloat level2 = window2.windowLevel;
                if (level1 < level2) return NSOrderedAscending;
                if (level1 > level2) return NSOrderedDescending;
                return NSOrderedSame;
            }];

        for (UIWindow *window in sorted) {
            if (window == overlay) continue;
            if (window.hidden) continue;
            if (window.frame.size.width <= 0.0 || window.frame.size.height <= 0.0) continue;
            CGRect visible = CGRectIntersection(srcRect, window.frame);
            if (CGRectIsEmpty(visible)) continue;
            CGRect local = CGRectOffset(visible, -window.frame.origin.x, -window.frame.origin.y);
            [window drawViewHierarchyInRect:local afterScreenUpdates:NO];
        }
    }];
    return image;
}

@end
