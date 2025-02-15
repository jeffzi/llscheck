local ansicolors = require("ansicolors")
local argparse = require("argparse")
local cjson = require("cjson")
local path = require("pl.path")
local tablex = require("pl.tablex")
local utils = require("pl.utils")

io.stdout:setvbuf("no")

local llscheck = {}

-- ----------------------------------------------------------------------------
-- Typing
-- ----------------------------------------------------------------------------

---@alias SeverityName
---| 'Hint'
---| 'Information'
---| 'Warning'
---| 'Error'

---@alias SeverityLevel
---| 4
---| 3
---| 2
---| 1

---@type table<SeverityName, SeverityLevel>
local SEVERITY = {
   Error = 1,
   Warning = 2,
   Information = 3,
   Hint = 4,
}

---@type SeverityName[]
local SEVERITY_NAMES = {}
for name, level in pairs(SEVERITY) do
   SEVERITY_NAMES[level] = name
end

---@class Position
---@field line integer
---@field character integer

---@class Range
---@field start Position
---@field ["end"] Position

---@class Diagnostic
---@field code string
---@field message string
---@field range Range
---@field severity SeverityLevel

---@alias URI string
---@alias Diagnosis table<URI, Diagnostic[]> Content of check.json

---@class Stats
---@field total integer Total number of diagnostic issues found
---@field files integer Number of files with issues
---@field [SeverityLevel?] integer Count of diagnostic issues per severity level

-- ----------------------------------------------------------------------------
-- Colors
-- ----------------------------------------------------------------------------

---@type table<SeverityLevel, string>
local SEVERITY_COLORS = { "red", "yellow", "white bright", "white dim" }

--- Create a uniform isatty function.
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

--- Set up whether to use ANSI colors for output messages based on:
--- - Whether color output is explicitly enabled/disabled via the show_color parameter
--- - Whether the output is going to a terminal (TTY)
--- - Whether the NO_COLOR environment variable is set (https://no-color.org/)
---@param show_color? boolean Whether to enable colored output. Defaults to true if nil.
function llscheck.setup_colorize(show_color)
   if show_color == nil then
      show_color = true
   end
   local isatty = get_isatty()
   local no_color = os.getenv("NO_COLOR")

   if isatty() and show_color and (not no_color or no_color == "") then
      colorize = function(message, color)
         return ansicolors("%{" .. color .. "}" .. message .. "%{reset}")
      end
   else
      colorize = function(message)
         return message
      end
   end
end

-- ----------------------------------------------------------------------------
-- Execute LuaLS
-- ----------------------------------------------------------------------------

---@param filepath string
---@return table<URI, Diagnostic[]>
local function read_diagnosis(filepath)
   local file = assert(io.open(filepath, "r"))
   local content = file:read("*a")
   file:close()
   return cjson.decode(content)
end

--- Run lua-language-server --check command.
---@param workspace string
---@param checklevel SeverityName
---@param configpath string LuaLS configpath argument
---@return Diagnosis? diagnosis
function llscheck.check_workspace(workspace, checklevel, configpath)
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
      "--check_format",
      "json",
   }
   if configpath then
      table.insert(args, "--configpath")
      table.insert(args, configpath)
   end

   local cmd = "lua-language-server " .. utils.quote_arg(args)
   local ok, _, _, stderr = utils.executeex(cmd)
   local has_diagnosis = path.exists(diagnosis_path)

   if not ok and not has_diagnosis then
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

   if has_diagnosis then
      return read_diagnosis(diagnosis_path)
   end
end

-- ----------------------------------------------------------------------------
-- Format diagnosis
-- ----------------------------------------------------------------------------

---@param filepath string
---@param diagnostic Diagnostic
---@return string
local function format_diagnostic_line(filepath, diagnostic)
   local colon = colorize(":", "white dim")
   local loc = string.format(
      "%s%s%d%s%d%s%d",
      filepath,
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
      diagnostic.severity == SEVERITY.Hint and colorize(msg, severity_color) or msg
   )
end

--- Format count of issues by severity.
---@param severity_name SeverityName
---@param count integer
---@return string
local function colorized_count(severity_name, count)
   local color = count > 0 and (SEVERITY_COLORS[SEVERITY[severity_name]] or "white") or "green"
   return colorize(string.format("%d %ss", count, severity_name), color)
end

--- Compare two diagnostics based on their position and severity.
--- @param x Diagnostic
--- @param y Diagnostic
--- @return boolean Returns
function llscheck.compare_diagnostics(x, y)
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

--- Convert a URI to a file path.
--- @param uri string The URI to convert.
--- @return string filepath The resulting file path
function llscheck.uri_to_path(uri)
   local filepath = uri:gsub("^file:///?(%a?:?/)", "%1")
   -- Decode percent-encoded characters
   filepath = filepath:gsub("%%(%x%x)", function(hex)
      return string.char(tonumber(hex, 16))
   end)
   return filepath
end

---@param stats table<SeverityName, integer>
---@return string[]
local function get_colored_severities(stats)
   local severities = {}
   for level, name in ipairs(SEVERITY_NAMES) do
      local count = stats[level]
      local colored = count and colorized_count(name, count) or nil
      if colored then
         table.insert(severities, colored)
      end
   end
   return severities
end

---@param stats Stats
---@return string
local function generate_summary(stats)
   if stats.total == 0 then
      return "Diagnosis completed, no problems found"
   end

   return string.format(
      "%s: %s in %d files",
      colorize("Total " .. stats.total, "white bright"),
      table.concat(get_colored_severities(stats), " / "),
      stats.files
   )
end

--- Generate human-friendly diagnosis report.
---@param diagnosis Diagnosis
---@return string report Human-friendly LuaLS diagnosis report
---@return Stats stats Counts of diagnostics indexed by severity name
function llscheck.generate_report(diagnosis)
   local total_stats = { total = 0, files = 0 }
   local lines = {}

   -- Calculate target summary column for alignment
   local max_filename_length = 0
   for uri in pairs(diagnosis) do
      local filepath = path.relpath(llscheck.uri_to_path(uri))
      max_filename_length = math.max(max_filename_length, #filepath + 1)
   end
   local target_column = math.min(max_filename_length + 5, 50)

   -- Generate report lines
   for uri, diagnostics in tablex.sort(diagnosis) do
      local filepath = path.relpath(llscheck.uri_to_path(uri))
      total_stats.files = total_stats.files + 1

      local file_stats = {}
      local diagnostic_lines = {}
      for _, diagnostic in tablex.sortv(diagnostics, llscheck.compare_diagnostics) do
         table.insert(diagnostic_lines, format_diagnostic_line(filepath, diagnostic))
         file_stats[diagnostic.severity] = (file_stats[diagnostic.severity] or 0) + 1

         total_stats[diagnostic.severity] = (total_stats[diagnostic.severity] or 0) + 1
         total_stats.total = total_stats.total + 1
      end

      local padding = string.rep(" ", target_column - #filepath - 1)
      local header = string.format(
         "\n%s:%s%s\n",
         colorize(filepath, "underline blue"),
         padding,
         table.concat(get_colored_severities(file_stats), " / ")
      )

      table.insert(lines, header)
      for _, line in ipairs(diagnostic_lines) do
         table.insert(lines, line)
      end
   end

   table.insert(lines, generate_summary(total_stats))
   return table.concat(lines, "\n"), total_stats
end

-- ----------------------------------------------------------------------------
-- CLI
-- ----------------------------------------------------------------------------

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

local function run()
   local parser = argparse(
      "llscheck",
      "Generate a LuaLS diagnosis report and print to human-friendly format."
   ):add_complete()

   parser:argument("workspace", "The workspace to check."):default("."):convert(validate_file)

   parser
      :option("--checklevel", "The minimum level of diagnostic that should be logged.")
      :choices(SEVERITY_NAMES)
      :default("Warning")

   parser
      :option("--configpath", "Path to a LuaLS config file.")
      :default(get_default_configpath())
      :convert(validate_file)

   parser:flag("--no-color", "Do not add color to output.")

   local args = parser:parse()
   llscheck.setup_colorize(not args.no_color)

   local diagnosis = llscheck.check_workspace(args.workspace, args.checklevel, args.configpath)
   if diagnosis then
      local report, stats = llscheck.generate_report(diagnosis)
      io.stdout:write(report .. "\n")
      os.exit(stats.total > 0 and 1 or 0)
   end
end

-- Only run the CLI if this file is being run directly (not required as a module)
if arg and arg[0]:match("llscheck") then
   run()
end

llscheck.setup_colorize(true)

return llscheck
