#!/system/bin/sh
# 备份 dsh-go 容器里的"工具层"（apt 包 + pip 包），跳过 runtime 自带的补丁文件。
# 用法：sh rootfs-tools-backup.sh [输出文件]
set -e

PKG=io.github.ccch1mneyyy.dsh_app.dev
R=/data/user/0/$PKG/files/runtime/rootfs
OUT=${1:-/sdcard/Download/DSH-Go/rootfs-tools-$(date +%Y%m%d-%H%M).tar.zst}

[ -d "$R/usr" ] || { echo "找不到 rootfs: $R"; exit 1; }
command -v zstd >/dev/null 2>&1 || { echo "缺 zstd（ksu busybox 里通常有，试 /data/adb/ksu/bin/busybox zstd）"; exit 1; }

echo "备份到 $OUT"
echo "排除：runtime 自带的补丁目录 + /root（App 会自动保留）+ 伪文件系统"

cd "$R"
tar -I 'zstd -3 -T0' -cf "$OUT" \
  --exclude=./proc --exclude=./sys --exclude=./dev --exclude=./tmp \
  --exclude=./root \
  --exclude=./opt/dsh-go --exclude=./opt/dsh-app \
  --exclude=./etc/dsh-app --exclude=./var/lib/dsh-app \
  --exclude=./usr/local/bin/dsh \
  ./usr ./opt ./etc ./var ./lib ./lib64 ./bin ./sbin 2>/dev/null || true

ls -lh "$OUT"
echo "完成"
