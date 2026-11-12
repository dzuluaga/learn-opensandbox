#!/usr/bin/env bash
# Claude Code in a Firecracker microVM, restored from an "agent-ready" snapshot.
#   1. cold boot rootfs-claude.ext4 (from claude-setup.sh) and warm Claude Code up
#   2. snapshot that running VM, kill it          (no API key in the VM yet)
#   3. restore into a NEW process, time it
#   4. run `claude -p` in the restored VM
# The API key comes on stdin, goes to the guest over SSH stdin, and lives only in that one process's
# environment: never on a disk, never in the snapshot, never on a command line. Run from the Mac:
#   printf '%s' "$ANTHROPIC_API_KEY" | limactl shell fcvm bash <repo>/firecracker/claude-run.sh
# With no key on stdin it stops after `claude --version` in the restored VM.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$WORK"
ROOTFS="$WORK/rootfs-claude.ext4"
[ -f "$ROOTFS" ] || { echo "run claude-setup.sh first" >&2; exit 1; }

KEY=""
[ -t 0 ] || IFS= read -r KEY || true

kvm_access
trap cleanup EXIT
net_up
nat_up

echo "== 1. cold boot the agent-ready VM"
t0=$(now); boot "$ROOTFS" 2 2048; wait_ssh
echo "cold boot to SSH: $(ms "$t0" "$(now)") ms"
guest_net
"${SSH[@]}" 'claude --version >/dev/null && echo "Claude Code warmed up: $(claude --version)"'

echo "== 2. snapshot the running VM, kill it"
api PATCH /vm '{"state":"Paused"}'
t0=$(now)
api PUT /snapshot/create '{"snapshot_type":"Full","snapshot_path":"agent.snap","mem_file_path":"agent.mem"}'
echo "snapshot written in $(ms "$t0" "$(now)") ms ($(du -h agent.mem | cut -f1) of memory)"
kill "$FC_PID"; wait "$FC_PID" 2>/dev/null || true; FC_PID=""

echo "== 3. restore into a NEW process"
kvm_access
rm -f "$SOCK"; t0=$(now)
"$WORK/firecracker" --api-sock "$SOCK" > "$WORK/console-restore.log" 2>&1 &
FC_PID=$!
for _ in $(seq 1 100); do [ -S "$SOCK" ] && break; sleep 0.01; done
api PUT /snapshot/load '{"snapshot_path":"agent.snap","mem_backend":{"backend_type":"File","backend_path":"agent.mem"},"resume_vm":true}'
t1=$(now); wait_ssh; t2=$(now)
echo "snapshot load + resume: $(ms "$t0" "$t1") ms; SSH: $(ms "$t0" "$t2") ms (new pid $FC_PID)"

echo "== 4. Claude Code in the restored microVM"
if [ -z "$KEY" ]; then
  "${SSH[@]}" 'claude --version'
  echo "(no API key on stdin: skipped the claude -p call)"
else
  t0=$(now)
  printf '%s\n' "$KEY" | "${SSH[@]}" 'IFS= read -r K; export ANTHROPIC_API_KEY="$K" IS_SANDBOX=1; unset K
    claude -p "In two short sentences: what kernel and OS are you running on (use a shell command), and are you in a VM or a container?" --dangerously-skip-permissions'
  echo "claude -p answered in $(ms "$t0" "$(now)") ms"
fi
KEY=""

shutdown_guest
rm -f agent.snap agent.mem
