#!/usr/bin/env bash
# Boot one Firecracker microVM, time it, run a command over SSH, shut it down.
# Runs INSIDE the Lima VM after setup.sh:  limactl shell fc -- bash <repo>/firecracker/run.sh
set -euo pipefail

WORK="${FC_WORK:-$HOME/fc}"
cd "$WORK"
TAP=tap0 HOST_IP=172.16.0.1 GUEST_IP=172.16.0.2 GUEST_MAC=06:00:AC:10:00:02
SOCK="$WORK/firecracker.sock"
SSH=(ssh -q -i id_rsa -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=1 "root@$GUEST_IP")

# Host side of the microVM's network: a tap device. The CI rootfs derives its IP from the MAC.
sudo ip link del "$TAP" 2>/dev/null || true
sudo ip tuntap add dev "$TAP" mode tap user "$USER"
sudo ip addr add "$HOST_IP/30" dev "$TAP" && sudo ip link set "$TAP" up

cat > vm_config.json <<EOF
{
  "boot-source": { "kernel_image_path": "vmlinux", "boot_args": "keep_bootcon console=ttyS0 reboot=k panic=1" },
  "drives": [ { "drive_id": "rootfs", "path_on_host": "rootfs.ext4", "is_root_device": true, "is_read_only": false } ],
  "network-interfaces": [ { "iface_id": "net1", "guest_mac": "$GUEST_MAC", "host_dev_name": "$TAP" } ],
  "machine-config": { "vcpu_count": 1, "mem_size_mib": 512 }
}
EOF

rm -f "$SOCK" console.log
start=$(date +%s.%N)
./firecracker --api-sock "$SOCK" --config-file vm_config.json > console.log 2>&1 &
FC_PID=$!
trap 'kill $FC_PID 2>/dev/null || true; sudo ip link del $TAP 2>/dev/null || true' EXIT

# Wait until the guest answers SSH.
for _ in $(seq 1 100); do
  if "${SSH[@]}" true 2>/dev/null; then break; fi
  sleep 0.1
done
ready=$(date +%s.%N)
printf 'microVM ready for SSH in %.2f s (firecracker pid %s)\n' "$(echo "$ready - $start" | bc)" "$FC_PID"

echo "--- inside the microVM:"
"${SSH[@]}" 'uname -a; echo; grep PRETTY_NAME /etc/os-release; nproc; free -m | head -2'

echo "--- kernel boot milestone from the guest's console log:"
grep -m1 -E "Run /sbin/init|Freeing unused kernel" console.log || true

echo "--- host view: the whole VM is one process"
ps -o pid,rss,etime,cmd -p "$FC_PID"

"${SSH[@]}" 'reboot' || true   # reboot=k makes Firecracker exit
sleep 1
