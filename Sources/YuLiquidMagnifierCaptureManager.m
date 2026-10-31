#import "YuLiquidMagnifierCaptureManager.h"
#import <QuartzCore/QuartzCore.h>
#import "YuLiquidMagnifierLensView.h"

// 底图刷新间隔：静止时每 0.2s 重新拍一张屏（连续画面仍有 5fps），
// 拖动期间完全冻结底图，只做「裁剪 + 拉伸」，保证拖动丝滑。
static const CFTimeInterval YuLiquidMagnifierSnapshotInterval = 0.2;

@implementation YuLiquidMagnifierCaptureManager {
    CADisplayLink *_displayLink;
    BOOL _running;
    BOOL _interactive;        // 正在拖动 / 捏合
    CGImageRef _snapshot;     // 全屏 1:1 快照
    CFTimeInterval _snapshotAt;
    CGRect _lastSrcRect;
    CGFloat _lastZoom;
    BOOL _hasCrop;
}

- (instancetype)initWithLens:(YuLiquidMagnifierLensView *)lens overlayWindow:(UIWindow *)overlayWindow {
    self = [super init];
    if (self) {
        _lens = lens;
        _overlayWindow = overlayWindow;
    }
    return self;
}

- (void)dealloc {
    if (_snapshot) CGImageRelease(_snapshot);
}

- (void)yu_liquidmagnifier_start {
    if (_running) return;
    _running = YES;
    _displayLink = [CADisplayLink displayLinkWithTarget:self
        selector:@selector(yu_liquidmagnifier_tick:)];
    _displayLink.preferredFramesPerSecond = 60;
    [_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)yu_liquidmagnifier_stop {
    if (!_running) return;
    _running = NO;
    [_displayLink invalidate];
    _displayLink = nil;
    if (_snapshot) {
        CGImageRelease(_snapshot);
        _snapshot = NULL;
    }
    _hasCrop = NO;
}

// 拖动/捏合开始：冻结底图，只做裁剪；结束：立刻重拍一张
- (void)yu_liquidmagnifier_setInteractive:(BOOL)interactive {
    _interactive = interactive;
    if (!interactive) _snapshotAt = 0;
}

- (void)yu_liquidmagnifier_tick:(CADisplayLink *)link {
    YuLiquidMagnifierLensView *lens = self.lens;
    if (!lens || lens.hidden) return;
    if (!_lens.imageView.superview) return;

    UIView *host = lens.superview;
    CGPoint center = host ? [host convertPoint:lens.center toView:nil] : CGPointZero;

    CGFloat srcSize = lens.diameter / MAX(lens.zoom, 0.1);
    CGRect screen = [UIScreen mainScreen].bounds;
    CGRect srcRect = CGRectIntersection(
        CGRectMake(center.x - srcSize / 2.0, center.y - srcSize / 2.0, srcSize, srcSize), screen);
    if (CGRectIsEmpty(srcRect)) return;

    CFTimeInterval now = CACurrentMediaTime();
    BOOL needSnapshot = (_snapshot == NULL) ||
                        (!_interactive && (now - _snapshotAt) >= YuLiquidMagnifierSnapshotInterval);
    if (needSnapshot) {
        CGImageRef fresh = [self yu_liquidmagnifier_captureScreenImage];
        if (fresh) {
            if (_snapshot) CGImageRelease(_snapshot);
            _snapshot = fresh;
            _snapshotAt = now;
            _hasCrop = NO;
        }
    }
    if (!_snapshot) return;

    // 位置/倍率没变就复用上一帧，避免无谓裁剪
    if (_hasCrop && CGSizeEqualToSize(srcRect.size, _lastSrcRect.size) &&
        CGPointEqualToPoint(srcRect.origin, _lastSrcRect.origin) && lens.zoom == _lastZoom) {
        return;
    }

    CGFloat scale = [UIScreen mainScreen].scale;
    CGRect pixelRect = CGRectMake(srcRect.origin.x * scale, srcRect.origin.y * scale,
                                  srcRect.size.width * scale, srcRect.size.height * scale);
    CGImageRef cropped = CGImageCreateWithImageInRect(_snapshot, pixelRect);
    if (!cropped) return;

    lens.imageView.image = [UIImage imageWithCGImage:cropped
                                               scale:scale
                                         orientation:UIImageOrientationUp];
    CGImageRelease(cropped);

    _lastSrcRect = srcRect;
    _lastZoom = lens.zoom;
    _hasCrop = YES;
}

// 按 1:1 合成当前屏幕。注意 drawViewHierarchyInRect 会忽略外部缩放矩阵，
// 所以这里不缩放，裁剪交给 CGImageCreateWithImageInRect。
- (CGImageRef)yu_liquidmagnifier_captureScreenImage {
    CGRect screen = [UIScreen mainScreen].bounds;
    CGFloat scale = [UIScreen mainScreen].scale;

    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.opaque = NO;
    format.scale = scale;
    UIGraphicsImageRenderer *renderer =
        [[UIGraphicsImageRenderer alloc] initWithSize:screen.size format:format];

    UIWindow *overlay = self.overlayWindow;
    NSArray<UIWindow *> *windows = [UIApplication sharedApplication].windows;
    NSArray<UIWindow *> *sorted = [windows sortedArrayUsingComparator:
        ^NSComparisonResult(UIWindow *window1, UIWindow *window2) {
            CGFloat level1 = window1.windowLevel;
            CGFloat level2 = window2.windowLevel;
            if (level1 < level2) return NSOrderedAscending;
            if (level1 > level2) return NSOrderedDescending;
            return NSOrderedSame;
        }];

    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *renderContext) {
        for (UIWindow *window in sorted) {
            if (window == overlay) continue;
            if (window.hidden || window.alpha < 0.01) continue;
            if (window.frame.size.width <= 0.0 || window.frame.size.height <= 0.0) continue;
            [window drawViewHierarchyInRect:window.frame afterScreenUpdates:NO];
        }
    }];

    return image.CGImage ? CGImageRetain(image.CGImage) : NULL;
}

@end
