#!/usr/bin/env bash
# 构建 arm64 APK：复用官方 release APK 里自带的 runtime，跳过 runtime/build-runtime.sh。
#
#   ./scripts/build.sh                    # 用 work/ 源码 + v1.0.13 runtime
#   OUT=work UPSTREAM=v1.0.13 ./scripts/build.sh
#   KEYSTORE=/path/app.jks KEYSTORE_PASSWORD=x KEY_PASSWORD=y KEY_ALIAS=dsh ./scripts/build.sh
#
# 依赖：Flutter 3.47.7、JDK 17、Android SDK 34-36、unzip、curl。
set -euo pipefail

OUT="${OUT:-work}"
UPSTREAM="${UPSTREAM:-v1.0.13}"
ABI="${ABI:-arm64}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

[ -d "$OUT/app" ] || { echo "找不到 $OUT/app，先跑 scripts/apply.sh"; exit 1; }
cd "$OUT"

# ---- 1. 官方 runtime ----
OFFICIAL_APK="/tmp/dsh-go-official-${UPSTREAM}.apk"
if [ ! -f "$OFFICIAL_APK" ]; then
  echo "==> 下载官方 $UPSTREAM APK（提供 runtime 资产）"
  URL="https://github.com/ccch1mneyyy/dsh-Go/releases/download/${UPSTREAM}/dsh-go-${UPSTREAM#v}-${ABI}.apk"
  # GitHub 直连慢时走镜像
  curl -fL --retry 3 --max-time 900 -o "$OFFICIAL_APK" "$URL" \
    || curl -fL --retry 3 --max-time 900 -o "$OFFICIAL_APK" "https://ghfast.top/$URL"
fi

RT="runtime/out/${ABI}"
mkdir -p "$RT/assets" "$RT/jniLibs/${ABI}"
if [ ! -d "$RT/assets/runtime" ] || [ -z "$(ls -A "$RT/jniLibs/${ABI}" 2>/dev/null)" ]; then
  echo "==> 从官方 APK 提取 runtime"
  TMP="$(mktemp -d)"
  ( cd "$TMP" && unzip -q "$OFFICIAL_APK" )
  mkdir -p "$RT/assets/runtime"
  cp -a "$TMP/assets/runtime/." "$RT/assets/runtime/"
  for so in "$TMP/lib/${ABI}"/libproot*.so; do
    [ -e "$so" ] && cp -a "$so" "$RT/jniLibs/${ABI}/"
  done
  rm -rf "$TMP"
fi

# ---- 2. 签名配置 ----
if [ -n "${KEYSTORE:-}" ]; then
  echo "==> 写入 key.properties"
  cat > app/android/key.properties <<EOF
storeFile=$KEYSTORE
storePassword=${KEYSTORE_PASSWORD:-}
keyPassword=${KEY_PASSWORD:-}
keyAlias=${KEY_ALIAS:-dsh}
EOF
fi

# ---- 3. 本地化 + 构建 ----
echo "==> flutter pub get"
( cd app && flutter pub get )

echo "==> 生成本地化"
python3 app/tool/l10n_merge.py || echo "（l10n_merge 失败，沿用仓库内已生成的文件）"

echo "==> 构建 $ABI"
tooling/build-apk.sh --release -f "$ABI"

echo
echo "产物："
find app/build -name "*release*.apk" -newermt '-2 hours' 2>/dev/null | while read -r f; do
  printf "  %s  (%s)\n" "$f" "$(du -h "$f" | cut -f1)"
done
