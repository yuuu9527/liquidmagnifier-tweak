DEBUG = 0
FINALPACKAGE = 1

ARCHS = arm64 arm64e

# Share the SDK and deployment targets with the PreferenceBundle.
include YuLiquidMagnifierBuild.mk
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = YuLiquidMagnifier
YuLiquidMagnifier_FILES = $(wildcard Hooks/*.xm Sources/*.m)
YuLiquidMagnifier_CFLAGS = -fobjc-arc -I./Headers -I./Sources
YuLiquidMagnifier_FRAMEWORKS = UIKit Foundation CoreFoundation QuartzCore
YuLiquidMagnifier_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk


