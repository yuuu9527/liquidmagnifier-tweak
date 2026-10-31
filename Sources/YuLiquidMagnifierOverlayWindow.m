#import "YuLiquidMagnifierOverlayWindow.h"
#import "YuLiquidMagnifierCaptureManager.h"
#import "YuLiquidMagnifierConfig.h"

static YuLiquidMagnifierOverlayWindow *YuLiquidMagnifierSharedWindow;
static NSUInteger YuLiquidMagnifierCreateRetry = 0;

static const CGFloat YuLiquidMagnifierHandleSize = 26.0;

@implementation YuLiquidMagnifierOverlayWindow {
    YuLiquidMagnifierCaptureManager *_captureManager;
    UIView *_handle;
    NSUInteger _sceneRetries;
    BOOL _lensVisible;
}

+ (instancetype)yu_liquidmagnifier_ensureCreated {
    if (YuLiquidMagnifierSharedWindow) return YuLiquidMagnifierSharedWindow;

    // 白名单 / 总开关：当前 App 没被允许就完全不创建
    NSString *bundleID = [NSBundle mainBundle].bundleIdentifier ?: @"";
    YuLiquidMagnifierConfig *config = [YuLiquidMagnifierConfig yu_liquidmagnifier_shared];
    if (![config yu_liquidmagnifier_isEnabledForBundleID:bundleID]) return nil;

    // 极早期（dylib 刚被注入）UIApplication / UIScreen 可能还不存在，等主队列就绪后重试。
    if (![UIApplication sharedApplication] || ![UIScreen mainScreen]) {
        if (YuLiquidMagnifierCreateRetry++ > 50) return nil;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [YuLiquidMagnifierOverlayWindow yu_liquidmagnifier_ensureCreated];
        });
        return nil;
    }
    YuLiquidMagnifierCreateRetry = 0;

    YuLiquidMagnifierOverlayWindow *window = [[self alloc] initWithFrame:[UIScreen mainScreen].bounds];
    YuLiquidMagnifierSharedWindow = window;
    [window yu_liquidmagnifier_attachScene];
    return window;
}

// 切换镜片显示（小圆点 / 快捷指令 / Darwin 通知共用的入口）
+ (void)yu_liquidmagnifier_toggleVisibility {
    YuLiquidMagnifierOverlayWindow *window = [self yu_liquidmagnifier_ensureCreated];
    if (!window) return;
    [window yu_liquidmagnifier_setVisible:!window->_lensVisible];
}

// 设置面板改动后重新应用（白名单 / 圆点开关 / 总开关）
+ (void)yu_liquidmagnifier_refreshForPreferences {
    NSString *bundleID = [NSBundle mainBundle].bundleIdentifier ?: @"";
    YuLiquidMagnifierConfig *config = [YuLiquidMagnifierConfig yu_liquidmagnifier_shared];
    [config yu_liquidmagnifier_reload];

    if (![config yu_liquidmagnifier_isEnabledForBundleID:bundleID]) {
        if (YuLiquidMagnifierSharedWindow) {
            [YuLiquidMagnifierSharedWindow yu_liquidmagnifier_setVisible:NO];
            YuLiquidMagnifierSharedWindow->_handle.hidden = YES;
            YuLiquidMagnifierSharedWindow->_handle.userInteractionEnabled = NO;
        }
        return;
    }
    YuLiquidMagnifierOverlayWindow *window = [self yu_liquidmagnifier_ensureCreated];
    [window yu_liquidmagnifier_applyHandleVisibility];
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
        _lensVisible = NO;

        UIViewController *rootController = [[UIViewController alloc] init];
        rootController.view.backgroundColor = [UIColor clearColor];
        self.rootViewController = rootController;

        // 镜片（默认隐藏）
        CGFloat diameter = 240.0;
        YuLiquidMagnifierLensView *lens =
            [[YuLiquidMagnifierLensView alloc] initWithFrame:CGRectMake(0, 0, diameter, diameter)];
        lens.center = CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame) * 0.7);
        lens.hidden = YES;
        __weak typeof(self) weakSelf = self;
        lens.onSingleTap = ^{
            [weakSelf yu_liquidmagnifier_setVisible:NO];
        };
        [rootController.view addSubview:lens];
        _lens = lens;

        // 常驻小圆点：点一下唤出镜片
        _handle = [[UIView alloc] initWithFrame:CGRectMake(0, 0,
                                                          YuLiquidMagnifierHandleSize,
                                                          YuLiquidMagnifierHandleSize)];
        _handle.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.32];
        _handle.layer.cornerRadius = YuLiquidMagnifierHandleSize / 2.0;
        _handle.layer.borderWidth = 1.0;
        _handle.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.35].CGColor;
        _handle.center = CGPointMake(frame.size.width - YuLiquidMagnifierHandleSize,
                                     frame.size.height * 0.55);

        UIImageView *glyph = [[UIImageView alloc] initWithFrame:_handle.bounds];
        glyph.contentMode = UIViewContentModeCenter;
        glyph.tintColor = [UIColor colorWithWhite:1.0 alpha:0.72];
        if (@available(iOS 13.0, *)) {
            glyph.image = [UIImage systemImageNamed:@"magnifyingglass"];
        }
        [_handle addSubview:glyph];

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self
            action:@selector(yu_liquidmagnifier_handleHandleTap:)];
        [_handle addGestureRecognizer:tap];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self
            action:@selector(yu_liquidmagnifier_handleHandlePan:)];
        [_handle addGestureRecognizer:pan];

        [rootController.view addSubview:_handle];

        _captureManager = [[YuLiquidMagnifierCaptureManager alloc] initWithLens:lens overlayWindow:self];

        self.hidden = NO; // 常驻：只显示小圆点，镜片等点击后再出现
        [self yu_liquidmagnifier_applyHandleVisibility];
    }
    return self;
}

// 不抢 key window，避免影响宿主 App 的输入与键盘
- (BOOL)canBecomeKeyWindow {
    return NO;
}

- (void)yu_liquidmagnifier_attachScene {
    if (self.windowScene != nil || _sceneRetries > 20) return;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            self.windowScene = (UIWindowScene *)scene;
            return;
        }
        _sceneRetries++;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self yu_liquidmagnifier_attachScene];
        });
    }
}

- (void)yu_liquidmagnifier_setVisible:(BOOL)visible {
    if (visible == _lensVisible) return;
    _lensVisible = visible;

    if (!self.windowScene) [self yu_liquidmagnifier_attachScene];
    self.hidden = NO;

    if (visible) {
        _lens.hidden = NO;
        [_captureManager yu_liquidmagnifier_start];
    } else {
        _lens.hidden = YES;
        [_captureManager yu_liquidmagnifier_stop];
    }

    [UIView animateWithDuration:0.16 animations:^{
        [self yu_liquidmagnifier_applyHandleVisibility];
    }];
}

// 小圆点是否显示：受设置里的 showHandle 与镜片是否打开共同决定
- (void)yu_liquidmagnifier_applyHandleVisibility {
    BOOL enabled = [[YuLiquidMagnifierConfig yu_liquidmagnifier_shared] yu_liquidmagnifier_showHandle];
    BOOL show = enabled && !_lensVisible;
    _handle.hidden = !show;
    _handle.alpha = show ? 1.0 : 0.0;
    _handle.userInteractionEnabled = show;
}

/* ── 小圆点交互 ── */

- (void)yu_liquidmagnifier_handleHandleTap:(UITapGestureRecognizer *)recognizer {
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
    [self yu_liquidmagnifier_setVisible:!_lensVisible];
}

- (void)yu_liquidmagnifier_handleHandlePan:(UIPanGestureRecognizer *)recognizer {
    UIView *host = _handle.superview;
    if (!host) return;
    CGPoint translation = [recognizer translationInView:host];
    CGPoint center = _handle.center;
    center.x += translation.x;
    center.y += translation.y;
    [recognizer setTranslation:CGPointZero inView:host];

    CGFloat inset = YuLiquidMagnifierHandleSize / 2.0;
    CGRect bounds = host.bounds;
    center.x = MIN(MAX(center.x, inset), bounds.size.width - inset);
    center.y = MIN(MAX(center.y, inset), bounds.size.height - inset);
    _handle.center = center;
}

// 只接收镜片与小圆点上的触摸，其余全部透传给下层窗口
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (!hit) return nil;
    if (hit == self || hit == self.rootViewController.view) return nil;
    return hit;
}

@end
