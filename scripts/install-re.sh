#!/bin/bash
# dsh-go：一键安装逆向 / APK / 动态调试工具链
# 约定：下载类资产放 /root/tools（运行时升级不丢），系统包装在 /usr（升级可能被换，重跑本脚本即可）
LOG=/root/tools/install-re.log
mkdir -p /root/tools
exec > >(tee -a "$LOG") 2>&1
export DEBIAN_FRONTEND=noninteractive
echo "===== START $(date) ====="
set -x

apt-get update

# 基础编译/运行依赖
apt-get install -y --no-install-recommends \
  openjdk-17-jdk-headless unzip zip curl wget file binutils gdb \
  xxd p7zip-full python3-pip python3-venv ca-certificates \
  build-essential pkg-config cmake 2>&1 || true

# 逆向 / APK（装得上多少算多少）
apt-get install -y --no-install-recommends \
  apktool radare2 aapt apksigner zipalign binwalk 2>&1 || true

# 顺带补回常用工具（之前被运行时换掉过）
apt-get install -y --no-install-recommends git ca-certificates 2>&1 || true

# Python 工具链（pip 已配清华源）
pip3 install --no-cache-dir -U \
  lief androguard frida-tools pwntools capstone keystone-engine \
  unicorn zstandard pyaxmlparser 2>&1 || true

# jadx（Java，架构无关；GitHub 直连慢就走 ghfast.top 代理）
JADX_VER=1.5.1
if ! command -v jadx >/dev/null 2>&1; then
  for base in "https://ghfast.top/https://github.com" "https://github.com"; do
    if curl -fL --retry 2 --max-time 240 -o /root/tools/jadx.zip \
        "$base/skylot/jadx/releases/download/v${JADX_VER}/jadx-${JADX_VER}.zip"; then
      rm -rf /root/tools/jadx && mkdir -p /root/tools/jadx
      if unzip -q -o /root/tools/jadx.zip -d /root/tools/jadx; then
        ln -sf /root/tools/jadx/bin/jadx /usr/local/bin/jadx
        break
      fi
    fi
  done
  rm -f /root/tools/jadx.zip
fi

# 把 pip 的控制台脚本接到 PATH（frida / androguard / ROPgadget…）
for s in frida frida-ps frida-trace ROPgadget checksec asm disasm elfpatch androguard apkinfo apkInspector; do
  [ -e "/usr/local/bin/$s" ] || ln -sf "/opt/python/bin/$s" "/usr/local/bin/$s"
done

# apktool 兜底（apt 没装上就下 jar）
if ! command -v apktool >/dev/null 2>&1; then
  curl -fL --retry 3 -o /root/tools/apktool.jar \
    "https://github.com/iBotPeaches/Apktool/releases/download/v2.11.1/apktool_2.11.1.jar" \
  && printf '#!/bin/sh\nexec java -jar /root/tools/apktool.jar "$@"\n' > /usr/local/bin/apktool \
  && chmod +x /usr/local/bin/apktool
fi

# 报告
{
echo "===== REPORT $(date) ====="
for t in apktool jadx aapt aapt2 apksigner zipalign radare2 r2 rizin binwalk gdb java python3 pip3 frida; do
  printf "%-12s %s\n" "$t" "$(command -v $t 2>/dev/null || echo MISSING)"
done
echo "--- python pkgs ---"
python3 - <<'PY'
import importlib
for m in ["lief","androguard","frida","pwn","capstone","keystone","unicorn","zstandard","pyaxmlparser"]:
    try:
        mod=importlib.import_module(m); print(f"{m:12s} OK {getattr(mod,'__version__','')}")
    except Exception as e:
        print(f"{m:12s} FAIL {type(e).__name__}")
PY
} >> /root/tools/INSTALL-REPORT.txt 2>&1

echo "===== END $(date) ====="

# 还原 dsh-root 客户端（proot 之外的 root 执行通道）
ln -sf /root/tools/dsh-root.cjs /usr/local/bin/dsh-root 2>/dev/null || true
chmod +x /root/tools/dsh-root.cjs 2>/dev/null || true
