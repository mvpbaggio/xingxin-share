# 行信+ 分享导出附件 Tweak

为行信+ (Bank of China 企业微信) 添加系统分享/导出附件功能。

## 原理

在文件预览页面导航栏添加"分享"按钮，点击后弹出 iOS 系统分享菜单（UIActivityViewController），支持保存到文件、AirDrop、发送到微信等。

## 前置条件

- iPhone 已安装 TrollStore
- Mac 电脑 或 GitHub Actions

## 编译（Mac）

```bash
# 安装 theos
git clone --recursive https://github.com/theos/theos.git /opt/theos

# 编译 tweak
cd xingxin-tweak
THEOS=/opt/theos ./build.sh

# 注入 IPA
# 先把行信脱壳的 IPA 放到当前目录
./inject.sh 行信.ipa
```

## 编译（GitHub Actions）

1. 把脱壳的 IPA 放到 `ipa/` 目录并推送到仓库
2. 在 GitHub Actions 手动触发 `Build Injected IPA`
3. 下载产出的 `XingxinWithShare.ipa`
4. 用 TrollStore 安装

## 安装

用 TrollStore 打开 `XingxinWithShare.ipa` 安装即可。

## 使用

打开行信 → 打开任意文件附件 → 导航栏左侧会出现**分享按钮 (□↑)** → 点击后用系统分享导出。
