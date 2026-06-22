#!/bin/bash
# 全自动编译+注入脚本 (macOS)
# 用法: ./build_and_inject.sh 行信.ipa

set -e

IPA="${1:-ipa/xingxin.ipa}"
if [ ! -f "$IPA" ]; then
    echo "用法: $0 <行信.ipa>"
    echo "或者把行信.ipa放到 ipa/ 目录"
    exit 1
fi

echo "==> 检查 theos..."
THEOS="${THEOS:-/opt/theos}"
if [ ! -d "$THEOS" ]; then
    echo "安装 theos..."
    git clone --recursive --depth 1 https://github.com/theos/theos.git "$THEOS"
fi
export THEOS

echo "==> 编译 tweak..."
TARGET=iphone:17.0:14.0 make clean 2>/dev/null || true
TARGET=iphone:17.0:14.0 make package
DYLIB=$(find . -name "*.dylib" | head -1)
if [ -z "$DYLIB" ]; then
    # 直接clang编译
    clang -target arm64-apple-ios14.0 -fobjc-arc -dynamiclib \
        -O2 -o XingxinShare.dylib hook_dylib.m \
        -lobjc -Wl,-dylib_install_name,@executable_path/XingxinShare.dylib
    DYLIB=XingxinShare.dylib
fi
echo "dylib: $DYLIB"

echo "==> 解压 IPA..."
TMPDIR=$(mktemp -d)
unzip -q "$IPA" -d "$TMPDIR"
APP_PATH=$(find "$TMPDIR" -name "*.app" -type d | head -1)

# 找到主二进制
MACHO=$(find "$APP_PATH" -maxdepth 1 -type f | head -1)

echo "==> 注入 dylib..."
cp "$DYLIB" "$APP_PATH/"
# 用insert_dylib注入
# 如果不存在则从theos获取
if ! which insert_dylib >/dev/null 2>&1; then
    # 编译insert_dylib
    git clone --depth 1 https://github.com/Tyilo/insert_dylib.git /tmp/insert_dylib
    cd /tmp/insert_dylib
    clang -O2 insert_dylib.c -o insert_dylib
    cd -
    INSERT_DYLIB=/tmp/insert_dylib/insert_dylib
else
    INSERT_DYLIB=insert_dylib
fi

"$INSERT_DYLIB" --strip-codesig --all-yes "@executable_path/XingxinShare.dylib" "$MACHO" "${MACHO}_patched"
mv "${MACHO}_patched" "$MACHO"
chmod +x "$MACHO"

echo "==> 移除签名..."
rm -rf "$APP_PATH/_CodeSignature"
rm -f "$APP_PATH/embedded.mobileprovision"

echo "==> 重新打包..."
OUTPUT="行信_带分享.ipa"
cd "$TMPDIR"
zip -qr "$OLDPWD/$OUTPUT" Payload/

echo ""
echo "========================================="
echo "✅ 完成! 输出: $OUTPUT"
echo "用 TrollStore 打开安装即可"
echo "========================================="
