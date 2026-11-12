# Interactive chat with Claude where the sandbox is created lazily: only when Claude first uses a tool.
# Text-only turns never touch a sandbox. Once created, the same sandbox is reused for the whole
# conversation (files and installed packages persist across turns) and killed when you quit.
#
# Run from the repo root, with the OpenSandbox server running (uvx opensandbox-server):
#   source ~/.sandbox.env && read -s ANTHROPIC_API_KEY && export ANTHROPIC_API_KEY
#   uv run --with opensandbox --with anthropic python examples/chat_with_sandbox.py
#
# Try: "what's a microVM?" (text only), then "what kernel are you on?" (creates the sandbox),
# then "write /tmp/notes.txt", then "is /tmp/notes.txt still there?" (same sandbox, it is).
import os
import time
from datetime import timedelta

import anthropic
from opensandbox import SandboxSync
from opensandbox.config import ConnectionConfigSync
from opensandbox.models.sandboxes import NetworkPolicy, NetworkRule, SandboxImageSpec

MODEL = os.getenv("ANTHROPIC_MODEL", "claude-sonnet-5-5")
IMAGE = os.getenv("SANDBOX_IMAGE", "python:3.12-slim")
SYSTEM = (
    "You are a helpful assistant. You have a bash tool that runs in an isolated Linux sandbox. "
    "Use it only when a question needs running something; answer conversational questions directly."
)
BASH_TOOL = {
    "name": "bash",
    "description": "Run a shell command in an isolated Linux sandbox and return stdout, stderr and the exit code.",
    "input_schema": {"type": "object", "properties": {"command": {"type": "string"}}, "required": ["command"]},
}

config = ConnectionConfigSync(
    domain=os.environ["OPEN_SANDBOX_DOMAIN"],
    api_key=os.environ["OPEN_SANDBOX_API_KEY"],
    request_timeout=timedelta(seconds=120),
)
sandbox = None  # created on the first tool call


def get_sandbox() -> SandboxSync:
    global sandbox
    if sandbox is None:
        print("  [sandbox] first tool call: creating a sandbox for this conversation ...")
        t0 = time.monotonic()
        sandbox = SandboxSync.create(
            image=SandboxImageSpec(IMAGE),
            timeout=timedelta(minutes=30),
            network_policy=NetworkPolicy(defaultAction="deny", egress=[NetworkRule(action="allow", target="pypi.org")]),
            connection_config=config,
        )
        print(f"  [sandbox] ready in {time.monotonic() - t0:.1f} s; reused for the rest of the chat")
    return sandbox


def run_bash(command: str) -> str:
    execution = get_sandbox().commands.run(command)
    out = "\n".join(m.text for m in execution.logs.stdout)
    err = "\n".join(m.text for m in execution.logs.stderr)
    code = execution.error.name if execution.error else "0"
    return f"exit: {code}\nstdout:\n{out}\nstderr:\n{err}"[-4000:]


client = anthropic.Anthropic()  # the LLM call stays on the host, with the host's key
messages = []
print(f"Chat with {MODEL}. The sandbox is created only if Claude needs to run something. Type /quit to exit.")
try:
    while True:
        try:
            user = input("\nyou> ").strip()
        except EOFError:
            break
        if user in ("/quit", "/exit"):
            break
        if not user:
            continue
        messages.append({"role": "user", "content": user})

        tool_calls = 0
        while True:  # one user turn: loop until Claude stops asking for tools
            response = client.messages.create(
                model=MODEL, max_tokens=1500, system=SYSTEM, tools=[BASH_TOOL], messages=messages
            )
            messages.append({"role": "assistant", "content": response.content})
            if response.stop_reason != "tool_use":
                break
            results = []
            for block in response.content:
                if block.type == "tool_use":
                    tool_calls += 1
                    print(f"  [claude -> sandbox] $ {block.input['command']}")
                    output = run_bash(block.input["command"])
                    print("    " + output.replace("\n", "\n    ")[:600])
                    results.append({"type": "tool_result", "tool_use_id": block.id, "content": output})
            messages.append({"role": "user", "content": results})

        text = "".join(b.text for b in response.content if b.type == "text")
        note = f"{tool_calls} tool call(s) in the sandbox" if tool_calls else "text only, no sandbox"
        print(f"\nclaude> {text}\n  ({note})")
finally:
    if sandbox is not None:
        print("\n[sandbox] killing the conversation's sandbox")
        sandbox.kill()
        sandbox.close()
    else:
        print("\n[sandbox] none was created: the whole chat was text only")
