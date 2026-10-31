// 设置面板：总开关 + 小圆点开关 + 按 App 白名单
// 通过 PreferenceLoader 在「设置」里出现，写入 /var/mobile/Library/Preferences/com.yu.liquidmagnifier.plist
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <dlfcn.h>
#import <objc/runtime.h>

#define LM_DOMAIN @"com.yu.liquidmagnifier"
#define LM_PREFS_CHANGED @"com.yu.liquidmagnifier.preferences-changed"
#define LM_SWITCH_CELL 6
#define LM_GROUP_CELL 0

// Preferences.framework 里的私有类：只声明用到的接口，运行时由 Settings 进程提供
@interface PSListController : UIViewController
- (NSArray *)specifiers;
- (void)reloadSpecifiers;
@end

@interface PSSpecifier : NSObject
+ (instancetype)groupSpecifierWithName:(NSString *)name;
+ (instancetype)preferenceSpecifierNamed:(NSString *)name
                                  target:(id)target
                                     set:(SEL)set
                                     get:(SEL)get
                                  detail:(Class)detail
                                    cell:(long)cell
                                    edit:(Class)edit;
- (void)setProperty:(id)value forKey:(NSString *)key;
- (id)propertyForKey:(NSString *)key;
@end

static id LMPreference(NSString *key) {
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                        (__bridge CFStringRef)LM_DOMAIN);
    return value ? (__bridge_transfer id)value : nil;
}

static BOOL LMBool(NSString *key, BOOL fallback) {
    id value = LMPreference(key);
    return [value isKindOfClass:[NSNumber class]] ? [value boolValue] : fallback;
}

static void LMSetBool(NSString *key, BOOL value) {
    CFPreferencesSetAppValue((__bridge CFStringRef)key,
                             (__bridge CFPropertyListRef)@(value),
                             (__bridge CFStringRef)LM_DOMAIN);
    CFPreferencesAppSynchronize((__bridge CFStringRef)LM_DOMAIN);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)LM_PREFS_CHANGED,
                                         NULL, NULL, true);
}

// 枚举已安装 App（Settings 进程有权限，不依赖 AppList）
static NSArray<NSDictionary *> *LMInstalledApps(void) {
    static NSArray<NSDictionary *> *cached;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dlopen("/System/Library/Frameworks/MobileCoreServices.framework/MobileCoreServices", RTLD_LAZY);
        NSMutableArray *items = [NSMutableArray array];

        Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
        id workspace = workspaceClass ? [workspaceClass performSelector:@selector(defaultWorkspace)] : nil;
        NSArray *proxies = workspace ? [workspace performSelector:@selector(allInstalledApplications)] : @[];

        for (id proxy in proxies) {
            NSString *bundleID = [proxy performSelector:@selector(applicationIdentifier)];
            NSString *name = [proxy performSelector:@selector(localizedName)];
            if (![bundleID isKindOfClass:[NSString class]] || bundleID.length == 0) continue;
            [items addObject:@{ @"id": bundleID,
                                @"name": ([name isKindOfClass:[NSString class]] && name.length) ? name : bundleID }];
        }
        [items addObject:@{ @"id": @"com.apple.springboard", @"name": @"桌面（SpringBoard）" }];
        [items sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            return [a[@"name"] compare:b[@"name"] options:NSCaseInsensitiveSearch];
        }];
        cached = items;
    });
    return cached;
}

@interface YuLiquidMagnifierPrefsRootListController : PSListController
@end

@implementation YuLiquidMagnifierPrefsRootListController

- (NSArray *)specifiers {
    static NSArray *specifiers;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray *list = [NSMutableArray array];

        PSSpecifier *group = [PSSpecifier groupSpecifierWithName:@"液态放大镜"];
        [group setProperty:@"悬浮放大镜：点小圆点唤出镜片，单击镜片收起。" forKey:@"footerText"];
        [list addObject:group];

        PSSpecifier *enabled = [PSSpecifier preferenceSpecifierNamed:@"启用"
                                                              target:self set:@selector(setEnabled:specifier:)
                                                                 get:@selector(getEnabled:)
                                                              detail:nil cell:LM_SWITCH_CELL edit:nil];
        [list addObject:enabled];

        group = [PSSpecifier groupSpecifierWithName:@"触发方式"];
        [group setProperty:@"关闭后不再显示触发小圆点（可用快捷指令 / lqm 命令唤出）。" forKey:@"footerText"];
        [list addObject:group];

        PSSpecifier *handle = [PSSpecifier preferenceSpecifierNamed:@"显示触发小圆点"
                                                             target:self set:@selector(setShowHandle:specifier:)
                                                                get:@selector(getShowHandle:)
                                                             detail:nil cell:LM_SWITCH_CELL edit:nil];
        [list addObject:handle];

        group = [PSSpecifier groupSpecifierWithName:@"生效范围"];
        [group setProperty:@"选「全部 App」时对所有应用生效；关掉后只对下面勾选的 App 生效。" forKey:@"footerText"];
        [list addObject:group];

        PSSpecifier *allApps = [PSSpecifier preferenceSpecifierNamed:@"全部 App 生效"
                                                              target:self set:@selector(setAllApps:specifier:)
                                                                 get:@selector(getAllApps:)
                                                              detail:nil cell:LM_SWITCH_CELL edit:nil];
        [list addObject:allApps];

        group = [PSSpecifier groupSpecifierWithName:@"仅在以下 App 生效（或关掉全部后使用）"];
        [group setProperty:@"勾选后该 App 内才会出现小圆点。" forKey:@"footerText"];
        [list addObject:group];

        for (NSDictionary *app in LMInstalledApps()) {
            PSSpecifier *cell = [PSSpecifier preferenceSpecifierNamed:app[@"name"]
                                                               target:self set:@selector(setAppEnabled:specifier:)
                                                                  get:@selector(getAppEnabled:)
                                                               detail:nil cell:LM_SWITCH_CELL edit:nil];
            [cell setProperty:app[@"id"] forKey:@"lmid"];
            [list addObject:cell];
        }

        specifiers = list;
    });
    return specifiers;
}

/* ── 总开关 ── */
- (id)getEnabled:(PSSpecifier *)specifier {
    return @(LMBool(@"enabled", YES));
}

- (void)setEnabled:(id)value specifier:(PSSpecifier *)specifier {
    LMSetBool(@"enabled", [value boolValue]);
}

/* ── 小圆点 ── */
- (id)getShowHandle:(PSSpecifier *)specifier {
    return @(LMBool(@"showHandle", YES));
}

- (void)setShowHandle:(id)value specifier:(PSSpecifier *)specifier {
    LMSetBool(@"showHandle", [value boolValue]);
}

/* ── 全部 App ── */
- (id)getAllApps:(PSSpecifier *)specifier {
    return @(LMBool(@"allApps", YES));
}

- (void)setAllApps:(id)value specifier:(PSSpecifier *)specifier {
    LMSetBool(@"allApps", [value boolValue]);
}

/* ── 单个 App ── */
- (id)getAppEnabled:(PSSpecifier *)specifier {
    NSString *bundleID = [specifier propertyForKey:@"lmid"];
    if (bundleID.length == 0) return @NO;
    return @(LMBool(bundleID, NO));
}

- (void)setAppEnabled:(id)value specifier:(PSSpecifier *)specifier {
    NSString *bundleID = [specifier propertyForKey:@"lmid"];
    if (bundleID.length == 0) return;
    LMSetBool(bundleID, [value boolValue]);
}

@end
