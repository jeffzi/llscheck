local argparse = require("argparse")
local cjson = require("cjson")
local colors = require("ansicolors")
local lfs = require("lfs")

---@enum Severity
local Severity = {
   Error = 1,
   Warning = 2,
   Information = 3,
   Hint = 4,
}

---Colorize message depending on the severity.
---@param message any
---@param severity Severity
---@return string
local function colorize_severity(message, severity)
   if severity == Severity.Error then
      return colors("%{red}" .. message)
   elseif severity == Severity.Warning then
      return colors("%{yellow}" .. message)
   else
      return colors("%{white}" .. message)
   end
end

---Return True if the file exists.
---@param path string
---@return boolean?
local function file_exists(path)
   local file = io.open(path, "r")
   return file ~= nil and io.close(file)
end

---Exit the program if the file doesn't exist.
---@param path string
---@return boolean?
local function check_file(path)
   if not file_exists(path) then
      local msg = string.format("%s does not exist!", path)
      print(colors("%{red}" .. msg))
      os.exit(1)
   end
end

---Print a LuaLS diagnostic
---@param file_path string
---@param diagnostic table
local function print_diagnostic(file_path, diagnostic)
   local colon = colors("%{ white dim}:")
   local dash = colors("%{ white dim}-")
   local loc = string.format(
      "%s%s%d%s%d%s%d",
      colors("%{blue}" .. file_path .. "%{reset}"),
      colon,
      diagnostic.range.start.line,
      colon,
      diagnostic.range.start.character,
      dash,
      diagnostic.range["end"].character
   )
   print(
      string.format(
         "%s%s %s%s %s",
         loc,
         colon,
         colorize_severity(diagnostic.code, diagnostic.severity),
         colon,
         diagnostic.message
      )
   )
end

---Print a summary of the diagnostics
---@param warnings integer Number of warnings
---@param errors integer Number of errors
---@param files integer Number of files containing diagnostics
local function print_summary(warnings, errors, files)
   local zero_count = colors("%{green} 0")
   local warn_count = warnings > 0 and colorize_severity(warnings, Severity.Warning) or zero_count
   local err_count = errors > 0 and colorize_severity(errors, Severity.Error) or zero_count
   print(string.format("Total: %s warnings / %s errors in %s files", warn_count, err_count, files))
end

local function main()
   local parser = argparse(
      "llscheck",
      "Convert Lua Language Server diagnostics for human and CI friendly interpretation."
   )
   parser:argument("report", "LuaLS JSON Diagnosis Report")
   local args = parser:parse()
   local path = args.report
   check_file(path)

   local file = assert(io.open(args.report, "r"))
   local content = file:read("*a")
   file:close()
   local data = cjson.decode(content)

   local current_dir = lfs.currentdir()
   local errors = 0
   local warnings = 0
   local files = 0
   local total_diagnostics = 0

   for file_path, diagnostics in pairs(data) do
      files = files + 1
      file_path = file_path:gsub("file://" .. current_dir .. "/", "")
      for _, diagnostic in ipairs(diagnostics) do
         print_diagnostic(file_path, diagnostic)
         if diagnostic.severity == Severity.Error then
            errors = errors + 1
         elseif diagnostic.severity == Severity.Warning then
            warnings = warnings + 1
         end
         total_diagnostics = total_diagnostics + 1
      end
   end

   print_summary(warnings, errors, files)
   if total_diagnostics > 0 then
      os.exit(1)
   end
end

main()
