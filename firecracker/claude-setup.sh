#!/usr/bin/env bash
# Build an "agent-ready" root disk: a 4 GB copy of rootfs.ext4 with Node.js 22 and Claude Code installed.
# No API key needed. Runs INSIDE the Lima VM after setup.sh:
#   limactl shell fcvm bash <repo>/firecracker/claude-setup.sh
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$WORK"
ROOTFS="$WORK/rootfs-claude.ext4"

sudo apt-get install -y -qq iptables e2fsprogs >/dev/null
kvm_access

if [ ! -f "$ROOTFS" ]; then
  echo "== copying rootfs.ext4 to a 4 GB rootfs-claude.ext4"
  cp --sparse=always rootfs.ext4 "$ROOTFS"
  truncate -s 4G "$ROOTFS"
  e2fsck -fy "$ROOTFS" >/dev/null || true
  resize2fs -p "$ROOTFS" >/dev/null
fi

trap cleanup EXIT
net_up
nat_up

echo "== booting (2 vCPU, 2 GiB) to install"
boot "$ROOTFS" 2 2048
wait_ssh
guest_net
"${SSH[@]}" 'curl -fsS -o /dev/null -w "internet from the microVM: HTTP %{http_code}\n" https://registry.npmjs.org/'

echo "== installing Node.js 22 (official linux-arm64 build)"
"${SSH[@]}" 'set -e
  command -v node >/dev/null && node --version | grep -q "^v22" && { echo "node already $(node --version)"; exit 0; }
  base=https://nodejs.org/dist/latest-v22.x
  file=$(curl -fsSL "$base/SHASUMS256.txt" | grep -o "node-v22[0-9.]*-linux-arm64.tar.gz" | head -1)
  curl -fsSL -o "/tmp/$file" "$base/$file"
  curl -fsSL "$base/SHASUMS256.txt" | grep " $file\$" | (cd /tmp && sha256sum -c -)
  tar -xzf "/tmp/$file" -C /usr/local --strip-components=1   # .tar.gz: the CI rootfs has no xz
  rm -f "/tmp/$file"
  echo "node $(node --version), npm $(npm --version)"'

echo "== installing Claude Code"
"${SSH[@]}" 'npm install -g @anthropic-ai/claude-code --no-audit --no-fund --loglevel=error >/dev/null && claude --version'

"${SSH[@]}" 'echo "root disk: $(df -h / | tail -1 | awk "{print \$3\" used of \"\$2}")"'
echo "== shutting down; the install is saved in $ROOTFS"
shutdown_guest
