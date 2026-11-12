# Setup log

## 2026-11-11: server aborts at startup

`uvx opensandbox-server` printed a security warning, waited 30 seconds for `YES`, then aborted:
"confirmation timed out waiting for YES" (see upstream issue #750).

Cause: `server.api_key` was empty in `~/.sandbox.toml`.

Fix: set a random key (`openssl rand -hex 24`) as `api_key` under `[server]`, and export the same value as
`OPEN_SANDBOX_API_KEY` for the SDK (`~/.sandbox.env`, mode 600). Don't type `YES` to skip auth.

## 2026-11-11: hello world fails with HTTP 404 "Cannot POST /v1/sandboxes"

That error page is Express/Bun, not OpenSandbox's FastAPI, so a different server was answering.

Cause: another dev server (`bun --watch serve.ts`) listened on `*:8080` over IPv6, while OpenSandbox listens on
`127.0.0.1:8080` (IPv4). `localhost` resolved to `::1` first and reached bun.

Diagnose: `lsof -nP -iTCP:8080 -sTCP:LISTEN`, and `curl http://127.0.0.1:8080/health` returns `{"status":"healthy"}`.

Fix: `OPEN_SANDBOX_DOMAIN=127.0.0.1:8080` instead of `localhost:8080`. (Or move one of the servers to another port.)

## 2026-11-11: upstream Claude Code example, changes I made

`examples/claude-code/main.py` upstream:
- defaults to `localhost:8080` (same IPv6 problem above),
- pulls the image from Alibaba's China registry (slow from the US; Docker Hub has `opensandbox/code-interpreter:v1.1.0`),
- runs `claude "..."` interactively first, which needs a TTY and can hang (their own docs warn about it).

`examples/claude_in_sandbox.py` here runs headless only (`claude -p --output-format json`), then `--resume`.
It passes the real API key into the sandbox env; Credential Vault is the way to avoid that.

## 2026-11-11: Claude Code inside a sandbox works

`examples/claude_in_sandbox.py` with `opensandbox/code-interpreter:v1.1.0` from Docker Hub:
- npm installed Claude Code in the sandbox (the "new major version of npm" notice on stderr is harmless).
- Headless turn: Claude ran `uname -a` and read `/etc/os-release` itself: Ubuntu 24.04.4 LTS,
  kernel `6.10.14-linuxkit`, aarch64. It figured out it was in a container on Docker Desktop on Apple silicon.
- `--resume <session_id>` answered `42`, so session state carries across turns in the same sandbox.

Takeaway: a container sandbox shares the host VM's kernel (here, Docker Desktop's LinuxKit). That's the
reason microVM sandboxes like Firecracker exist: each sandbox gets its own kernel, a stronger boundary.
