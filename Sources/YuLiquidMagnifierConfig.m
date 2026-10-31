#import "YuLiquidMagnifierConfig.h"
#import "YuLiquidMagnifierPreferences.h"

@interface YuLiquidMagnifierConfig ()
@property (atomic, copy) NSDictionary *snapshot;
@property (nonatomic, strong) dispatch_queue_t reloadQueue;
@end

static void yu_liquidmagnifier_preferencesDidChange(CFNotificationCenterRef center, void *observer,
                                          CFStringRef name, const void *object, CFDictionaryRef info) {
    YuLiquidMagnifierConfig *config = (__bridge YuLiquidMagnifierConfig *)observer;
    dispatch_async(config.reloadQueue, ^{
        [config yu_liquidmagnifier_reload];
    });
}

@implementation YuLiquidMagnifierConfig

+ (instancetype)yu_liquidmagnifier_shared {
    static YuLiquidMagnifierConfig *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _reloadQueue = dispatch_queue_create("com.yu.liquidmagnifier.preferences", DISPATCH_QUEUE_SERIAL);
        [self yu_liquidmagnifier_reload];
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
            (__bridge const void *)self, yu_liquidmagnifier_preferencesDidChange,
            (__bridge CFStringRef)YuLiquidMagnifierPreferencesChanged, NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
        // Close the window between the first read and observer registration.
        dispatch_async(_reloadQueue, ^{ [self yu_liquidmagnifier_reload]; });
    }
    return self;
}

- (void)yu_liquidmagnifier_reload {
    self.snapshot = yu_liquidmagnifier_readPreferences();
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:YuLiquidMagnifierPreferencesChanged object:self];
    });
}

- (id)yu_liquidmagnifier_valueForKey:(NSString *)key defaultValue:(id)defaultValue {
    return self.snapshot[key] ?: defaultValue;
}

- (BOOL)yu_liquidmagnifier_isEnabled {
    id value = [self yu_liquidmagnifier_valueForKey:@"enabled" defaultValue:@(YES)];
    return [value isKindOfClass:[NSNumber class]] ? [value boolValue] : YES;
}

- (BOOL)yu_liquidmagnifier_isEnabledForBundleID:(NSString *)bundleID {
    if (![self yu_liquidmagnifier_isEnabled]) return NO;

    id allValue = [self yu_liquidmagnifier_valueForKey:@"allApps" defaultValue:@(YES)];
    BOOL allApps = [allValue isKindOfClass:[NSNumber class]] ? [allValue boolValue] : YES;
    if (allApps) return YES;

    if (bundleID.length == 0) return NO;
    id value = self.snapshot[bundleID];
    return [value isKindOfClass:[NSNumber class]] ? [value boolValue] : NO;
}

- (BOOL)yu_liquidmagnifier_showHandle {
    id value = [self yu_liquidmagnifier_valueForKey:@"showHandle" defaultValue:@(YES)];
    return [value isKindOfClass:[NSNumber class]] ? [value boolValue] : YES;
}

- (void)dealloc {
    CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                            (__bridge const void *)self);
}

@end
