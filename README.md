# 液态放大镜（LiquidMagnifier）

悬浮实时放大镜：需要时唤出一个圆形镜片，实时放大当前位置的屏幕内容。

## 触发

镜片**默认不显示**，两种唤出方式：

| 方式 | 操作 |
|---|---|
| 三指长按 | 前台任意位置三指按住约 0.5 秒 → 显示／再次三指长按 → 隐藏（有轻微触感反馈） |
| 快捷指令 | 建一个「通过 SSH 运行脚本」的快捷指令，执行 `notifyutil -p com.yu.liquidmagnifier.toggle` |

Darwin 通知名（仅供调用，不是 URL）：

- `com.yu.liquidmagnifier.toggle` — 显示／隐藏切换
- `com.yu.liquidmagnifier.show` — 强制显示
- `com.yu.liquidmagnifier.hide` — 强制隐藏

快捷指令做法：`快捷指令` → 新建 → 添加「通过 SSH 运行脚本」（主机 `localhost`，端口 22，用户 `root`，密码填你设备的 root 密码）→ 脚本内容 `notifyutil -p com.yu.liquidmagnifier.toggle` → 保存后可加到主屏、Siri 或自动化里。设备需装有 OpenSSH（Sileo 里搜 `openssh`）。

## 镜片操作

| 手势 | 作用 |
|---|---|
| 单指拖动 | 移动镜片（轻微速度挤压，无旋转） |
| 双指捏合 | 调整镜片大小（110 ~ 430 pt） |
| 双击 | 循环切换倍率 1.9× / 2.6× / 3.6× |

镜片只在当前前台进程显示，且仅镜片圆内接收触摸，圆外触摸全部透传给下面的 App；隐藏时会停掉 30fps 采集，不占资源。

## 构建

- **GitHub Actions**：推送到 `main` / `master` 或手动触发 `Build LiquidMagnifier`（ubuntu + clang/lld 交叉编译），产物在 Release 中，同时给出 Rootless 与 Roothide 两个包。
- **本地构建**（Linux / iSH Alpine 均可，需要 clang、lld、ldid、perl、dpkg-deb、iPhoneOS16.5 SDK、Theos 的 logos.pl 与 vendor/include）：

  ```sh
  SDK=/path/to/iPhoneOS16.5.sdk THEOS_DIR=/path/to/theos LDID=/path/to/ldid \
    VERSION=5.3.0-1 sh build_linux.sh            # 两套都出
  sh build_linux.sh rootless                     # 只出 rootless
  ```

  产物：`packages/com.yu.liquidmagnifier_<版本>_iphoneos-arm64.deb`（rootless，落 `/var/jb`）、
  `..._iphoneos-arm64e.deb`（roothide，落 bootstrap 根，install_name 为 `@loader_path/.jbroot/...`）。

## 工程结构

- `Hooks/YuLiquidMagnifierMain.xm` — 注入入口：三指长按挂载、Darwin 通知监听、前后台显隐
- `Sources/YuLiquidMagnifierOverlayWindow.{h,m}` — 悬浮窗口：`windowLevel = 1000000` 永远置顶；`hitTest` 只接管镜片圆内触摸；三指长按手势挂在当前 key window 上（`cancelsTouchesInView = NO`，不影响 App 自身操作）
- `Sources/YuLiquidMagnifierLensView.{h,m}` — 圆形镜片：手势、尺寸/倍率、玻璃描边
- `Sources/YuLiquidMagnifierCaptureManager.{h,m}` — 30fps 实时截屏：把镜片覆盖区域按倍率放大渲染进镜片（显示时才运行）
- `build_linux.sh` — 不依赖 Theos 主工具链的交叉编译 + 打包脚本
