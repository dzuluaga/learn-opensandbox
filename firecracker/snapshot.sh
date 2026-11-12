#!/usr/bin/env bash
# Snapshot a running Firecracker microVM, kill it, restore it into a NEW process, and time the restore.
# Proves memory survives: a file in /dev/shm (RAM only) and a running process come back.
# Runs INSIDE the Lima VM after setup.sh:  limactl shell fcvm bash <repo>/firecracker/snapshot.sh
set -euo pipefail

WORK="${FC_WORK:-$HOME/fc}"
cd "$WORK"
TAP=tap0 HOST_IP=172.16.0.1 GUEST_IP=172.16.0.2 GUEST_MAC=06:00:AC:10:00:02
SOCK="$WORK/firecracker.sock"
SSH=(ssh -q -i id_rsa -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=1 "root@$GUEST_IP")
api() {
  local body code
  body=$(curl -sS --unix-socket "$SOCK" -X "$1" "http://localhost$2" -H 'Content-Type: application/json' ${3:+-d "$3"} -w '\n%{http_code}')
  code=${body##*$'\n'}; body=${body%$'\n'*}
  if [ "${code:0:1}" != 2 ]; then echo "API $1 $2 -> HTTP $code: $body" >&2; return 1; fi
  [ -n "$body" ] && echo "$body"
  return 0
}
now() { date +%s.%N; }
ms() { echo "($2 - $1) * 1000" | bc | cut -d. -f1; }
wait_ssh() {
  for _ in $(seq 1 600); do
    kill -0 "$FC_PID" 2>/dev/null || { echo "firecracker exited; see $WORK/console*.log" >&2; tail -3 "$WORK"/console*.log >&2; return 1; }
    "${SSH[@]}" true 2>/dev/null && return 0
    sleep 0.05
  done
  echo "no SSH after ~30 s" >&2; return 1
}

# The /dev/kvm ACL from setup.sh can reset (device reset, VM restart): grant it every run.
sudo setfacl -m "u:${USER}:rw" /dev/kvm

sudo ip link del "$TAP" 2>/dev/null || true
sudo ip tuntap add dev "$TAP" mode tap user "$USER"
sudo ip addr add "$HOST_IP/30" dev "$TAP" && sudo ip link set "$TAP" up
cleanup() { [ -n "${FC_PID:-}" ] && kill "$FC_PID" 2>/dev/null || true; sudo ip link del "$TAP" 2>/dev/null || true; }
trap cleanup EXIT

cat > vm_config.json <<EOF
{
  "boot-source": { "kernel_image_path": "vmlinux", "boot_args": "keep_bootcon console=ttyS0 reboot=k panic=1" },
  "drives": [ { "drive_id": "rootfs", "path_on_host": "rootfs.ext4", "is_root_device": true, "is_read_only": false } ],
  "network-interfaces": [ { "iface_id": "net1", "guest_mac": "$GUEST_MAC", "host_dev_name": "$TAP" } ],
  "machine-config": { "vcpu_count": 1, "mem_size_mib": 512 }
}
EOF

echo "== 1. cold boot"
rm -f "$SOCK"; t0=$(now)
./firecracker --api-sock "$SOCK" --config-file vm_config.json > console.log 2>&1 &
FC_PID=$!
wait_ssh; echo "cold boot to SSH: $(ms "$t0" "$(now)") ms (pid $FC_PID)"

echo "== 2. leave state that lives only in memory"
"${SSH[@]}" 'echo "written at $(date +%T) before the snapshot" > /dev/shm/marker; nohup sleep 100000 >/dev/null 2>&1 & echo "sleep pid $!"; cat /proc/uptime'

echo "== 3. pause, snapshot, kill the process"
api PATCH /vm '{"state":"Paused"}'
t0=$(now)
api PUT /snapshot/create '{"snapshot_type":"Full","snapshot_path":"vm.snap","mem_file_path":"vm.mem"}'
echo "snapshot written in $(ms "$t0" "$(now)") ms"
ls -lh vm.snap vm.mem | awk '{print "  " $5 "  " $9}'
kill "$FC_PID"; wait "$FC_PID" 2>/dev/null || true; FC_PID=""
echo "original firecracker process killed"

echo "== 4. restore into a NEW process"
sudo setfacl -m "u:${USER}:rw" /dev/kvm   # the ACL can drop between runs; kvm group membership (setup.sh) is the durable fix
rm -f "$SOCK"; t0=$(now)
./firecracker --api-sock "$SOCK" > console-restore.log 2>&1 &
FC_PID=$!
for _ in $(seq 1 100); do [ -S "$SOCK" ] && break; sleep 0.01; done
api PUT /snapshot/load '{"snapshot_path":"vm.snap","mem_backend":{"backend_type":"File","backend_path":"vm.mem"},"resume_vm":true}'
t1=$(now)
wait_ssh; t2=$(now)
echo "snapshot load + resume: $(ms "$t0" "$t1") ms; reachable over SSH: $(ms "$t0" "$t2") ms (new pid $FC_PID)"

echo "== 5. is the memory state still there?"
"${SSH[@]}" 'cat /dev/shm/marker; pgrep -a sleep; cat /proc/uptime'

"${SSH[@]}" 'reboot' 2>/dev/null || true
sleep 1
