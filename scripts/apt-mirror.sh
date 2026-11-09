#!/bin/bash
# 把 apt 源切成国内镜像（新 runtime 会重置回 ports.ubuntu.com，重装工具前先跑这个）
set -e
cat > /etc/apt/sources.list.d/ubuntu.sources <<'EOF'
Types: deb
URIs: https://mirrors.ustc.edu.cn/ubuntu-ports/
Suites: noble noble-updates noble-backports noble-security
Components: main universe restricted multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
mkdir -p /usr/share/man/man1 /usr/share/man/man8
echo "apt mirror -> USTC (ubuntu-ports)"
