#import "YuLiquidMagnifierOverlayWindow.h"
#import "YuLiquidMagnifierCaptureManager.h"

static YuLiquidMagnifierOverlayWindow *YuLiquidMagnifierSharedWindow;

@implementation YuLiquidMagnifierOverlayWindow {
    YuLiquidMagnifierCaptureManager *_captureManager;
}

+ (instancetype)yu_liquidmagnifier_ensureVisible {
    if (YuLiquidMagnifierSharedWindow) {
        [YuLiquidMagnifierSharedWindow yu_liquidmagnifier_setVisible:YES];
        return YuLiquidMagnifierSharedWindow;
    }
    if (![UIApplication sharedApplication]) return nil;
    if (![UIScreen mainScreen]) return nil;

    YuLiquidMagnifierOverlayWindow *window = [[self alloc] initWithFrame:[UIScreen mainScreen].bounds];
    YuLiquidMagnifierSharedWindow = window;
    [window yu_liquidmagnifier_attachScene];
    return window;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        // 高于状态栏、键盘、系统弹层，保证镜片永远在最上层
        self.windowLevel = 1000000.0;
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = YES;

        UIViewController *rootController = [[UIViewController alloc] init];
        rootController.view.backgroundColor = [UIColor clearColor];
        self.rootViewController = rootController;

        CGFloat diameter = 240.0;
        YuLiquidMagnifierLensView *lens =
            [[YuLiquidMagnifierLensView alloc] initWithFrame:CGRectMake(0, 0, diameter, diameter)];
        lens.center = CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame) * 0.7);
        [rootController.view addSubview:lens];
        _lens = lens;

        _captureManager = [[YuLiquidMagnifierCaptureManager alloc] yu_liquidmagnifier_initWithLens:lens overlayWindow:self];
        [_captureManager yu_liquidmagnifier_start];

        self.hidden = YES; // 前台活跃时才显示
    }
    return self;
}

- (void)yu_liquidmagnifier_attachScene {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                self.windowScene = (UIWindowScene *)scene;
                break;
            }
        }
        if (!self.windowScene) {
            // 启动初期场景可能还没就绪，稍后重试
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                [self yu_liquidmagnifier_attachScene];
            });
        }
    }
}

- (void)yu_liquidmagnifier_setVisible:(BOOL)visible {
    if (visible) {
        if (!self.windowScene) [self yu_liquidmagnifier_attachScene];
        self.hidden = NO;
    } else {
        self.hidden = YES;
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
