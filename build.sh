#!/bin/bash
# build.sh — 本地验证 / 构建 MacSensors
#
# 本机环境（Command Line Tools，无完整 Xcode）下：
#   1) 用 xcodegen 生成 .xcodeproj
#   2) 用 swiftc 直接编译主 App 与 Widget 二进制做类型/运行时验证
#   3) 打包出可直接运行的 MacSensors.app（菜单栏应用）
#
# 有完整 Xcode 时：直接 `open MacSensors.xcodeproj` 用 ⌘R 编译运行即可，
# Widget 会作为 PlugIns/MacSensorsWidgetExtension.appex 一同嵌入。
set -e
cd "$(dirname "$0")"

mkdir -p generated/build

echo "==> [1/4] 生成 Xcode 工程"
if command -v xcodegen >/dev/null 2>&1; then
    xcodegen generate
else
    echo "    (未装 xcodegen，跳过；MacSensors.xcodeproj 已存在可直接用)"
fi

# 主 App 编译 SensorReader（含 IOKit 私有 API）；Widget 只编译纯数据模型+存储，
# 编译期即杜绝沙箱内现场采样的可能。
APP_SRC="Shared/SensorModels.swift Shared/SensorReader.swift Shared/SensorStore.swift MacSensorsApp/MacSensorsApp.swift"
WIDGET_SRC="Shared/SensorModels.swift Shared/SensorStore.swift MacSensorsWidget/MacSensorsWidget.swift"

echo "==> [2/4] typecheck 主 App + Widget"
xcrun swiftc -parse-as-library -typecheck -swift-version 5 $APP_SRC
xcrun swiftc -parse-as-library -typecheck -swift-version 5 $WIDGET_SRC
echo "    typecheck OK"

echo "==> [3/4] 编译主 App 与 Widget 二进制"
xcrun swiftc -parse-as-library -swift-version 5 -O -target arm64-apple-macosx14.0 \
    $APP_SRC -o generated/build/MacSensors
xcrun swiftc -parse-as-library -swift-version 5 -O -target arm64-apple-macosx14.0 \
    $WIDGET_SRC -o generated/build/MacSensorsWidget
echo "    build OK"

echo "==> [4/4] 打包 generated/build/MacSensors.app"
APP="generated/build/MacSensors.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/PlugIns"
cp generated/build/MacSensors "$APP/Contents/MacOS/MacSensors"
cp MacSensorsApp/Info.plist "$APP/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string com.macsensors.app "$APP/Contents/Info.plist"
plutil -replace CFBundleExecutable -string MacSensors "$APP/Contents/Info.plist"
plutil -replace LSMinimumSystemVersion -string 14.0 "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
cp generated/build/MacSensorsWidget "$APP/Contents/PlugIns/MacSensorsWidget"
cp MacSensorsWidget/Info.plist "$APP/Contents/PlugIns/Info.plist"

echo
echo "完成 ✅  产物: $APP"
echo "运行:   open \"$APP\""
echo "        （LSUIElement 应用，无 Dock 图标，出现在菜单栏右上角）"
echo "退出:   pkill -f 'MacSensors.app/Contents/MacOS/MacSensors'"
