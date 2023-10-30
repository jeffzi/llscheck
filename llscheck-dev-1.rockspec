package = "llscheck"

local package_version = "dev"
local rockspec_revision = "1"

version = package_version .. "-" .. rockspec_revision

source = {
   url = "git+https://github.com/jeffzi/llscheck.git",
}

if package_version == "dev" then
   source.branch = "main"
else
   source.tag = "v" .. package_version
end

description = {
   summary = "Human-friendly Lua code analysis powered by Lua Language Server.",
   detailed = [[
      LLSCheck is a command-line utility that leverages the Lua Language Server for linting and
      static analysis of Lua code. It delivers user-friendly reports, enhancing readability compared
      to raw JSON output. Moreover, LLSCheck seamlessly integrates with popular CI tools.
   ]],
   homepage = "https://github.com/jeffzi/llscheck",
   license = "MIT",
}

dependencies = {
   "lua >= 5.1",
   "ansicolors >=v1.0.2",
   "argparse >= 0.7.0",
   "lua-cjson >= 2.1.0.9",
   "luafilesystem >= 1.8.0",
   "penlight >= 1.11.0",
}

build = {
   type = "builtin",
   modules = {
      llscheck = "src/llscheck.lua",
   },
   install = {
      bin = {
         llscheck = "bin/llscheck.lua",
      },
   },
}
