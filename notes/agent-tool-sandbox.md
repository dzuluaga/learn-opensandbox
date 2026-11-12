# Where an agent's tools run (2026-11-12)

You don't change how you call the model. You change where its hands are.

The LLM call stays a normal Anthropic SDK call in your app. Only the commands Claude asks to run (tool calls)
go to a sandbox, by swapping `subprocess.run(cmd)` for `sandbox.commands.run(cmd)` in the tool handler.
Examples: [agent_tool_in_sandbox.py](../examples/agent_tool_in_sandbox.py) (one shot) and
[chat_with_sandbox.py](../examples/chat_with_sandbox.py) (interactive, lazy sandbox).

```text
 Anthropic API (cloud)
 ┌────────────────────┐
 │  Claude (model)    │
 └─────────▲──────────┘
           │ 1. messages.create()  ──►  text reply        (no sandbox)
           │                       ──►  tool_use: bash    (needs sandbox)
           │
 Your Mac  │
 ┌─────────┴──────────────────────────────────────────────────────────┐
 │                                                                    │
 │  chat_with_sandbox.py  (your app, holds ANTHROPIC_API_KEY)         │
 │  ┌──────────────────────────────────────────────┐                  │
 │  │ get_sandbox():  first tool call? create one  │                  │
 │  │ run_bash(cmd):  sandbox.commands.run(cmd)    │                  │
 │  └───────┬──────────────────────────────┬───────┘                  │
 │          │ 2. POST /sandboxes           │ 4. POST /command "cmd"   │
 │          │    (once per chat)           │    (every tool call)     │
 │          ▼                              │                          │
 │  OpenSandbox server  (uvx, :8080)       │                          │
 │  ┌──────────────────────────┐           │                          │
 │  │ lifecycle API            │           │                          │
 │  │ runtime: Docker          │           │                          │
 │  │   (or Firecracker with   │           │                          │
 │  │    Fast Sandbox)         │           │                          │
 │  └───────┬──────────────────┘           │                          │
 │          │ 3. start container           │                          │
 │          ▼                              ▼                          │
 │  ┌─────────────────────────────────────────────────────┐           │
 │  │ SANDBOX  (container here; microVM with Fast Sandbox)│           │
 │  │                                                     │           │
 │  │   execd  ──►  runs cmd: python3 ..., pip, curl      │           │
 │  │               files:   /tmp/notes.txt (persists     │           │
 │  │                        for the whole chat)          │           │
 │  │   egress policy: deny all, allow pypi.org           │           │
 │  │   no API key inside                                 │           │
 │  └──────────────────────────┬──────────────────────────┘           │
 │                             │ 5. stdout / stderr / exit code       │
 │                             └──────► back to run_bash()            │
 │                                       └──► 6. tool_result to Claude│
 └────────────────────────────────────────────────────────────────────┘

 Text-only turn:  1 → reply.                       Sandbox never created.
 First tool call: 1 → 2 → 3 → 4 → 5 → 6 → loop.    Sandbox created.
 Later tool call: 1 → 4 → 5 → 6 → loop.            Same sandbox reused.
 /quit:           DELETE /sandboxes/{id}           Sandbox killed.
```

## The same flow on Firecracker (Fast Sandbox)

Same app code; only the server's runtime changes. Timings are from this repo's hand-built runs
([firecracker.md](firecracker.md)), not from OpenSandbox's Fast Sandbox.

```text
 Anthropic API (cloud)
 ┌────────────────────┐
 │  Claude (model)    │
 └─────────▲──────────┘
           │ 1. messages.create()  ──►  text reply  or  tool_use: bash
           │
 Linux host with KVM: bare metal in production, Lima VM "fcvm" on a Mac
 ┌─────────┴──────────────────────────────────────────────────────────┐
 │                                                                    │
 │  chat_with_sandbox.py   (your app: same code as on Docker)         │
 │        │ 2. POST /sandboxes            │ 4. POST /command "cmd"    │
 │        │    (first tool call)          │    (every tool call)      │
 │        ▼                               │                           │
 │  OpenSandbox server                    │                           │
 │  runtime: Fast Sandbox                 │                           │
 │        │ 3. restore a warm microVM     │                           │
 │        │    from a snapshot: ~6-25 ms  │                           │
 │        │    (cold boot here: 10-35 s)  │                           │
 │        ▼                               │                           │
 │  firecracker process   one per sandbox, ~100 MB, opens /dev/kvm    │
 │   ┌───────────────────────────────────┼────────────────────────┐   │
 │   │ MICROVM: its own guest kernel     ▼                        │   │
 │   │   execd ──► runs cmd: python3 ..., pip, curl               │   │
 │   │   own disk image (rootfs.ext4): files persist              │   │
 │   │   own RAM: restored exactly from the snapshot              │   │
 │   │   virtio net ──► tap0 on the host                          │   │
 │   │   no API key inside                                        │   │
 │   └───────────────────────┬────────────────────────────────────┘   │
 │                           │ 5. stdout / stderr / exit code         │
 │                           └──► back to run_bash() ──► 6. to Claude │
 │                                                                    │
 │  Network rules can sit on the HOST side of tap0 (as in this repo's │
 │  hand-built setup), outside the guest kernel: the guest can't undo │
 │  them.                                                             │
 └────────────────────────────────────────────────────────────────────┘

 vs Docker: no shared kernel. The boundary is KVM hardware virtualization,
 not Linux namespaces; a guest-kernel exploit stays inside the microVM.
```

## Key points

- **No migration of LLM code.** Your own calls (the model, Stripe, your database) stay normal library calls.
  What moves into the sandbox is code you didn't write: model-generated commands, possibly prompt-injected.
- **Three things, three places.** Your app runs on the host and calls Claude. The OpenSandbox server (also on
  the host) creates the sandbox through a runtime (Docker here, Firecracker with Fast Sandbox). Claude's
  commands, including any Python it writes, run inside the sandbox, received by `execd`.
- **The model decides per turn.** Text-only turns never touch a sandbox; only `tool_use` blocks do.
- **When to create the sandbox is the app's choice**, not OpenSandbox's: lazily on the first tool call
  (`get_sandbox()`), at chat start, or from a warm pool. OpenSandbox makes creation cheap enough (fast creates,
  pause/resume, pools) that lazy creation is practical.
- **One sandbox per conversation**, so files and installed packages persist across turns; pause it when idle,
  resume on the next tool call (OSEP-0024 auto-pause and wake).
- **Same script, other runtime.** Pointing the server at Fast Sandbox would run the same code in Firecracker
  microVMs, with no script change. `uname -r` tells you which: `6.10.14-linuxkit` (Docker Desktop) vs the
  guest kernel (for example `6.1.155`).
- **Second pattern: the whole agent in the sandbox** (Claude Code demos). Then the agent's own LLM call starts
  inside, and Credential Vault keeps the real key outside.
