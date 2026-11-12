#!/usr/bin/env bash
# Download Firecracker + a CI kernel and Ubuntu rootfs, following Firecracker's getting-started guide.
# Runs INSIDE the Lima VM (needs /dev/kvm):  limactl shell fc -- bash <repo>/firecracker/setup.sh
set -euo pipefail

WORK="${FC_WORK:-$HOME/fc}"
mkdir -p "$WORK" && cd "$WORK"
ARCH="$(uname -m)"

sudo apt-get update -qq && sudo apt-get install -y -qq squashfs-tools acl curl wget bc >/dev/null

# Let this user open /dev/kvm.
sudo setfacl -m "u:${USER}:rw" /dev/kvm

# Firecracker release binary.
release_url="https://github.com/firecracker-microvm/firecracker/releases"
latest=$(basename "$(curl -fsSLI -o /dev/null -w '%{url_effective}' "$release_url/latest")")
if [ ! -x firecracker ]; then
  curl -fsSL "$release_url/download/$latest/firecracker-$latest-$ARCH.tgz" | tar -xz
  mv "release-$latest-$ARCH/firecracker-$latest-$ARCH" firecracker
fi
echo "firecracker: $(./firecracker --version | head -1)"

# CI kernel and Ubuntu rootfs. The CI bucket can lag the release (v1.18 had none on 2026-11-11),
# so use the newest release line that has artifacts for this arch.
list="http://spec.ccfc.min.s3.amazonaws.com/?list-type=2"
kernel_key="" ubuntu_key=""
for ci in $(curl -fsSL "$list&prefix=firecracker-ci/&delimiter=/" | grep -oP "(?<=<Prefix>firecracker-ci/)v1\.[0-9]+(?=/</Prefix>)" | sort -V | tac); do
  kernel_key=$(curl -fsSL "$list&prefix=firecracker-ci/$ci/$ARCH/vmlinux-" | grep -oP "(?<=<Key>)(firecracker-ci/$ci/$ARCH/vmlinux-[0-9]+\.[0-9]+\.[0-9]{1,3})(?=</Key>)" | sort -V | tail -1 || true)
  ubuntu_key=$(curl -fsSL "$list&prefix=firecracker-ci/$ci/$ARCH/ubuntu-" | grep -oP "(?<=<Key>)(firecracker-ci/$ci/$ARCH/ubuntu-[0-9]+\.[0-9]+\.squashfs)(?=</Key>)" | sort -V | tail -1 || true)
  [ -n "$kernel_key" ] && [ -n "$ubuntu_key" ] && break
done
echo "CI artifacts from: $ci"
[ -f vmlinux ] || wget -q -O vmlinux "https://s3.amazonaws.com/spec.ccfc.min/$kernel_key"
echo "kernel: $(basename "$kernel_key")"

if [ ! -f rootfs.ext4 ]; then
  wget -q -O rootfs.squashfs "https://s3.amazonaws.com/spec.ccfc.min/$ubuntu_key"
  sudo rm -rf squashfs-root && sudo unsquashfs -q rootfs.squashfs >/dev/null
  [ -f id_rsa ] || ssh-keygen -q -f id_rsa -N ""
  sudo mkdir -p squashfs-root/root/.ssh && sudo cp id_rsa.pub squashfs-root/root/.ssh/authorized_keys
  sudo chown -R root:root squashfs-root
  truncate -s 1G rootfs.ext4 && sudo mkfs.ext4 -q -d squashfs-root -F rootfs.ext4
  sudo rm -rf squashfs-root rootfs.squashfs
fi
echo "rootfs: $(basename "$ubuntu_key" .squashfs) -> rootfs.ext4"
ls -lh "$WORK"
