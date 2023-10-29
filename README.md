[![pre-commit](https://img.shields.io/badge/pre--commit-enabled-brightgreen?logo=pre-commit)](https://github.com/pre-commit/pre-commit)

# llscheck

LLSCheck is a command-line utility that leverages the [Lua Language Server](https://luals.github.io)
for linting and static analysis of Lua code.

It delivers user-friendly reports, enhancing readability compared to raw JSON output. Moreover,
LLSCheck seamlessly integrates with popular CI tools, i.e the exit code is a failure when the Lua
Language Server finds issues.

## CLI

### Installation

Using [LuaRocks](https://luarocks.org):

```bash
luarocks install llscheck
```

### Usage

From the command line:

```bash
llscheck --help
```

```
Usage: llscheck [-h] [--completion {bash,zsh,fish}]
       [--checklevel {Error,Warning,Information,Hint}]
       <files> [<files>] ...

Generate a LuaLS diagnosis report and print to human-friendly format.

Arguments:
   files                 List of files and directories to check.

Options:
   -h, --help            Show this help message and exit.
   --completion {bash,zsh,fish}
                         Output a shell completion script for the specified shell.
   --checklevel {Error,Warning,Information,Hint}
                         default: Warning
```

## Version control integration

Use [pre-commit](https://pre-commit.com). Once you [have it installed](https://pre-commit.com/#install),
add this to the `.pre-commit-config.yaml` in your repository:

```yaml
repos:
- repo: https://github.com/jeffzi/llscheck
    rev: latest
    hooks:
      - id: llscheck
        # args: --checklevel Hint
```
