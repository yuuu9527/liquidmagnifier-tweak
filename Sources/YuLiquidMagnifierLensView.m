#import "YuLiquidMagnifierLensView.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat YuLiquidMagnifierMinDiameter = 110.0;
static const CGFloat YuLiquidMagnifierMaxDiameter = 430.0;
static const CGFloat YuLiquidMagnifierZoomLevels[] = { 1.9f, 2.6f, 3.6f };
static const NSUInteger YuLiquidMagnifierZoomCount = 3;

@implementation YuLiquidMagnifierLensView {
    UIImageView *_imageView;
    UIPinchGestureRecognizer *_pinchRecognizer;
    CGFloat _pinchLastScale;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _diameter = MAX(YuLiquidMagnifierMinDiameter, MIN(YuLiquidMagnifierMaxDiameter, frame.size.width));
        if (_diameter != frame.size.width) {
            frame.size.width = _diameter;
            frame.size.height = _diameter;
            self.frame = frame;
        }
        _zoom = 2.6f;

        self.backgroundColor = [UIColor blackColor];
        self.clipsToBounds = YES;
        self.layer.cornerRadius = _diameter / 2.0;
        self.layer.borderWidth = 1.0;
        self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.35].CGColor;

        _imageView = [[UIImageView alloc] initWithFrame:self.bounds];
        _imageView.contentMode = UIViewContentModeScaleToFill;
        _imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:_imageView];

        [self yu_liquidmagnifier_addGestures];
    }
    return self;
}

- (void)yu_liquidmagnifier_addGestures {
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self
        action:@selector(yu_liquidmagnifier_handlePan:)];
    pan.maximumNumberOfTouches = 1;
    [self addGestureRecognizer:pan];

    _pinchRecognizer = [[UIPinchGestureRecognizer alloc] initWithTarget:self
        action:@selector(yu_liquidmagnifier_handlePinch:)];
    [self addGestureRecognizer:_pinchRecognizer];

    UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self
        action:@selector(yu_liquidmagnifier_handleDoubleTap:)];
    doubleTap.numberOfTapsRequired = 2;
    [self addGestureRecognizer:doubleTap];

    // 单击收起镜片：必须等双击失败，避免切倍率时误收起
    UITapGestureRecognizer *singleTap = [[UITapGestureRecognizer alloc] initWithTarget:self
        action:@selector(yu_liquidmagnifier_handleSingleTap:)];
    singleTap.numberOfTapsRequired = 1;
    [singleTap requireGestureRecognizerToFail:doubleTap];
    [self addGestureRecognizer:singleTap];
}

- (void)yu_liquidmagnifier_handleSingleTap:(UITapGestureRecognizer *)recognizer {
    void (^handler)(void) = self.onSingleTap;
    if (handler) handler();
}


/* ── 单指拖动 ── */
- (void)yu_liquidmagnifier_handlePan:(UIPanGestureRecognizer *)recognizer {
    UIView *host = self.superview;
    if (!host) return;

    if (recognizer.state == UIGestureRecognizerStateChanged) {
        CGPoint translation = [recognizer translationInView:host];
        CGPoint center = self.center;
        center.x += translation.x;
        center.y += translation.y;
        self.center = center;
        [recognizer setTranslation:CGPointZero inView:host];

        // 速度带来的轻微挤压（无旋转，避免画面翻转）
        CGPoint velocity = [recognizer velocityInView:host];
        CGFloat speed = sqrt(velocity.x * velocity.x + velocity.y * velocity.y);
        CGFloat k = MIN(speed * 0.00004, 0.05);
        self.transform = CGAffineTransformMakeScale(1.0 + k, 1.0 - k * 0.6);
    } else if (recognizer.state == UIGestureRecognizerStateEnded ||
               recognizer.state == UIGestureRecognizerStateCancelled) {
        [UIView animateWithDuration:0.25 animations:^{
            self.transform = CGAffineTransformIdentity;
        }];
    }
    [self yu_liquidmagnifier_clampToSuperviewBounds];
}

/* ── 双指捏合调圈大小 ── */
- (void)yu_liquidmagnifier_handlePinch:(UIPinchGestureRecognizer *)recognizer {
    if (recognizer.state == UIGestureRecognizerStateBegan) {
        _pinchLastScale = 1.0;
        return;
    }
    if (recognizer.state == UIGestureRecognizerStateChanged) {
        CGFloat delta = recognizer.scale / MAX(_pinchLastScale, 0.01);
        _pinchLastScale = recognizer.scale;
        [self yu_liquidmagnifier_setDiameter:_diameter * delta];
    }
}

/* ── 双击切换倍率 ── */
- (void)yu_liquidmagnifier_handleDoubleTap:(UITapGestureRecognizer *)recognizer {
    [self yu_liquidmagnifier_cycleZoom];
}

- (void)yu_liquidmagnifier_cycleZoom {
    NSUInteger index = 1;
    for (NSUInteger i = 0; i < YuLiquidMagnifierZoomCount; i++) {
        if (ABS(YuLiquidMagnifierZoomLevels[i] - _zoom) < 0.05) {
            index = i;
            break;
        }
    }
    [self yu_liquidmagnifier_setZoom:YuLiquidMagnifierZoomLevels[(index + 1) % YuLiquidMagnifierZoomCount]];
}

- (void)yu_liquidmagnifier_setDiameter:(CGFloat)diameter {
    diameter = MAX(YuLiquidMagnifierMinDiameter, MIN(YuLiquidMagnifierMaxDiameter, diameter));
    if (ABS(diameter - _diameter) < 0.5) return;
    _diameter = diameter;

    CGPoint center = self.center;
    self.bounds = CGRectMake(0, 0, diameter, diameter);
    self.center = center;
    self.layer.cornerRadius = diameter / 2.0;
    [self yu_liquidmagnifier_clampToSuperviewBounds];
}

- (void)yu_liquidmagnifier_setZoom:(CGFloat)zoom {
    if (zoom <= 0.0) return;
    _zoom = zoom;
}

- (void)yu_liquidmagnifier_clampToSuperviewBounds {
    UIView *host = self.superview;
    if (!host) return;
    CGFloat radius = _diameter / 2.0 + 2.0;
    CGRect bounds = host.bounds;
    CGPoint center = self.center;
    center.x = MIN(MAX(center.x, radius), bounds.size.width - radius);
    center.y = MIN(MAX(center.y, radius), bounds.size.height - radius);
    self.center = center;
}

@end
