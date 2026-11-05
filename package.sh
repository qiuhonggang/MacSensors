#!/bin/bash
# package.sh — 把 MacSensors 打包成可拖拽安装的 .dmg
#
# 产物（generated/dist/）：
#   MacSensors.app           结构规范、ad-hoc 签名的应用包（含真正的 .appex Widget）
#   MacSensors-1.1.1.dmg     拖拽安装：打开后把 MacSensors 拖进 Applications
#
# 说明：本项目只有一个自包含 .app，无守护进程 / 无系统级组件 / 无安装脚本，
#       不需要 PKG 安装器（自 v1.1.1 起不再生成 .pkg）。
# 前提：先跑 ./build.sh 生成 generated/build/ 下的两个二进制。
set -e
cd "$(dirname "$0")"

D=generated/dist
APP="$D/MacSensors.app"
APPEX="$APP/Contents/PlugIns/MacSensorsWidgetExtension.appex"
DMG="$D/MacSensors-1.1.1.dmg"

echo "==> [1/5] 组装 .app 目录结构"
rm -rf "$D"
mkdir -p "$APP/Contents/"{MacOS,Resources} "$APPEX/Contents/MacOS" "$D/dmg-stage"

cp generated/build/MacSensors "$APP/Contents/MacOS/MacSensors"
cp generated/build/MacSensorsWidget "$APPEX/Contents/MacOS/MacSensorsWidgetExtension"
printf 'APPL????' > "$APP/Contents/PkgInfo"
printf 'BNDL????' > "$APPEX/Contents/PkgInfo"

echo "==> [2/5] 生成 AppIcon.icns（iconutil，不依赖完整 Xcode 的 actool）"
ICONSET=/tmp/MacSensors.iconset
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
S=MacSensorsApp/Assets.xcassets/AppIcon.appiconset
for f in icon_16x16.png icon_16x16@2x.png icon_32x32.png icon_32x32@2x.png \
         icon_128x128.png icon_128x128@2x.png icon_256x256.png icon_256x256@2x.png \
         icon_512x512.png icon_512x512@2x.png; do cp "$S/$f" "$ICONSET/$f"; done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "==> [3/5] 写入展开后的 Info.plist"
python3 - <<'PY'
import plistlib
D="generated/dist/MacSensors.app"
APPEX=D+"/Contents/PlugIns/MacSensorsWidgetExtension.appex"
d=plistlib.load(open("MacSensorsApp/Info.plist","rb"))
d.update(CFBundleExecutable="MacSensors", CFBundleIdentifier="com.macsensors.app",
         CFBundleIconFile="AppIcon", LSMinimumSystemVersion="14.0",
         CFBundleShortVersionString="1.1.1", CFBundleVersion="3")
plistlib.dump(d, open(D+"/Contents/Info.plist","wb"))
w=plistlib.load(open("MacSensorsWidget/Info.plist","rb"))
w.update(CFBundleExecutable="MacSensorsWidgetExtension",
         CFBundleIdentifier="com.macsensors.app.widget",
         CFBundleDisplayName="MacSensorsWidget", LSMinimumSystemVersion="14.0",
         CFBundleShortVersionString="1.1.1", CFBundleVersion="3")
plistlib.dump(w, open(APPEX+"/Contents/Info.plist","wb"))
PY
cp MacSensorsApp/MacSensors.entitlements "$D/app.entitlements"
cp MacSensorsWidget/MacSensorsWidget.entitlements "$D/widget.entitlements"

echo "==> [4/5] ad-hoc 签名（先签内侧 .appex，再签外侧 .app）"
codesign --force --sign - --entitlements "$D/widget.entitlements" --options runtime --timestamp=none "$APPEX"
codesign --force --sign - --entitlements "$D/app.entitlements"   --options runtime --timestamp=none "$APP"
codesign -v "$APP" && codesign -v "$APPEX" && echo "    签名验证 ✅"

echo "==> [5/5] 生成 DMG（拖拽到 Applications）"
cp -R "$APP" "$D/dmg-stage/"
ln -s /Applications "$D/dmg-stage/Applications"
hdiutil create -volname MacSensors -srcfolder "$D/dmg-stage" -ov -format UDZO "$DMG" 2>/dev/null

echo
echo "完成 ✅ 安装包："
ls -lh "$DMG"
echo
echo "  open $DMG  （把 MacSensors 拖进 Applications）"
