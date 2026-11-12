# OpenSandbox hello world (from the OpenSandbox README).
# Run from the repo root: source ~/.sandbox.env && uv run --with opensandbox python examples/hello_sandbox.py
import asyncio

from opensandbox import Sandbox
from opensandbox.models import WriteEntry


async def main() -> None:
    sandbox = await Sandbox.create("alpine")
    try:
        execution = await sandbox.commands.run("echo 'Hello OpenSandbox!' && uname -a")
        for log in execution.logs.stdout:
            print(log.text)

        await sandbox.files.write_files([
            WriteEntry(
                path="/tmp/hello.sh",
                data="echo \"Hello $1\"\necho '2 + 2 =' $((2 + 2))",
                mode=755,
            )
        ])
        execution = await sandbox.commands.run("sh /tmp/hello.sh CAST-SD")
        for log in execution.logs.stdout:
            print(log.text)
    finally:
        await sandbox.destroy()


if __name__ == "__main__":
    asyncio.run(main())
