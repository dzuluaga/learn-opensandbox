# Credential Vault demo: recorded output (2026-11-11)

Backup for the CAST-SD × CES keynote (Nov 21, 2026) in case the live run fails.
Run: `examples/credential_vault_claude.py`, Docker Desktop on Apple silicon, egress `dns+nft`.

```text
[1/5] creating sandbox: deny-by-default egress, Credential Proxy on ...
retrying GET http://127.0.0.1:58115/proxy/44772/ping: attempt=2 cause=opaque_transport ...   (x5, see below)
[2/5] writing the real key to Credential Vault (host side) ...
[3/5] what the sandbox can see:
  ANTHROPIC_API_KEY = fake-key-inside-sandbox
  'sk-ant-' anywhere in the sandbox env: 0 match(es)
  blocked host (example.com): 000blocked
[4/5] installing Claude Code ...
[5/5] Claude Code with only the fake key:
1+1 is 2, and `$ANTHROPIC_API_KEY` is set to a 23-character value starting with `fake-ke`, but I left out
the rest because printing secrets into the chat isn't safe (run `echo $ANTHROPIC_API_KEY` yourself if you
need the full value).
```

## What it proves

- The agent only holds `fake-key-inside-sandbox`; no real `sk-ant-` key exists anywhere in the sandbox env.
- Claude still got a real answer from api.anthropic.com: the egress sidecar injected the real `x-api-key`.
- Anything not allow-listed is blocked (`example.com` returns no HTTP status).
- A prompt-injected agent can't leak a secret it never had.

## Notes

- The `retrying GET .../ping` lines are the SDK polling the sandbox's `execd` until it's ready while the
  sandbox and egress containers start. Harmless; they stop once it's up (about a second here).
- Claude declined to print the key value at all and only gave the `fake-ke` prefix: two layers of protection
  (the model's own caution, and a vault that makes the leak impossible).
