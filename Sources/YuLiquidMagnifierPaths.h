#pragma once

#import <Foundation/Foundation.h>

#ifdef THEOS_PACKAGE_SCHEME_ROOTHIDE
#import <roothide.h>
#else
#import <rootless.h>
#endif

static inline NSString *yu_liquidmagnifier_resourcePath(NSString *rootfsPath) {
#ifdef THEOS_PACKAGE_SCHEME_ROOTHIDE
    return jbroot(rootfsPath);
#else
    return ROOT_PATH_NS_VAR(rootfsPath);
#endif
}

static inline NSString *yu_liquidmagnifier_preferencesPath(void) {
    // 用户域偏好文件属于真实系统路径，rootless / roothide 都不应做 jbroot 前缀转换，
    // 否则会指向越狱根的 /var，读不到真正写在 /var/mobile 下的配置。
    return @"/var/mobile/Library/Preferences/com.yu.liquidmagnifier.plist";
}
