[![pre-commit](https://img.shields.io/badge/pre--commit-enabled-brightgreen?logo=pre-commit)](https://github.com/pre-commit/pre-commit)
[![Luacheck](https://github.com/jeffzi/llscheck/actions/workflows/luacheck.yml/badge.svg)](https://github.com/jeffzi/llscheck/actions/workflows/luacheck.yml)
[![Luarocks](https://img.shields.io/luarocks/v/jeffzi/llscheck?label=Luarocks&logo=Lua)](https://luarocks.org/modules/jeffzi/llscheck)

# llscheck

LLSCheck runs [Lua Language Server](https://luals.github.io) diagnostics and formats the results
for human readers.

It returns a non-zero exit code when diagnostics are found, making it easy to use in CI pipelines.

![llscheck demo output](demo.png)

## CLI

### Requirements

Lua Language Server must be [installed locally](https://luals.github.io/#other-install)
and `lua-language-server` must be in your $PATH.

### Installation

Using [LuaRocks](https://luarocks.org):

```bash
luarocks install llscheck
```

### Usage

```bash
llscheck --help
```

```text
Usage: llscheck [-h] [--completion {bash,zsh,fish}]
       [--checklevel {Error,Warning,Information,Hint}]
       [--configpath <configpath>] [<workspace>]

Generate a LuaLS diagnosis report and print to human-friendly format.

Arguments:
   workspace             The workspace to check. (default: .)

Options:
   -h, --help            Show this help message and exit.
   --completion {bash,zsh,fish}
                         Output a shell completion script for the specified shell.
   --checklevel {Error,Warning,Information,Hint}
                         The minimum level of diagnostic that should be logged. (default: Warning)
   --configpath <configpath>
                         Path to a LuaLS config file. (default: .luarc.json)
   --no-color            Do not add color to output.
```

> **Note:** LLSCheck operates on workspaces (directories), not individual files.
>
> ```bash
> llscheck examples/demo/           # Correct
> llscheck examples/demo/init.lua   # Wrong
> ```

### Neovim

See [examples/neovim](examples/neovim/README.md) for using llscheck with Neovim projects

### Programmatic API

LLSCheck can be used as a Lua module:

```lua
local llscheck = require("llscheck")

local diagnosis = llscheck.check_workspace("src", "Warning", ".luarc.json")
local report, stats = llscheck.generate_report(diagnosis)
print(report)
```

## Colored output

LLSCheck disables colored output when:

- llscheck is not run from a terminal (TTY).
- The [NO_COLOR](https://no-color.org/) environment variable is present and not empty.
- The `--no-color` argument is provided.

## Docker

LLSCheck runs as a Docker container. Build it with:

```console
docker build -t llscheck https://github.com/jeffzi/llscheck.git
```

Optionally, you can pin the [version of Lua Language Server][lls-releases] with
`--build-arg LLS_VERSION=3.7.0`.

[lls-releases]: https://github.com/LuaLS/lua-language-server/releases

Once you have a container you can run it with arguments:

```console
# Run llscheck on the src directory
docker run -v "$(pwd):/data" llscheck --checklevel Information src
```

On an Apple Silicon chip M1+, you'll need to add the option `--platform=linux/amd64` to both
docker commands.

## Version control integration

Use [pre-commit](https://pre-commit.com). Once [installed](https://pre-commit.com/#install),
add this to `.pre-commit-config.yaml`:

```yaml
repos:
  - repo: https://github.com/jeffzi/llscheck
    rev: latest
    hooks:
      - id: llscheck
        # args: ["--checklevel", "Hint"]
```
