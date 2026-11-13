#!/usr/bin/env bash
# 把补丁集应用到指定 upstream 版本，产出可构建的源码树。
#
#   ./scripts/apply.sh                 # 默认 v1.0.15，输出到 work/
#   UPSTREAM=v1.0.14 ./scripts/apply.sh
#   OUT=/tmp/build ./scripts/apply.sh
#
# 依赖：git、bash。首次会浅克隆上游（约 5MB，--filter=blob:none）。
set -euo pipefail

UPSTREAM="${UPSTREAM:-v1.0.15}"
OUT="${OUT:-work}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATCHES="$ROOT/patches"

command -v git >/dev/null || { echo "需要 git"; exit 1; }
[ -d "$PATCHES" ] || { echo "找不到 $PATCHES"; exit 1; }

if [ -e "$OUT" ]; then
  echo "目录 $OUT 已存在。删除后重试，或换 OUT= 路径。"
  exit 1
fi

echo "==> 克隆 upstream $UPSTREAM"
git clone --depth 1 --branch "$UPSTREAM" \
  https://github.com/ccch1mneyyy/dsh-Go.git "$OUT"

cd "$OUT"
git config user.email "patch@local"
git config user.name "dsh-go-root patches"

echo "==> 应用补丁（$(ls "$PATCHES"/*.patch | wc -l) 个）"
git am --keep-cr "$PATCHES"/*.patch

echo
echo "完成：$OUT"
echo "下一步："
echo "  OUT=$OUT ./scripts/build.sh          # 复用官方 runtime 构建"
echo
echo "若上游改动了 DshProcess.kt / RuntimeController.kt / PhoneBridge.kt，"
echo "git am 会在这里停下。解决冲突后："
echo "  git add -A && git am --continue"
