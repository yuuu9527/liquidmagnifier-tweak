#pragma once

#import <Foundation/Foundation.h>

@interface YuLiquidMagnifierConfig : NSObject
+ (instancetype)yu_liquidmagnifier_shared;
- (BOOL)yu_liquidmagnifier_isEnabled;
// 当前 App 是否生效（受 allApps / 单个 bundleID 开关控制）
- (BOOL)yu_liquidmagnifier_isEnabledForBundleID:(NSString *)bundleID;
// 是否显示触发小圆点
- (BOOL)yu_liquidmagnifier_showHandle;
- (id)yu_liquidmagnifier_valueForKey:(NSString *)key defaultValue:(id)defaultValue;
- (void)yu_liquidmagnifier_reload;
@end
