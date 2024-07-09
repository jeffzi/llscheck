local ansicolors = require("ansicolors")
local argparse = require("argparse")
local cjson = require("cjson")
local path = require("pl.path")
local tablex = require("pl.tablex")
local utils = require("pl.utils")

io.stdout:setvbuf("no")

---@enum SEVERITY
local Severity = {
   Error = 1,
   Warning = 2,
   Information = 3,
   Hint = 4,
}

local SeverityName = {
   "Error",
   "Warning",
   "Information",
   "Hint",
}

local SeverityColor = {
   "red",
   "yellow",
   "white bright",
   "white dim",
}

---@param message string
---@param color string
---@return string
local function colorize(message, color)
   return ansicolors("%{" .. color .. "}" .. message .. "%{reset}")
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

---Run `lua-language-server --check` to perform a diganosis report
---@param workspace table A list of source files (or directories) to check.
---@param checklevel string One of: Error, Warning, Information, Hint
---@param configpath string LuaLS configpath argument
---@return table? The parsed diagnosis report (check.json).
local function luals_check(workspace, checklevel, configpath)
   local logpath = path.tmpname()
   os.remove(logpath)
   local diagnosis_path = path.join(logpath, "check.json")
   local args = {
      "--check",
      workspace,
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
      return read_diagnosis(diagnosis_path)
   end
end

---Return a human-friendly LuaLS diagnosis report (1 line).
---@param filepath string
---@param diagnostic table
local function make_diagnostic_line(filepath, diagnostic)
   local colon = colorize(":", "white dim")
   local loc = string.format(
      "%s%s%d%s%d%s%d",
      colorize(filepath, "blue"),
      colon,
      diagnostic.range.start.line + 1,
      colon,
      diagnostic.range.start.character + 1,
      colorize("-", "white dim"),
      diagnostic.range["end"].character
   )
   local msg = diagnostic.message
   local severity = diagnostic.severity
   return string.format(
      "%s%s %s%s %s",
      loc,
      colon,
      colorize(diagnostic.code, SeverityColor[severity]),
      colon,
      severity == Severity.Hint and colorize(msg, SeverityColor[severity]) or msg
   )
end

local function colorized_count(severity_name, count)
   local color = count > 0 and (SeverityColor[Severity[severity_name]] or "white") or "green"
   local msg = string.format("%s %ss", count, severity_name)
   return colorize(msg, color)
end

---Return a summary of the diagnostics
---@param stats table Counts of diagnostics indexed by severity name
---@return string
local function make_summary(stats)
   local summary
   local total = stats["total"]
   if total == 0 then
      summary = "No issues found ✨ 🍰 ✨"
   else
      local severities = {}
      for _, severity_name in ipairs(SeverityName) do
         local count = stats[severity_name]
         if count then
            table.insert(severities, colorized_count(severity_name, stats[severity_name]))
         end
      end
      summary = string.format(
         "\n%s: %s in %d files",
         colorize("Total " .. total, "white bright"),
         table.concat(severities, " / "),
         stats["files"]
      )
   end
   return summary
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

---Return a human-friendly LuaLS diagnosis report.
---@param diagnosis table Array of parsed diagnosis reports (check.json files).
---@return string report Hhuman-friendly LuaLS diagnosis report
---@return table stats Counts of diagnostics indexed by severity name
local function make_report(diagnosis)
   local stats = { total = 0, files = 0 }
   local lines = {}
   for filepath, diagnostics in tablex.sort(diagnosis) do
      stats["files"] = stats["files"] + 1
      filepath = filepath:gsub("file://", "")
      filepath = path.relpath(filepath)
      for _, diagnostic in tablex.sortv(diagnostics, compare_diagnostics) do
         table.insert(lines, make_diagnostic_line(filepath, diagnostic))
         local severity_name = SeverityName[diagnostic.severity]
         stats[severity_name] = (stats[severity_name] or 0) + 1
         stats["total"] = stats["total"] + 1
      end
   end
   table.insert(lines, make_summary(stats))
   return table.concat(lines, "\n"), stats
end

---Validate that filepath exists and convert it to absolute path.
---@param filepath string
---@return string? filepath Validated filepath
---@return string? error Error message
local function validate_file(filepath)
   filepath = path.abspath(filepath)
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
   parser:argument("workspace", "The workspace to check."):default("."):convert(validate_file)
   parser
      :option("--checklevel", "The minimum level of diagnostic that should be logged.")
      :choices({ "Error", "Warning", "Information", "Hint" })
      :default("Warning")
   parser
      :option("--configpath", "Path to a LuaLS config file.")
      :default(get_default_configpath())
      :convert(validate_file)

   local args = parser:parse()

   local diagnosis = luals_check(args.workspace, args.checklevel, args.configpath)
   if diagnosis then
      local report, diagnostics = make_report(diagnosis)
      io.stdout:write(report)
      if diagnostics["total"] > 0 then
         os.exit(1)
      end
   end
end

main()
