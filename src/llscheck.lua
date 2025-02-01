local ansicolors = require("ansicolors")
local argparse = require("argparse")
local cjson = require("cjson")
local path = require("pl.path")
local tablex = require("pl.tablex")
local utils = require("pl.utils")

io.stdout:setvbuf("no")

---@alias SeverityName "Error"|"Warning"|"Information"|"Hint"

---@class DiagnosisStats
---@field total number Total number of diagnostic issues found
---@field files number Number of files with issues
---@field [SeverityName?] integer Count of diagnostic issues per severity level

---@type SeverityName[]
local SEVERITY = { "Error", "Warning", "Information", "Hint" }
local SEVERITY_COLORS = { "red", "yellow", "white bright", "white dim" }

---Create a uniform isatty function.
---@return fun(): boolean
local function get_isatty()
   local system_loaded, system = pcall(require, "system")
   if system_loaded and system.isatty then
      return function()
         return system.isatty(io.stdout)
      end
   end

   local unistd_loaded, unistd = pcall(require, "posix.unistd")
   if unistd_loaded then
      return function()
         return unistd.isatty(unistd.STDOUT_FILENO) == 1
      end
   end

   return function()
      return true
   end
end

---@type fun(message: string, color?: string): string
local colorize

---@param no_color boolean
local function setup_colorize(no_color)
   local isatty = get_isatty()
   local env_no_color = os.getenv("NO_COLOR")

   if isatty() and not no_color and (not env_no_color or env_no_color == "") then
      colorize = function(message, color)
         return ansicolors("%{" .. color .. "}" .. message .. "%{reset}")
      end
   else
      colorize = function(message)
         return message
      end
   end
end

---Parse a LuaLS diagnosis report check.json file.
---@param filepath string
---@return table
local function read_diagnosis(filepath)
   local file = assert(io.open(filepath, "r"))
   local content = file:read("*a")
   file:close()
   return cjson.decode(content)
end

---Execute the command and exit the program on error.
---@param cmd string
local function execute(cmd)
   local ok, _, _, stderr = utils.executeex(cmd)
   if not ok then
      utils.quit(
         -1,
         string.format(
            "%s%s\n%s",
            colorize("Command failed: ", "red"),
            colorize(cmd, "yellow"),
            stderr:match("^%s*(.-)%s*$")
         )
      )
   end
end

---Run lua-language-server --check command.
---@param workspace string A workspace to check.
---@param checklevel string One of: ERROR, WARNING, INFO, HINT
---@param configpath string LuaLS configpath argument
---@return table? The parsed diagnosis report (check.json).
local function check_workspace(workspace, checklevel, configpath)
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
      table.insert(args, "--configpath")
      table.insert(args, configpath)
   end

   execute("lua-language-server " .. utils.quote_arg(args))

   if path.exists(diagnosis_path) then
      return read_diagnosis(diagnosis_path)
   end
end

---Format diagnostic location and message.
---@param filepath string
---@param diagnostic table
---@return string
local function format_diagnostic_line(filepath, diagnostic)
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

   local severity_color = SEVERITY_COLORS[diagnostic.severity]
   local msg = diagnostic.message

   return string.format(
      "%s%s %s%s %s",
      loc,
      colon,
      colorize(diagnostic.code, severity_color),
      colon,
      diagnostic.severity == 4 and colorize(msg, severity_color) or msg
   )
end

---Format count of issues by severity.
---@param name SeverityName
---@param severity integer
---@param count number
---@return string
local function colorized_count(name, severity, count)
   local color = count > 0 and (SEVERITY_COLORS[severity] or "white") or "green"
   return colorize(string.format("%d %ss", count, name), color)
end

---Generate diagnostic summary.
---@param stats DiagnosisStats Counts of diagnostics indexed by severity name
---@return string
local function generate_summary(stats)
   if stats.total == 0 then
      return "Diagnosis completed, no problems found"
   end

   local severities = {}
   for severity, name in ipairs(SEVERITY) do
      local count = stats[name]
      if count then
         table.insert(severities, colorized_count(name, severity, count))
      end
   end

   return string.format(
      "\n%s: %s in %d files",
      colorize("Total " .. stats.total, "white bright"),
      table.concat(severities, " / "),
      stats.files
   )
end

---Compare diagnostic entries for sorting.
---@param x table
---@param y table
---@return boolean
local function compare_diagnostics(x, y)
   local x_line, y_line = x.range.start.line, y.range.start.line
   if x_line ~= y_line then
      return x_line < y_line
   end

   local x_char, y_char = x.range.start.character, y.range.start.character
   if x_char ~= y_char then
      return x_char < y_char
   end

   return x.severity < y.severity
end

---Generate human-friendly diagnosis report.
---@param diagnosis table Array of parsed diagnosis reports (check.json files).
---@return string report Human-friendly LuaLS diagnosis report
---@return DiagnosisStats stats Counts of diagnostics indexed by severity name
local function generate_report(diagnosis)
   local stats = { total = 0, files = 0 }
   local lines = {}

   for filepath, diagnostics in tablex.sort(diagnosis) do
      stats.files = stats.files + 1
      filepath = filepath:gsub("file://", "")
      filepath = path.relpath(filepath)

      for _, diagnostic in tablex.sortv(diagnostics, compare_diagnostics) do
         table.insert(lines, format_diagnostic_line(filepath, diagnostic))
         local severity_name = SEVERITY[diagnostic.severity]
         stats[severity_name] = (stats[severity_name] or 0) + 1
         stats.total = stats.total + 1
      end
   end

   table.insert(lines, generate_summary(stats))
   return table.concat(lines, "\n"), stats
end

---Validate file existence and return absolute path.
---@param filepath string
---@return string? filepath Validated filepath
---@return string? error ERROR message
local function validate_file(filepath)
   if not path.exists(filepath) then
      return nil, string.format("'%s': No such file or directory", filepath)
   end
   return filepath
end

---Get default config path if it exists.
---@return string?
local function get_default_configpath()
   local default = path.join(path.currentdir(), ".luarc.json")
   return path.exists(default) and path.abspath(default) or nil
end

local function main()
   local parser = argparse(
      "llscheck",
      "Generate a LuaLS diagnosis report and print to human-friendly format."
   ):add_complete()

   parser:argument("workspace", "The workspace to check."):default("."):convert(validate_file)

   parser
      :option("--checklevel", "The minimum level of diagnostic that should be logged.")
      :choices(SEVERITY)
      :default("Warning")

   parser
      :option("--configpath", "Path to a LuaLS config file.")
      :default(get_default_configpath())
      :convert(validate_file)

   parser:flag("--no-color", "Do not add color to output.")

   local args = parser:parse()
   setup_colorize(args.no_color)

   local diagnosis = check_workspace(args.workspace, args.checklevel, args.configpath)
   if diagnosis then
      local report, stats = generate_report(diagnosis)
      io.stdout:write(report .. "\n")
      os.exit(stats.total > 0 and 1 or 0)
   end
end

main()
