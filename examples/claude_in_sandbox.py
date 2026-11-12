# Run Claude Code headless inside an OpenSandbox sandbox.
# Adapted from OpenSandbox/examples/claude-code/main.py: headless only (the interactive
# `claude "..."` step needs a TTY and can hang), Docker Hub image, SDK env from ~/.sandbox.env.
#
# Run:
#   source ~/.sandbox.env && export ANTHROPIC_API_KEY=...   # your key, set in your own shell
#   uv run --with opensandbox python examples/claude_in_sandbox.py
#
# Note for the keynote: this passes the real key into the sandbox env. Credential Vault
# (step 5) is how you avoid that.
import asyncio
import json
import os
from datetime import timedelta

from opensandbox import Sandbox
from opensandbox.config import ConnectionConfig

IMAGE = os.getenv("SANDBOX_IMAGE", "opensandbox/code-interpreter:v1.1.0")


def logs(execution) -> str:
    out = "\n".join(m.text for m in execution.logs.stdout)
    err = "\n".join(m.text for m in execution.logs.stderr)
    if err:
        print(f"[stderr] {err[-600:]}")
    return out


def as_json(text: str) -> dict:
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        print(f"[warn] expected JSON, got: {text[:300]!r}")
        return {}


async def main() -> None:
    api_key = os.environ["ANTHROPIC_API_KEY"]
    config = ConnectionConfig(
        domain=os.getenv("OPEN_SANDBOX_DOMAIN", "127.0.0.1:8080"),
        api_key=os.getenv("OPEN_SANDBOX_API_KEY"),
        request_timeout=timedelta(seconds=120),
    )
    env = {"ANTHROPIC_API_KEY": api_key, "IS_SANDBOX": "1"}
    if os.getenv("ANTHROPIC_MODEL"):
        env["ANTHROPIC_MODEL"] = os.environ["ANTHROPIC_MODEL"]

    print(f"[1/4] creating sandbox from {IMAGE} ...")
    sandbox = await Sandbox.create(IMAGE, connection_config=config, env=env)
    async with sandbox:
        print("[2/4] installing Claude Code in the sandbox ...")
        logs(await sandbox.commands.run("npm i -g @anthropic-ai/claude-code@latest && claude --version"))

        print("[3/4] headless turn ...")
        first = as_json(logs(await sandbox.commands.run(
            'claude -p "Remember this for later: my favorite sandbox number is 42. '
            'Then tell me the OS and kernel you are running on, using a shell command." '
            "--output-format json --dangerously-skip-permissions"
        )))
        print(f"[claude] {first.get('result', '')}")

        session_id = first.get("session_id")
        if session_id:
            print("[4/4] resuming the same session ...")
            second = as_json(logs(await sandbox.commands.run(
                'claude -p "What is my favorite sandbox number? Reply with just the number." '
                f'--resume "{session_id}" --output-format json'
            )))
            print(f"[claude] {second.get('result', '')}")

        await sandbox.kill()


if __name__ == "__main__":
    asyncio.run(main())
