# MenuBarCalendar

一个使用 Swift 和 SwiftUI 开发的 macOS 菜单栏日历工具。

## 功能

- 菜单栏显示当前日期，可在设置中自定义格式，例如 `YYYY-MM-DD`、`MM/dd`、`M月d日`。
- 也可以切换为只显示日历图标。
- macOS 13+ 使用 `MenuBarExtra`，macOS 12 回退到 `NSStatusItem + NSPopover`。
- 面板展示当前月日历，自动定位并高亮今天。
- 支持上一月、下一月按钮和左右滑动切换，切换带左右动画。
- 支持在日期下方显示农历，例如“初八”“廿二”。
- 支持设置每周开始日期。
- 周六、周日使用较浅颜色；非本月日期使用更浅颜色。
- 底部显示选中日期的日历事项，可点击事项打开详情弹窗；非订阅日历的事项支持编辑。
- 有日程的日期下方显示日程颜色圆点，每个日期最多显示 4 个。
- 面板高度自适应，不使用滚动条。
- 自动适配深色模式，跟随系统。
- 支持英文和简体中文，根据系统语言自动切换。
- macOS 26+ 使用 Liquid Glass 面板效果；更低版本使用系统模糊材质。

## 构建并打包

```bash
./scripts/build_app.sh
```

产物位于：

```bash
dist/MenuBarCalendar.app
```

## 开发调试

```bash
swift build
```

注意：直接运行 SwiftPM 生成的二进制时，缺少应用 bundle 和 Info.plist，日历权限体验可能不完整。建议使用打包后的 `.app`。

## 使用日历权限

首次展示日历事项时点击“请求日历权限”。如果曾被拒绝，可以在：

```text
系统设置 > 隐私与安全性 > 日历
```

中重新允许 `MenuBarCalendar`。

## 打包细节

当前构建脚本（`scripts/build_app.sh`）已内置：

- **Universal Binary**：同时编译 arm64 + x86_64（Intel 和 Apple Silicon 通用）。
- **App Sandbox**：通过 `MenuBarCalendar.entitlements` 启用沙盒（App Store 必需），
  含日历权限（`personal-information.calendars`）和网络客户端（`network.client`，用于节日数据）。
- **版本号**：优先取脚本第一个参数，其次 `APP_VERSION` 环境变量，其次最新 git tag，兜底 `1.0.0`；
  build 号取 git 提交数。

```bash
./scripts/build_app.sh            # 默认 ad-hoc 签名，本地可用
./scripts/build_app.sh 1.2.0      # 指定版本号
```

### 生成 DMG

```bash
./scripts/make_dmg.sh             # 产出 dist/MenuBarCalendar.dmg
./scripts/make_dmg.sh 1.2.0       # 产出 dist/MenuBarCalendar-1.2.0.dmg
```

> 注意：DMG 未公证，接收方首次打开需右键 → 打开（或 `xattr -cr MenuBarCalendar.app`）。

### 应用图标

```bash
./scripts/make_icon.sh path/to/1024x1024.png   # 生成 Resources/AppIcon.icns
./scripts/build_app.sh                          # 重新打包即自动带上
```

### 将来正式签名（开通 Developer Program 后）

```bash
# DMG 分发（Developer ID + 公证）
SIGN_IDENTITY="Developer ID Application: 你的名字 (TEAMID)" ./scripts/build_app.sh
xcrun notarytool submit dist/MenuBarCalendar.dmg --keychain-profile PROFILE --wait
xcrun stapler staple dist/MenuBarCalendar.dmg
```
