#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

echo "=== 1. 编译并打包 T1.app ==="
./package.sh

DMG_NAME="T1-v1.0.0.dmg"
STAGING="build_dmg_tmp"

echo "=== 2. 准备 DMG 镜像内容 ==="
rm -rf "$STAGING" "$DMG_NAME"
mkdir -p "$STAGING"

cp -R "T1.app" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

cat << 'EOF' > "$STAGING/安装指南与说明.txt"
========================================
       T1 遥控器与飞鼠增强工具 v1.0.0
========================================

【安装步骤】：
1. 将「T1.app」直接拖入「Applications」文件夹。
2. 在「应用程序」中双击启动 T1。
3. 首次启动时，macOS 会提示需要辅助功能权限：
   请打开「系统设置 → 隐私与安全性 → 辅助功能」，勾选 T1 即可。

【如果提示“无法打开，因为无法验证开发者”】：
请打开终端 (Terminal.app)，复制并执行以下命令回车即可：
xattr -cr /Applications/T1.app

【核心功能】：
- 绳子拖拽消抖物理引擎：彻底消灭飞鼠漂浮与残余滑行；
- 硬件光标坐标固化：彻底消除光标变形瞬移问题；
- 遥控器正反 59 键全量高保真映射与双击/长按手势识别；
- 侧边独立双音量键与系统多媒体键底层打通；
- 原生触控板与键盘 100% 直通零干扰。
========================================
EOF

echo "=== 3. 生成 DMG 安装镜像 ==="
hdiutil create -volname "T1" -srcfolder "$STAGING" -ov -format UDZO "$DMG_NAME"
rm -rf "$STAGING"

echo "=== 发布包生成完成: $DMG_NAME ==="
ls -lh "$DMG_NAME"
