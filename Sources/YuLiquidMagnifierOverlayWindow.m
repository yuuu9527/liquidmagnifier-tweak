#import "YuLiquidMagnifierOverlayWindow.h"
#import "YuLiquidMagnifierCaptureManager.h"
#import "YuLiquidMagnifierConfig.h"

static YuLiquidMagnifierOverlayWindow *YuLiquidMagnifierSharedWindow;
static NSUInteger YuLiquidMagnifierCreateRetry = 0;

@implementation YuLiquidMagnifierOverlayWindow {
    YuLiquidMagnifierCaptureManager *_captureManager;
    NSUInteger _sceneRetries;
}

+ (instancetype)yu_liquidmagnifier_ensureCreated {
    if (YuLiquidMagnifierSharedWindow) return YuLiquidMagnifierSharedWindow;

    // 极早期（dylib 刚被注入）UIApplication / UIScreen 可能还不存在，
    // 这里不放弃，等主队列就绪后重试若干次。
    if (![UIApplication sharedApplication] || ![UIScreen mainScreen]) {
        if (YuLiquidMagnifierCreateRetry++ > 50) return nil;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            YuLiquidMagnifierOverlayWindow *window = [YuLiquidMagnifierOverlayWindow yu_liquidmagnifier_ensureCreated];
            if (window.hidden) [window yu_liquidmagnifier_setVisible:YES];
        });
        return nil;
    }
    YuLiquidMagnifierCreateRetry = 0;

    YuLiquidMagnifierOverlayWindow *window = [[self alloc] initWithFrame:[UIScreen mainScreen].bounds];
    YuLiquidMagnifierSharedWindow = window;
    [window yu_liquidmagnifier_attachScene];
    return window;
}

// 切换显示：显示时显示、隐藏时隐藏（快捷指令 / Darwin 通知调用）。
+ (void)yu_liquidmagnifier_toggleVisibility {
    YuLiquidMagnifierOverlayWindow *window = YuLiquidMagnifierSharedWindow;
    if (!window) {
        window = [self yu_liquidmagnifier_ensureCreated];
        if (!window) return;
        [window yu_liquidmagnifier_setVisible:YES];
        return;
    }
    [window yu_liquidmagnifier_setVisible:window.hidden];
}

+ (void)yu_liquidmagnifier_hideIfVisible {
    if (!YuLiquidMagnifierSharedWindow) return;
    [YuLiquidMagnifierSharedWindow yu_liquidmagnifier_setVisible:NO];
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        // 高于状态栏、键盘、系统弹层，保证镜片永远在最上层
        self.windowLevel = 1000000.0;
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = YES;
        _sceneRetries = 0;

        UIViewController *rootController = [[UIViewController alloc] init];
        rootController.view.backgroundColor = [UIColor clearColor];
        self.rootViewController = rootController;

        CGFloat diameter = 240.0;
        YuLiquidMagnifierLensView *lens =
            [[YuLiquidMagnifierLensView alloc] initWithFrame:CGRectMake(0, 0, diameter, diameter)];
        lens.center = CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame) * 0.7);
        [rootController.view addSubview:lens];
        _lens = lens;

        _captureManager = [[YuLiquidMagnifierCaptureManager alloc] initWithLens:lens overlayWindow:self];

        self.hidden = YES; // 等快捷指令唤出
    }
    return self;
}

- (void)yu_liquidmagnifier_attachScene {
    if (!(self.windowScene == nil) || _sceneRetries > 20) return;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            self.windowScene = (UIWindowScene *)scene;
            return;
        }
        // 启动初期场景可能还没就绪，稍后重试
        _sceneRetries++;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self yu_liquidmagnifier_attachScene];
        });
    }
}

- (void)yu_liquidmagnifier_setVisible:(BOOL)visible {
    if (visible) {
        if (!self.windowScene) [self yu_liquidmagnifier_attachScene];
        self.hidden = NO;
        [_captureManager yu_liquidmagnifier_start];
    } else {
        self.hidden = YES;
        [_captureManager yu_liquidmagnifier_stop];
    }
}

// 只接收镜片圆内的触摸，其余全部透传给下层窗口
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (!hit) return nil;
    if (hit == self || hit == self.rootViewController.view) {
        return nil; // 空白区域：交给下面的窗口
    }
    return hit; // 镜片及其子视图
}

@end
