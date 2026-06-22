#!/bin/bash
# 注入 tweak 到 IPA
# 用法: ./inject.sh 行信.ipa

set -e

IPA="$1"
if [ -z "$IPA" ]; then
    echo "用法: ./inject.sh <行信.ipa>"
    exit 1
fi
if [ ! -f "$IPA" ]; then
    echo "❌ 文件不存在: $IPA"
    exit 1
fi

# 找dylib
DYLIB=$(find . -name "*.dylib" | head -1)
if [ -z "$DYLIB" ]; then
    echo "❌ 没找到 dylib，请先运行 build.sh"
    exit 1
fi
DYLIB_NAME=$(basename "$DYLIB")

echo "==> 解压 IPA..."
TMPDIR=$(mktemp -d)
unzip -q "$IPA" -d "$TMPDIR"

APP_PATH=$(find "$TMPDIR" -name "*.app" -type d | head -1)
echo "App: $APP_PATH"

MACHO=$(find "$APP_PATH" -maxdepth 1 -type f -perm +111 | head -1)
echo "Binary: $MACHO"

echo "==> 复制 dylib..."
cp "$DYLIB" "$APP_PATH/"

echo "==> 注入 dylib..."
# 使用 insert_dylib
insert_dylib --strip-codesig --all-yeso "@executable_path/$DYLIB_NAME" "$MACHO" "${MACHO}_patched"
mv "${MACHO}_patched" "$MACHO"
chmod +x "$MACHO"

echo "==> 移除签名..."
rm -rf "$APP_PATH/_CodeSignature"
rm -f "$APP_PATH/embedded.mobileprovision"

echo "==> 重新打包..."
OUTPUT="XingxinWithShare.ipa"
cd "$TMPDIR"
zip -qr "$OLDPWD/$OUTPUT" Payload/

echo "✅ 完成! 输出: $OUTPUT"
echo "用 TrollStore 安装 $OUTPUT 即可"
