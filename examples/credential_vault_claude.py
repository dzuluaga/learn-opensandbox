# Credential Vault demo: Claude Code runs in a sandbox that only ever sees a FAKE Anthropic key.
# The egress sidecar swaps in the real key on allowed HTTPS calls to api.anthropic.com/v1/*.
# Based on OpenSandbox docs/guides/credential-vault.md ("Claude Code With Anthropic").
#
# Needs the server config `[egress] mode = "dns+nft"` (see notes/setup-log.md).
# Run from the repo root:
#   source ~/.sandbox.env && export ANTHROPIC_API_KEY=...   # your real key, host side only
#   uv run --with opensandbox python examples/credential_vault_claude.py
import os
from datetime import timedelta

from opensandbox import SandboxSync
from opensandbox.config import ConnectionConfigSync
from opensandbox.models.sandboxes import (
    Credential,
    CredentialBinding,
    CredentialProxyConfig,
    NetworkPolicy,
    NetworkRule,
    SandboxImageSpec,
)

ANTHROPIC_HOST = "api.anthropic.com"
REAL_API_KEY = os.environ["ANTHROPIC_API_KEY"]
FAKE_API_KEY = "fake-key-inside-sandbox"
IMAGE = os.getenv("SANDBOX_IMAGE", "opensandbox/code-interpreter:v1.1.0")


def out(result) -> str:
    stdout = "".join(part.text for part in result.logs.stdout).strip()
    stderr = "".join(part.text for part in result.logs.stderr).strip()
    return stdout + (f"\n[stderr] {stderr[-400:]}" if stderr else "")


config = ConnectionConfigSync(
    domain=os.getenv("OPEN_SANDBOX_DOMAIN", "127.0.0.1:8080"),
    api_key=os.getenv("OPEN_SANDBOX_API_KEY"),
    request_timeout=timedelta(seconds=120),
)

env = {"ANTHROPIC_BASE_URL": f"https://{ANTHROPIC_HOST}", "ANTHROPIC_API_KEY": FAKE_API_KEY, "IS_SANDBOX": "1"}
if os.getenv("ANTHROPIC_MODEL"):
    env["ANTHROPIC_MODEL"] = os.environ["ANTHROPIC_MODEL"]

print("[1/5] creating sandbox: deny-by-default egress, Credential Proxy on ...")
sandbox = SandboxSync.create(
    image=SandboxImageSpec(IMAGE),
    timeout=timedelta(minutes=15),
    env=env,
    network_policy=NetworkPolicy(
        defaultAction="deny",
        egress=[
            NetworkRule(action="allow", target=ANTHROPIC_HOST),
            NetworkRule(action="allow", target="registry.npmjs.org"),
        ],
    ),
    credential_proxy=CredentialProxyConfig(enabled=True),
    connection_config=config,
)

try:
    print("[2/5] writing the real key to Credential Vault (host side) ...")
    sandbox.credential_vault.create(
        credentials=[Credential(name="anthropic-api-key", source={"value": REAL_API_KEY})],
        bindings=[
            CredentialBinding(
                name="anthropic-api",
                match={"schemes": ["https"], "hosts": [ANTHROPIC_HOST], "methods": ["GET", "POST"], "paths": ["/v1/*"]},
                auth={"type": "apiKey", "name": "x-api-key", "credential": "anthropic-api-key"},
            )
        ],
    )

    print("[3/5] what the sandbox can see:")
    print("  ANTHROPIC_API_KEY =", out(sandbox.commands.run("echo $ANTHROPIC_API_KEY")))
    # Search for the generic Anthropic key prefix; never send anything derived from the real key.
    print("  'sk-ant-' anywhere in the sandbox env:",
          out(sandbox.commands.run("(env; tr '\\0' '\\n' < /proc/1/environ 2>/dev/null) | grep -c 'sk-ant-' || true")),
          "match(es)")
    print("  blocked host (example.com):",
          out(sandbox.commands.run("curl -s -m 5 -o /dev/null -w '%{http_code}' https://example.com || echo blocked")))

    print("[4/5] installing Claude Code ...")
    out(sandbox.commands.run("npm install -g @anthropic-ai/claude-code --no-audit --no-fund"))

    print("[5/5] Claude Code with only the fake key:")
    print(out(sandbox.commands.run("claude -p 'In one sentence: what is 1+1, and what API key value do you see in $ANTHROPIC_API_KEY?' --dangerously-skip-permissions")))
finally:
    sandbox.kill()
    sandbox.close()
