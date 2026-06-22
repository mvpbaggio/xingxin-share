#!/bin/bash
# 行信分享Tweak 编译脚本
# 需要 macOS + theos

set -e

echo "==> 检查 theos..."
if [ -z "$THEOS" ]; then
    if [ -d "/opt/theos" ]; then
        export THEOS=/opt/theos
    elif [ -d "$HOME/theos" ]; then
        export THEOS=$HOME/theos
    else
        echo "❌ theos 未安装"
        echo "安装: git clone --recursive https://github.com/theos/theos.git /opt/theos"
        exit 1
    fi
fi
echo "theos: $THEOS"

echo "==> 编译 tweak..."
make clean 2>/dev/null
make package

echo "✅ 完成! 找到以下文件:"
find . -name "*.deb" -o -name "*.dylib"
