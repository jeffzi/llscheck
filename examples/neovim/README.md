# How To Run
```sh
VIMRUNTIME="`nvim --clean --headless --cmd 'lua io.write(os.getenv("VIMRUNTIME"))' --cmd 'quit'`" llscheck .
```

If you run the line above

- line 1 will succeed
- line 2 will fail because of a mismatched type, as we expected

This proves that `llscheck` is working as intended!


# How It Works
In the [.luarc.json](./.luarc.json) file there is a line called
`"$VIMRUNTIME/lua"` and it has all of Neovim's [LuaCATS type
annotations](https://luals.github.io/wiki/annotations). All we need to do to
get the magic working is to define `$VIMRUNTIME`. This variable is defined in
Neovim so we run Neovim and immediately print its value to the terminal using
`io.write` and then `:quit`. The resulting expression above is a bit verbose
but it does the trick on any Neovim installation you might have.

From there, we just call `llscheck` as we normally would!
