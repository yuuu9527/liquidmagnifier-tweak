#!/bin/sh
# 在 Linux（含 iSH/Alpine）上不依赖 Theos 主工具链直接交叉编译并打包 deb。
# 依赖：clang、lld（提供 ld64.lld）、ldid、dpkg-deb、perl（跑 logos.pl）
# 需要：iPhoneOS SDK、Theos 的 logos.pl 与 vendor/include
set -eu
cd "$(dirname "$0")"
ROOT=$(pwd)

SDK=${SDK:-/tmp/sdks/iPhoneOS16.5.sdk}
THEOS_DIR=${THEOS_DIR:-/tmp/theos}
LDID=${LDID:-/tmp/ldid/ldid}
LOGO_PL=$(ls "$THEOS_DIR"/vendor/logos/bin/logos.pl 2>/dev/null || echo "$THEOS_DIR/bin/logos.pl")
VENDOR_INC="$THEOS_DIR/vendor/include"
NAME=YuLiquidMagnifier
PKGID=com.yu.liquidmagnifier
VERSION=${VERSION:-5.2.0-1}
MINIOS=15.0

[ -f "$LOGO_PL" ] || { echo "找不到 logos.pl" >&2; exit 1; }
[ -d "$SDK" ] || { echo "找不到 SDK: $SDK" >&2; exit 1; }

SCHEMES=${1:-"rootless roothide"}

for scheme in $SCHEMES; do
    case "$scheme" in
        rootless) DEFINE=-DTHEOS_PACKAGE_SCHEME_ROOTLESS=1
                  ARCH_FIELD=iphoneos-arm64
                  INSTALL_NAME=/var/jb/Library/MobileSubstrate/DynamicLibraries/$NAME.dylib
                  PREFIX=var/jb/ ;;
        roothide) DEFINE=-DTHEOS_PACKAGE_SCHEME_ROOTHIDE=1
                  ARCH_FIELD=iphoneos-arm64e
                  INSTALL_NAME="@loader_path/.jbroot/Library/MobileSubstrate/DynamicLibraries/$NAME.dylib"
                  PREFIX= ;;
        *) echo "未知方案: $scheme" >&2; exit 2 ;;
    esac

    OUT="$ROOT/.build/$scheme"
    rm -rf "$OUT"; mkdir -p "$OUT/obj"

    CF="-target arm64-apple-ios$MINIOS -arch arm64 -isysroot $SDK -miphoneos-version-min=$MINIOS \
        -fobjc-arc -O2 -I$ROOT/Headers -I$ROOT/Sources -I$VENDOR_INC $DEFINE \
        -DLM_VERSION=\"$VERSION\" \
        -Wno-nullability-completeness -Wno-deprecated-declarations"

    perl "$LOGO_PL" Hooks/$NAME"Main.xm" > "$OUT/$NAME"Main.mm
    for f in Sources/*.m; do
        n=$(basename "$f" .m)
        clang $CF -x objective-c -c "$f" -o "$OUT/obj/$n.o"
    done
    clang $CF -x objective-c++ -c "$OUT/$NAME"Main.mm -o "$OUT/obj/${NAME}Main.o"

    clang -target arm64-apple-ios$MINIOS -arch arm64 -isysroot $SDK -miphoneos-version-min=$MINIOS \
        -dynamiclib -fuse-ld=lld \
        -Wl,-install_name,"$INSTALL_NAME" \
        -framework UIKit -framework Foundation -framework CoreFoundation -framework QuartzCore \
        -Wl,-undefined,dynamic_lookup \
        -o "$OUT/$NAME.dylib" "$OUT"/obj/*.o

    "$LDID" -S "$OUT/$NAME.dylib"

    # 触发命令 lqm：给快捷指令 / NewTerm 用
    clang -target arm64-apple-ios$MINIOS -arch arm64 -isysroot $SDK -miphoneos-version-min=$MINIOS \
        -fuse-ld=lld -framework CoreFoundation -o "$OUT/lqm" tools/lqm.c
    "$LDID" -S "$OUT/lqm"

    # 设置面板 bundle（PreferenceLoader）
    BUNDLE="$OUT/LiquidMagnifierPrefs.bundle"
    rm -rf "$BUNDLE"; mkdir -p "$BUNDLE"
    clang -target arm64-apple-ios$MINIOS -arch arm64 -isysroot $SDK -miphoneos-version-min=$MINIOS \
        -fobjc-arc -O2 -bundle -fuse-ld=lld -framework UIKit -framework Foundation \
        -Wl,-undefined,dynamic_lookup -o "$BUNDLE/LiquidMagnifierPrefs" Prefs/*.m
    "$LDID" -S "$BUNDLE/LiquidMagnifierPrefs"
    cp Prefs/Info.plist "$BUNDLE/Info.plist"

    PKGROOT="$OUT/root"
    DL="$PKGROOT/${PREFIX}Library/MobileSubstrate/DynamicLibraries"
    BIN="$PKGROOT/${PREFIX}usr/bin"
    PB="$PKGROOT/${PREFIX}Library/PreferenceBundles"
    PL="$PKGROOT/${PREFIX}Library/PreferenceLoader/Preferences"
    mkdir -p "$DL" "$BIN" "$PB" "$PL" "$PKGROOT/DEBIAN"
    cp "$OUT/$NAME.dylib" "$DL/"
    cp "$NAME.plist" "$DL/"
    cp "$OUT/lqm" "$BIN/lqm"
    chmod 0755 "$BIN/lqm"
    cp -R "$BUNDLE" "$PB/"
    cp Prefs/LiquidMagnifier.plist "$PL/"

    cat > "$PKGROOT/DEBIAN/control" <<EOF
Package: $PKGID
Name: 液态放大镜
Version: $VERSION
Architecture: $ARCH_FIELD
Description: 悬浮实时放大镜，放大当前位置的屏幕内容；单指拖动、双指捏合调圈、双击切倍率。仅悬浮层，不含社交链接。
Maintainer: 鱼教兽
Author: 鱼教兽
Section: Yu-Tweaks
Depends: mobilesubstrate
EOF

    mkdir -p packages
    DEB="packages/${PKGID}_${VERSION}_${ARCH_FIELD}.deb"
    dpkg-deb --root-owner-group -Zxz --build "$PKGROOT" "$ROOT/$DEB" >/dev/null
    printf 'built %s (%s)\n' "$DEB" "$scheme"
done
