# A normal Claude agent loop where ONLY the tool runs in the sandbox.
# The LLM call is the usual Anthropic SDK call on your machine. When Claude asks to run a shell command,
# run_bash() sends it to an OpenSandbox sandbox instead of subprocess. That one function is the whole change.
#
# Run from the repo root:
#   source ~/.sandbox.env && export ANTHROPIC_API_KEY=...   # your key, host side only (never enters the sandbox)
#   uv run --with opensandbox --with anthropic python examples/agent_tool_in_sandbox.py
import os
from datetime import timedelta

import anthropic
from opensandbox import SandboxSync
from opensandbox.config import ConnectionConfigSync
from opensandbox.models.sandboxes import NetworkPolicy, NetworkRule, SandboxImageSpec

MODEL = os.getenv("ANTHROPIC_MODEL", "claude-sonnet-5-5")
IMAGE = os.getenv("SANDBOX_IMAGE", "python:3.12-slim")
TASK = (
    "Use the bash tool to: 1) show the OS and kernel, 2) check whether https://pypi.org and "
    "https://example.com are reachable (use python3 urllib, 5 s timeout), 3) write a file /tmp/hello.txt. "
    "Then summarize what you found in three short bullets."
)

BASH_TOOL = {
    "name": "bash",
    "description": "Run a shell command and return stdout, stderr and the exit code.",
    "input_schema": {"type": "object", "properties": {"command": {"type": "string"}}, "required": ["command"]},
}

config = ConnectionConfigSync(
    domain=os.environ["OPEN_SANDBOX_DOMAIN"],
    api_key=os.environ["OPEN_SANDBOX_API_KEY"],
    request_timeout=timedelta(seconds=120),
)
sandbox = SandboxSync.create(
    image=SandboxImageSpec(IMAGE),
    timeout=timedelta(minutes=10),
    network_policy=NetworkPolicy(defaultAction="deny", egress=[NetworkRule(action="allow", target="pypi.org")]),
    connection_config=config,
)


def run_bash(command: str) -> str:
    # Before: subprocess.run(command, shell=True, capture_output=True, text=True)  -> runs on YOUR machine
    # After:  the same string runs inside the sandbox (its filesystem, its egress policy)
    execution = sandbox.commands.run(command)
    out = "\n".join(m.text for m in execution.logs.stdout)
    err = "\n".join(m.text for m in execution.logs.stderr)
    code = execution.error.name if execution.error else "0"
    return f"exit: {code}\nstdout:\n{out}\nstderr:\n{err}"[-4000:]


client = anthropic.Anthropic()  # reads ANTHROPIC_API_KEY on the host
messages = [{"role": "user", "content": TASK}]
try:
    while True:
        response = client.messages.create(model=MODEL, max_tokens=1500, tools=[BASH_TOOL], messages=messages)
        messages.append({"role": "assistant", "content": response.content})
        if response.stop_reason != "tool_use":
            break
        results = []
        for block in response.content:
            if block.type == "tool_use":
                print(f"\n[claude -> sandbox] $ {block.input['command']}")
                output = run_bash(block.input["command"])
                print("  " + output.replace("\n", "\n  ")[:800])
                results.append({"type": "tool_result", "tool_use_id": block.id, "content": output})
        messages.append({"role": "user", "content": results})

    print("\n[claude] " + "".join(b.text for b in response.content if b.type == "text"))
    print("\n[host] does /tmp/hello.txt exist on THIS machine?", os.path.exists("/tmp/hello.txt"), "(it was written in the sandbox)")
finally:
    sandbox.kill()
    sandbox.close()
