# 液态放大镜（LiquidMagnifier）

悬浮实时放大镜：屏幕上方一个圆形镜片，实时放大当前位置的屏幕内容。

## 交互

| 手势 | 作用 |
|---|---|
| 单指拖动 | 移动镜片（轻微速度挤压，无旋转） |
| 双指捏合 | 调整镜片大小（110 ~ 430 pt） |
| 双击 | 循环切换倍率 1.9× / 2.6× / 3.6× |

镜片只在前台活跃进程显示（主屏、App 内都可用）；镜片圆以外的触摸全部透传，不影响正常操作。

## 构建

- **GitHub Actions（推荐）**：推送到 `main` / `master` 或手动触发 `Build LiquidMagnifier`，产物 deb 在 Release 中，版本 `5.2.0-<run>`，Rootless（arm64 / arm64e）。
- **本地构建**（需 Theos + iOS 16.5 SDK 的 macOS 环境）：

  ```sh
  sh build.sh rootless
  ```

## 工程结构

- `Hooks/YuLiquidMagnifierMain.xm` — 注入入口：监听前台/后台通知，控制镜片显示
- `Sources/YuLiquidMagnifierOverlayWindow.{h,m}` — 悬浮窗口：`windowLevel = 1000000` 永远置顶；`hitTest` 只接管镜片圆内触摸
- `Sources/YuLiquidMagnifierLensView.{h,m}` — 圆形镜片：手势、尺寸/倍率、玻璃描边
- `Sources/YuLiquidMagnifierCaptureManager.{h,m}` — 30fps 实时截屏：把镜片覆盖区域按倍率放大渲染进镜片

## 实现要点与边界

- **全进程注入**（`YuLiquidMagnifier.plist` 空 `Filter`）：放大镜需要在主屏与所有 App 内生效；同一进程内用 `drawViewHierarchyInRect:` 合成窗口，因此能实时放大本进程可见内容（App 界面、主屏图标、键盘等）。
- **前台判定**：用 `UIApplicationDidBecomeActive` / `WillResignActive` 控制显示，避免主屏与前台 App 同时出现两个镜片。
- **性能**：CADisplayLink 30fps，只渲染镜片覆盖的小矩形，不做全屏截图。
- **限制**：不跨进程截屏（App 前台时由该 App 自身的镜片实例负责放大）；未做真机实测，需在目标越狱设备验收。
- 本插件仅包含悬浮放大功能，不含任何社交链接、推广入口或关于页。

## 版本

- 最低部署 iOS 15.0（Rootless），SDK 16.5
- 包名 `com.yu.liquidmagnifier`
