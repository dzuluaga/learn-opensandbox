# Learning OpenSandbox

My notes and runnable examples from learning [OpenSandbox](https://github.com/alibaba/OpenSandbox), the sandbox
runtime for AI agents that Alibaba donated to the Agentic AI Foundation (AAIF). Started Nov 2026 while preparing
the CAST-SD × CES keynote (UC San Diego, Nov 21, 2026).

Learned against upstream `e10bebdd3` (2026-11-12) with `opensandbox-server` from `uvx` on macOS (Apple silicon) and
Docker Desktop.

## Contents

| Path | What it is |
| --- | --- |
| [notes/learning-path.md](notes/learning-path.md) | Architecture tour, what's interesting, the hands-on order |
| [notes/setup-log.md](notes/setup-log.md) | Problems I hit and how I fixed them |
| [examples/hello_sandbox.py](examples/hello_sandbox.py) | Create an alpine sandbox, run a command, write and run a script |
| [examples/claude_in_sandbox.py](examples/claude_in_sandbox.py) | Claude Code running headless inside a sandbox, with session resume |
| [sandbox.env.example](sandbox.env.example) | SDK connection settings (copy to `~/.sandbox.env`) |

## Progress

- [x] Server running locally on Docker, with an API key
- [x] Hello world
- [ ] Claude Code inside a sandbox
- [ ] Credential Vault: agent gets a fake key, egress sidecar injects the real one
- [ ] Try Firecracker (Fast Sandbox) if it's quick, to understand how microVM sandboxes work. See
      [notes/learning-path.md](notes/learning-path.md#firecracker) for what it needs.
- [ ] Read OSEP-0012 (Credential Vault) and OSEP-0014 (multi-tenancy)
- [ ] First contribution (starter bug #2660, then identity threads #2621 / #2627)

## Quick start

```bash
uvx opensandbox-server init-config ~/.sandbox.toml --example docker
# set server.api_key in ~/.sandbox.toml, and put the same key in ~/.sandbox.env (see sandbox.env.example)
uvx opensandbox-server

# second terminal
source ~/.sandbox.env
uv run --with opensandbox python examples/hello_sandbox.py
```
