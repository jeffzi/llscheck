local ansicolors = require("ansicolors")
local argparse = require("argparse")
local cjson = require("cjson")
local path = require("pl.path")
local tablex = require("pl.tablex")
local utils = require("pl.utils")

io.stdout:setvbuf("no")

---@enum Severity
local Severity = {
   Error = 1,
   Warning = 2,
   Information = 3,
   Hint = 4,
}

---@param message string
---@param color string
---@return string
local function colorize(message, color)
   local txt = "%" .. string.format("{%s}%s", color, message)
   return ansicolors(txt)
end

---Colorize message depending on the severity.
---@param message any
---@param severity Severity
---@return string
local function colorize_severity(message, severity)
   local color
   if severity == Severity.Error then
      color = "red"
   elseif severity == Severity.Warning then
      color = "yellow"
   else
      color = "white"
   end
   return colorize(message, color)
end

---Parse a LuaLS diagnosis report check.json file.
---@param filepath string
---@return table
local function read_diagnosis(filepath)
   local file = assert(io.open(filepath, "r"))
   local raw_diagnosis = file:read("*a")
   file:close()
   return cjson.decode(raw_diagnosis)
end

---Execute the command and exit the program on error.
---@param cmd string
local function execute(cmd)
   local is_success, _, _, stderr = utils.executeex(cmd)
   if not is_success then
      local trimmed_stderr = stderr:gsub("^%s*(.-)%s*$", "%1")
      local header = (colorize("Command failed: ", "red") .. colorize(cmd, "yellow"))
      utils.quit(-1, header .. "\n" .. trimmed_stderr)
   end
end

---Run `lua-language-server --check` for each source file in files.
---@param files table A list of source files (or directories) to check.
---@param checklevel string One of: Error, Warning, Information, Hint
---@param configpath string LuaLS configpath argument
---@return table A list of parsed diagnosis report (check.json).
local function luals_check(files, checklevel, configpath)
   local diagnosis = {}
   for _, src_file in ipairs(files) do
      local logpath = path.tmpname()
      os.remove(logpath)
      local diagnosis_path = path.join(logpath, "check.json")
      local args = {
         "--check",
         src_file,
         "--checklevel",
         checklevel,
         "--logpath",
         logpath,
      }
      if configpath then
         table.insert(args, { "--configpath", configpath })
      end
      local lls_cmd = "lua-language-server " .. utils.quote_arg(args)

      execute(lls_cmd)

      if path.exists(diagnosis_path) then
         local partial_diagnosis = read_diagnosis(diagnosis_path)
         table.insert(diagnosis, partial_diagnosis)
      end
   end
   return diagnosis
end

---Print human-friendly LuaLS diagnosis report (1 line).
---@param filepath string
---@param diagnostic table
local function print_diagnostic_line(filepath, diagnostic)
   local colon = colorize(":", "white dim")
   local dash = colorize("-", "white dim")
   local loc = string.format(
      "%s%s%d%s%d%s%d",
      colorize(filepath, "blue"),
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
   local zero_count = colorize("0", "green")
   local warn_count = warnings > 0 and colorize_severity(warnings, Severity.Warning) or zero_count
   local err_count = errors > 0 and colorize_severity(errors, Severity.Error) or zero_count
   local msg = string.format("Total: %s warnings / %s errors", warn_count, err_count)
   if files > 0 then
      msg = string.format("%s in %s files", msg, files)
   end
   print(msg)
end

---Compare diagnostic lines for sorting
---@param x table
---@param y table
---@return boolean
local function compare_diagnostics(x, y)
   local x_line = x.range.start.line
   local y_line = y.range.start.line
   if x_line ~= y_line then
      return x_line < y_line
   end

   local x_character = x.range.start.character
   local y_character = y.range.start.character
   if x_character ~= y_character then
      return x_character < y_character
   end

   return x.severity < y.severity
end

---Print a human-friendly LuaLS diagnosis report.
---@param raw_reports table Array of parsed diagnosis reports (check.json files).
local function print_report(raw_reports)
   local errors = 0
   local warnings = 0
   local files = 0
   local total_diagnostics = 0
   for _, raw_report in ipairs(raw_reports) do
      for filepath, diagnostics in tablex.sort(raw_report) do
         files = files + 1
         filepath = filepath:gsub("file://", "")
         filepath = path.relpath(filepath)
         for _, diagnostic in tablex.sortv(diagnostics, compare_diagnostics) do
            print_diagnostic_line(filepath, diagnostic)
            if diagnostic.severity == Severity.Error then
               errors = errors + 1
            elseif diagnostic.severity == Severity.Warning then
               warnings = warnings + 1
            end
            total_diagnostics = total_diagnostics + 1
         end
      end
   end

   print_summary(warnings, errors, files)
   return total_diagnostics
end

---Validate that filepath exists and convert it to absolute path.
---@param filepath string
---@return string? Validated filepath
---@return string? Error message
local function validate_file(filepath)
   if not path.exists(filepath) then
      return nil, string.format("'%s': No such file or directory", filepath)
   end
   return filepath
end

---Return default configpath if it exists
---@return string?
local function get_default_configpath()
   local default = path.join(path.currentdir(), ".luarc.json")
   if path.exists(default) then
      -- LuaLS has troubles dealing with non-absolute configpath.
      -- https://github.com/LuaLS/lua-language-server/issues/2038
      return path.abspath(default)
   else
      return nil
   end
end

local function main()
   local desc = "Generate a LuaLS diagnosis report and print to human-friendly format."
   local parser = argparse("llscheck", desc):add_complete()
   parser
      :argument("files", "List of files and directories to check.")
      :args("+")
      :convert(validate_file)
   parser
      :option("--checklevel", "The minimum level of diagnostic that should be logged.")
      :choices({ "Error", "Warning", "Information", "Hint" })
      :default("Warning")
   parser
      :option("--configpath", "Path to a LuaLS config file.")
      :default(get_default_configpath())
      :convert(validate_file)

   local args = parser:parse()

   local raw_reports = luals_check(args.files, args.checklevel, args.configpath)
   local diagnostics = print_report(raw_reports)

   if diagnostics > 0 then
      os.exit(1)
   end
end

main()
