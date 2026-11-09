#!/system/bin/sh
# 把备份的工具层还原到新 runtime 的 rootfs（升级 1.0.14 之后跑）。
# 用法：sh rootfs-tools-restore.sh /sdcard/Download/DSH-Go/rootfs-tools-xxxx.tar.zst
set -e

PKG=io.github.ccch1mneyyy.dsh_app.dev
R=/data/user/0/$PKG/files/runtime/rootfs
SRC=$1

[ -f "$SRC" ] || { echo "用法: sh $0 <备份文件.tar.zst>"; exit 1; }
[ -d "$R/usr" ] || { echo "找不到 rootfs（先启动一次新版本，让它解压运行时）: $R"; exit 1; }

UID_APP=$(stat -c %u /data/user/0/$PKG)
echo "App uid = $UID_APP"
echo "还原 $SRC → $R"

cd "$R"
# 不覆盖 runtime 自带的东西
tar -I 'zstd -d -T0' -xf "$SRC" \
  --exclude=./opt/dsh-go --exclude=./opt/dsh-app \
  --exclude=./etc/dsh-app --exclude=./var/lib/dsh-app \
  --exclude=./usr/local/bin/dsh \
  --skip-old-files 2>/dev/null || \
tar -I 'zstd -d -T0' -xf "$SRC" \
  --exclude=./opt/dsh-go --exclude=./opt/dsh-app \
  --exclude=./etc/dsh-app --exclude=./var/lib/dsh-app \
  --exclude=./usr/local/bin/dsh || true

# 归主：runtime 以 App uid 运行，属主不对会读不到
chown -R "$UID_APP:$UID_APP" "$R/usr" "$R/opt/python" 2>/dev/null || true
chmod 755 "$R/usr/local/bin" 2>/dev/null || true

# dsh-root 客户端链接
[ -f "$R/root/tools/dsh-root.cjs" ] && ln -sf /root/tools/dsh-root.cjs "$R/usr/local/bin/dsh-root" 2>/dev/null || true

# 刷新动态库缓存
if [ -x "$R/usr/sbin/ldconfig" ]; then
  chroot "$R" /usr/sbin/ldconfig 2>/dev/null || true
fi

echo "还原完成。验证："
echo "  dsh-root 'id -u'          # 应为 0"
echo "  jadx --version; apktool --version; frida --version"
