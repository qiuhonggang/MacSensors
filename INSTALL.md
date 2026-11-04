# MacSensors 安装说明

## 安装包（二选一）

| 文件 | 大小 | 安装方式 |
|---|---|---|
| `generated/dist/MacSensors-1.0.dmg` | 427 KB | 双击挂载 → 把 **MacSensors** 拖进 **Applications** 文件夹 |
| `generated/dist/MacSensors-1.0.pkg` | 397 KB | 双击 → 按安装器提示，自动装到 `/Applications/MacSensors.app` |

两者内容完全一致，都是 **ad-hoc 签名、内含真正的 `MacSensorsWidgetExtension.appex`** 的规范应用包。

## 安装后

1. 打开 `/Applications/MacSensors.app`（或 DMG 里直接运行也可）。
2. 这是 `LSUIElement` 菜单栏应用 —— **没有 Dock 图标**，出现在**屏幕右上角菜单栏**，显示实时温度如 `57°`。
3. 点击菜单栏图标：看 CPU / 风扇 / 功率 / 迷你曲线；菜单里「打开详情窗口」看完整仪表盘。
4. 桌面组件：右键桌面 / 通知中心 →「编辑小组件」→ 搜 **MacSensors** → 添加（小/中/大三种尺寸）。

退出：菜单栏 →「退出 MacSensors」，或 `pkill -f 'MacSensors.app/Contents/MacOS/MacSensors'`。

## 卸载

把 `/Applications/MacSensors.app` 拖到废纸篓即可。
（PKG 安装的可用 `sudo pkgutil --forget com.macsensors.pkg` 清掉收据。）

## 关于签名 / 首次打开

- 用的是 **ad-hoc 签名（`-`）**，不是 Apple Developer ID 签名。本机可直接运行；
  若从别的 Mac 拷贝过来被 Gatekeeper 拦，右键 →「打开」或执行：
  ```bash
  xattr -cr /Applications/MacSensors.app
  ```
- ad-hoc 签名下 entitlements 已嵌入二进制（App Group / 沙箱已验证写入），
  用完整 Xcode ⌘R 或本机运行时 Widget 可被识别。
- **桌面组件可见性**：WidgetKit 的插件发现要求系统认可的签名。若在某些机器上
  「编辑小组件」里搜不到，用完整 Xcode 打开 `MacSensors.xcodeproj` 配真实
  `DEVELOPMENT_TEAM` + "Apple Development" 重新签名运行即可。

## 系统要求

- macOS **14.0+**（Sonoma 及以上）
- **Apple Silicon**（M1/M2/M3/M4；SMC float32 格式针对 Darwin 27 实测）
- Intel Mac / 旧系统：`SMCSensor` 会返回 nil，HID 通道仍可用，App 优雅降级

## 重新打包

```bash
./build.sh      # 编译 + typecheck + 出 .app
./package.sh    # 出 .dmg / .pkg（含图标、ad-hoc 签名、真实 .appex）
```

## 已知限制

- 使用 IOKit 私有 API（`IOHIDEventSystemClient*`）与未公开的 `AppleSMCClient` 调用，
  **不能上架 Mac App Store**，适合自用 / 学习。
- 菜单栏温度每 5 秒刷新；桌面组件时间线每分钟读取一次最近快照（非秒级实时）。
