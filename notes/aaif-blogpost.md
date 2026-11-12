# AAIF blog post (draft outline)

Action item: write a blog post for the Agentic AI Foundation (AAIF) community about learning OpenSandbox.
Status: outline only. Check AAIF's blog submission process before writing.

## Working title
Giving AI agents a safe place to work: a first week with OpenSandbox

## Angle
A newcomer's hands-on path through an AAIF project donated by Alibaba, from `uvx` to a sandbox that never sees
the real API key. Neutral and practical: no company pitch.

## Outline
1. Why agents need sandboxes: they run code, install tools and call APIs on our behalf.
2. Hello world in minutes: local server on Docker, one Python call to create a sandbox.
3. Claude Code inside a sandbox: headless runs, session resume (state lives with the sandbox).
4. Credential Vault: the agent holds a fake key; the egress sidecar injects the real one. Recorded output in
   [credential-vault-demo-output.md](credential-vault-demo-output.md).
5. Containers vs microVMs: shared kernel vs own kernel, with Firecracker booted on a Mac via Lima
   ([firecracker.md](firecracker.md), diagram `docs/containers-vs-microvms.svg`).
6. Sandboxes are disposable, not stateless: one per session, durable state outside
   (diagram `docs/functions-vs-sandboxes.svg`).
7. Gotchas a newcomer hits (from [setup-log.md](setup-log.md)): API key at startup, `localhost` vs `127.0.0.1`,
   restarting the server, `dns+nft` for Credential Vault.
8. How to get involved: the OpenSandbox repo, OSEPs, good first issues, AAIF events.

## Links
- Repo with all examples: https://github.com/dzuluaga/learn-opensandbox
- OpenSandbox: https://github.com/alibaba/OpenSandbox
- AAIF projects: https://aaif.io/projects/
