# Learning OpenSandbox (AAIF, donated by Alibaba)

Upstream clone: `~/tools/git/ucsd-keynote-aaif-tools/OpenSandbox`. Read 2026-11-12.

## The idea in one line
Agents need somewhere safe to run code, browse and edit files. OpenSandbox gives each agent an isolated
sandbox (Docker locally, Kubernetes or Firecracker microVMs at scale) behind one API.

## How it fits together
- **Client**: SDKs (Python, JS/TS, Java/Kotlin, Go, C#), the `osb` CLI, and an MCP server
  (`sdks/mcp/sandbox/python`) so Claude Code or Cursor can drive sandboxes.
- **Contracts**: OpenAPI specs in `specs/` are the source of truth.
- **Control plane**: FastAPI server in `server/` (create, pause, resume, delete, snapshots).
- **Data plane**: `execd` (Go) inside each sandbox runs commands, files, PTY, Jupyter.
  Clients talk to it directly, not through the server.
- **Network/security**: ingress gateway in, egress sidecar out (DNS + nftables policy), plus Credential Vault.
- **Design process**: OSEPs in `oseps/` (26 so far), like KEPs in Kubernetes.

## Coolest parts for the keynote
- **Credential Vault** (`docs/guides/credential-vault.md`, OSEP-0012/0023/0025): the agent only gets a
  fake API key. The egress sidecar swaps in the real one on allowed HTTPS calls. Prompt injection
  can't steal a secret the agent never had.
- **Fast Sandbox**: Firecracker microVMs, 64 ms P50 to create, pause/resume with memory kept.
- **RL/eval at scale**: resource pools and batch creation for agent training and evaluation.

## Hands-on (in order)
1. Start Docker Desktop.
2. Server:
   ```bash
   uvx opensandbox-server init-config ~/.sandbox.toml --example docker
   uvx opensandbox-server
   ```
3. Hello world: `uv pip install opensandbox`, then run the README's Python example
   (create an alpine sandbox, run a command, write and run a script, destroy).
4. Run Claude Code inside a sandbox: `docs/examples/claude-code.md`.
5. Credential Vault: needs `[egress].mode = "dns+nft"` and a deny-by-default outbound policy. Give the agent a
   fake key and watch the call succeed. This is the demo.

## Firecracker

To try if it's quick, to understand how microVM sandboxes work (Fast Sandbox: 64 ms P50 create, pause/resume
with memory kept).

- Firecracker needs Linux with KVM (`/dev/kvm`). macOS has no KVM, so it doesn't run directly on this Mac.
- Quick options to check:
  - A Linux VM with nested virtualization (Lima, `nestedVirtualization: true`; Apple M3 or newer and macOS 15+).
    This Mac (M4 Pro, macOS 26.6) qualifies, so this is the likely quick path.
  - A cloud VM that exposes KVM (bare metal, or an instance type with nested virtualization).
- Smallest experiment: Firecracker's own getting-started (boot one microVM from a kernel + rootfs), before
  OpenSandbox's Fast Sandbox, which runs on Kubernetes. Read `docs/architecture/fast-sandbox/index.md`
  and `oseps/0007-fast-sandbox-runtime-support.md` first.
- If none of these takes under an hour, skip it and just read the docs.

## Read next
- `docs/architecture/index.md`, then `docs/architecture/network/egress.md`
- `oseps/0012-credential-vault.md`, `oseps/0014-multi-tenancy.md`
- Open identity threads: #2621 (sandbox identity token + JWKS), #2627 (principal identity / ownership)

## Contributing (later)
- DCO sign-off required (`git commit -s`).
- Big changes: issue first or an OSEP.
- Starter bug: #2660 (uploads default to 0755 instead of 0644).
