#!/bin/bash
# package.sh — 把 MacSensors 打包成可安装的 .dmg 与 .pkg
#
# 产物（generated/dist/）：
#   MacSensors.app                结构规范、ad-hoc 签名的应用包（含真正的 .appex Widget）
#   MacSensors-1.0.dmg            拖拽安装：打开后把 MacSensors 拖进 Applications
#   MacSensors-1.0.pkg            系统安装器：双击按提示装到 /Applications
#
# 前提：先跑 ./build.sh 生成 generated/build/ 下的两个二进制。
set -e
cd "$(dirname "$0")"

D=generated/dist
APP="$D/MacSensors.app"
APPEX="$APP/Contents/PlugIns/MacSensorsWidgetExtension.appex"

echo "==> [1/6] 组装 .app 目录结构"
rm -rf "$D"
mkdir -p "$APP/Contents/"{MacOS,Resources} "$APPEX/Contents/MacOS" "$D/pkg-root/Applications" "$D/dmg-stage"

cp generated/build/MacSensors "$APP/Contents/MacOS/MacSensors"
cp generated/build/MacSensorsWidget "$APPEX/Contents/MacOS/MacSensorsWidgetExtension"
printf 'APPL????' > "$APP/Contents/PkgInfo"
printf 'BNDL????' > "$APPEX/Contents/PkgInfo"

echo "==> [2/6] 生成 AppIcon.icns（iconutil，不依赖完整 Xcode 的 actool）"
ICONSET=/tmp/MacSensors.iconset
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
S=MacSensorsApp/Assets.xcassets/AppIcon.appiconset
for f in icon_16x16.png icon_16x16@2x.png icon_32x32.png icon_32x32@2x.png \
         icon_128x128.png icon_128x128@2x.png icon_256x256.png icon_256x256@2x.png \
         icon_512x512.png icon_512x512@2x.png; do cp "$S/$f" "$ICONSET/$f"; done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "==> [3/6] 写入展开后的 Info.plist"
python3 - <<'PY'
import plistlib
D="generated/dist/MacSensors.app"
APPEX=D+"/Contents/PlugIns/MacSensorsWidgetExtension.appex"
d=plistlib.load(open("MacSensorsApp/Info.plist","rb"))
d.update(CFBundleExecutable="MacSensors", CFBundleIdentifier="com.macsensors.app",
         CFBundleIconFile="AppIcon", LSMinimumSystemVersion="14.0",
         CFBundleShortVersionString="1.0", CFBundleVersion="1")
plistlib.dump(d, open(D+"/Contents/Info.plist","wb"))
w=plistlib.load(open("MacSensorsWidget/Info.plist","rb"))
w.update(CFBundleExecutable="MacSensorsWidgetExtension",
         CFBundleIdentifier="com.macsensors.app.widget",
         CFBundleDisplayName="MacSensorsWidget", LSMinimumSystemVersion="14.0",
         CFBundleShortVersionString="1.0", CFBundleVersion="1")
plistlib.dump(w, open(APPEX+"/Contents/Info.plist","wb"))
PY
cp MacSensorsApp/MacSensors.entitlements "$D/app.entitlements"
cp MacSensorsWidget/MacSensorsWidget.entitlements "$D/widget.entitlements"

echo "==> [4/6] ad-hoc 签名（先签内侧 .appex，再签外侧 .app）"
# 嵌入 entitlements，让 pluginkit / App Group 认识它
codesign --force --sign - --entitlements "$D/widget.entitlements" --options runtime --timestamp=none "$APPEX"
codesign --force --sign - --entitlements "$D/app.entitlements"   --options runtime --timestamp=none "$APP"
codesign -v "$APP" && codesign -v "$APPEX" && echo "    签名验证 ✅"

echo "==> [5/6] 生成 DMG（拖拽到 Applications）"
cp -R "$APP" "$D/dmg-stage/"
ln -s /Applications "$D/dmg-stage/Applications"
hdiutil create -volname MacSensors -srcfolder "$D/dmg-stage" -ov -format UDZO "$D/MacSensors-1.0.dmg" 2>/dev/null

echo "==> [6/6] 生成 PKG（安装到 /Applications）"
cp -R "$APP" "$D/pkg-root/Applications/"
find "$D/pkg-root" -name '._*' -delete 2>/dev/null || true
pkgbuild --root "$D/pkg-root" --identifier com.macsensors.pkg --version 1.0 \
         --install-location / "$D/MacSensors-1.0.pkg" 2>/dev/null

echo
echo "完成 ✅ 安装包："
ls -lh "$D/MacSensors-1.0.dmg" "$D/MacSensors-1.0.pkg"
echo
echo "  DMG: open generated/dist/MacSensors-1.0.dmg  （拖 MacSensors → Applications）"
echo "  PKG: open generated/dist/MacSensors-1.0.pkg  （双击按提示安装）"
