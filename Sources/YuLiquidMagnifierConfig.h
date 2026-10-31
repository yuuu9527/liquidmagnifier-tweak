#pragma once

#import <Foundation/Foundation.h>

@interface YuLiquidMagnifierConfig : NSObject
+ (instancetype)yu_liquidmagnifier_shared;
- (BOOL)yu_liquidmagnifier_isEnabled;
- (id)yu_liquidmagnifier_valueForKey:(NSString *)key defaultValue:(id)defaultValue;
- (void)yu_liquidmagnifier_reload;
@end
