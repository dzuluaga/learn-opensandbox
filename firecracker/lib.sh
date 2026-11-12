# Shared helpers for the Firecracker scripts. Sourced, not run. Runs INSIDE the Lima VM.
WORK="${FC_WORK:-$HOME/fc}"
TAP=tap0 HOST_IP=172.16.0.1 GUEST_IP=172.16.0.2 GUEST_MAC=06:00:AC:10:00:02
SOCK="$WORK/firecracker.sock"
SSH=(ssh -q -i "$WORK/id_rsa" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=1 "root@$GUEST_IP")
FC_PID=""

now() { date +%s.%N; }
ms() { echo "($2 - $1) * 1000" | bc | cut -d. -f1; }

api() {
  local body code
  body=$(curl -sS --unix-socket "$SOCK" -X "$1" "http://localhost$2" -H 'Content-Type: application/json' ${3:+-d "$3"} -w '\n%{http_code}')
  code=${body##*$'\n'}; body=${body%$'\n'*}
  if [ "${code:0:1}" != 2 ]; then echo "API $1 $2 -> HTTP $code: $body" >&2; return 1; fi
  [ -n "$body" ] && echo "$body"
  return 0
}

kvm_access() { sudo setfacl -m "u:${USER}:rw" /dev/kvm; }

net_up() {
  sudo ip link del "$TAP" 2>/dev/null || true
  sudo ip tuntap add dev "$TAP" mode tap user "$USER"
  sudo ip addr add "$HOST_IP/30" dev "$TAP"
  sudo ip link set "$TAP" up
}

# Give the microVM internet access through the Lima VM (NAT on the tap device).
nat_up() {
  local ext
  ext=$(ip route show default | awk '{print $5; exit}')
  sudo sysctl -qw net.ipv4.ip_forward=1
  sudo iptables -t nat -C POSTROUTING -s 172.16.0.0/30 -o "$ext" -j MASQUERADE 2>/dev/null \
    || sudo iptables -t nat -A POSTROUTING -s 172.16.0.0/30 -o "$ext" -j MASQUERADE
  sudo iptables -C FORWARD -i "$TAP" -o "$ext" -j ACCEPT 2>/dev/null || sudo iptables -A FORWARD -i "$TAP" -o "$ext" -j ACCEPT
  sudo iptables -C FORWARD -i "$ext" -o "$TAP" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null \
    || sudo iptables -A FORWARD -i "$ext" -o "$TAP" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
}

cleanup() {
  [ -n "$FC_PID" ] && kill "$FC_PID" 2>/dev/null || true
  sudo ip link del "$TAP" 2>/dev/null || true
}

# boot ROOTFS VCPUS MEM_MIB: cold boot from a config file.
boot() {
  cat > "$WORK/vm_config.json" <<EOF
{
  "boot-source": { "kernel_image_path": "$WORK/vmlinux", "boot_args": "keep_bootcon console=ttyS0 reboot=k panic=1" },
  "drives": [ { "drive_id": "rootfs", "path_on_host": "$1", "is_root_device": true, "is_read_only": false } ],
  "network-interfaces": [ { "iface_id": "net1", "guest_mac": "$GUEST_MAC", "host_dev_name": "$TAP" } ],
  "machine-config": { "vcpu_count": $2, "mem_size_mib": $3 }
}
EOF
  rm -f "$SOCK"
  "$WORK/firecracker" --api-sock "$SOCK" --config-file "$WORK/vm_config.json" > "$WORK/console.log" 2>&1 &
  FC_PID=$!
}

wait_ssh() {
  for _ in $(seq 1 600); do
    kill -0 "$FC_PID" 2>/dev/null || { echo "firecracker exited; see $WORK/console*.log" >&2; tail -3 "$WORK"/console*.log >&2; return 1; }
    "${SSH[@]}" true 2>/dev/null && return 0
    sleep 0.05
  done
  echo "no SSH after ~30 s" >&2; return 1
}

# Default route and DNS inside the microVM.
guest_net() {
  "${SSH[@]}" "ip route replace default via $HOST_IP; rm -f /etc/resolv.conf; printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > /etc/resolv.conf"
}

shutdown_guest() {
  "${SSH[@]}" 'sync; reboot' 2>/dev/null || true
  for _ in $(seq 1 100); do kill -0 "$FC_PID" 2>/dev/null || break; sleep 0.1; done
  kill "$FC_PID" 2>/dev/null || true
  FC_PID=""
}
