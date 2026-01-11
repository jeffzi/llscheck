local llscheck = require("llscheck")
local path = require("pl.path")

describe("llscheck", function()
   before_each(function()
      llscheck.setup_colorize(false)
   end)

   local sample_diagnosis = {
      ["file://" .. path.abspath("test/main.lua")] = {
         {
            code = "unused-local",
            message = "Unused local variable 'foo'",
            range = {
               start = { line = 0, character = 6 },
               ["end"] = { character = 9 },
            },
            severity = 2, -- Warning
         },
         {
            code = "undefined-global",
            message = "Undefined global 'bar'",
            range = {
               start = { line = 1, character = 0 },
               ["end"] = { character = 3 },
            },
            severity = 1, -- Error
         },
      },
   }

   test("uri_to_path converts file URI to path", function()
      assert.are_equal("/test/file.lua", llscheck.uri_to_path("file:///test/file.lua"))
   end)

   test("uri_to_path handles windows paths", function()
      assert.are_equal("C:/test/file.lua", llscheck.uri_to_path("file:///C:/test/file.lua"))
   end)

   test("uri_to_path decodes percent-encoded characters", function()
      assert.are_equal(
         "/test/space file.lua",
         llscheck.uri_to_path("file:///test/space%20file.lua")
      )
   end)

   test("compare_diagnostics sorts by line number first", function()
      local diag1 = {
         range = { start = { line = 1, character = 0 } },
         severity = 1,
      }
      local diag2 = {
         range = { start = { line = 2, character = 0 } },
         severity = 1,
      }
      assert.truthy(llscheck.compare_diagnostics(diag1, diag2))
      assert.falsy(llscheck.compare_diagnostics(diag2, diag1))
   end)

   test("compare_diagnostics sorts by character position when lines are equal", function()
      local diag1 = {
         range = { start = { line = 1, character = 0 } },
         severity = 1,
      }
      local diag2 = {
         range = { start = { line = 1, character = 5 } },
         severity = 1,
      }
      assert.truthy(llscheck.compare_diagnostics(diag1, diag2))
      assert.falsy(llscheck.compare_diagnostics(diag2, diag1))
   end)

   test("compare_diagnostics sorts by severity when position is equal", function()
      local diag1 = {
         range = { start = { line = 1, character = 0 } },
         severity = 1,
      }
      local diag2 = {
         range = { start = { line = 1, character = 0 } },
         severity = 2,
      }
      assert.truthy(llscheck.compare_diagnostics(diag1, diag2))
      assert.falsy(llscheck.compare_diagnostics(diag2, diag1))
   end)

   test("generate_report generates correct stats", function()
      local _, stats = llscheck.generate_report(sample_diagnosis)
      assert.are_equal(2, stats.total)
      assert.are_equal(1, stats.files)
      assert.are_equal(1, stats[1]) -- 1 Error
      assert.are_equal(1, stats[2]) -- 1 Warning
      assert.is_nil(stats[3]) -- 0 Information
      assert.is_nil(stats[4]) -- 0 Hint
   end)

   test("generate_report generates report with no issues", function()
      local report, stats = llscheck.generate_report({})
      assert.are_equal(0, stats.total)
      assert.are_equal(0, stats.files)
      assert.matches("no problems found", report)
   end)

   test("generate_report formats diagnostic lines correctly", function()
      local report = llscheck.generate_report(sample_diagnosis)
      -- New format: indented, no filepath, with severity prefix
      assert.matches("%s+1:7%-9%s+%[Warning%] unused%-local", report)
      assert.matches("%s+2:1%-3%s+%[Error%] undefined%-global", report)
      assert.matches("Total 2: 1 Errors / 1 Warnings in 1 files", report)
   end)

   test("generate_report formats colored diagnostic lines correctly", function()
      llscheck.setup_colorize(true)
      local report = llscheck.generate_report(sample_diagnosis)

      -- Check for specific colored components
      assert.matches("\27%[34mtest/main%.lua", report) -- blue filepath (header only)
      assert.matches("\27%[33m%[Warning%]", report) -- yellow severity prefix
      assert.matches("\27%[31m%[Error%]", report) -- red severity prefix
      -- Verify reset codes
      assert.matches("\27%[0m", report) -- Color reset sequence
   end)

   test("check_workspace executes lua-language-server --check", function()
      local diagnosis = llscheck.check_workspace(".", "Hint")
      local report, stats = llscheck.generate_report(diagnosis)
      assert.are_equal(0, stats.total)
      assert.are_equal(0, stats.files)
      assert.matches("no problems found", report)
   end)

   test("llscheck.lua is executable", function()
      local llscheck_path = path.join("src", "llscheck.lua")
      assert.are_equal(0, os.execute("lua " .. llscheck_path))
   end)

   test("uri_to_path handles double-encoded characters", function()
      assert.are_equal(
         "/test/space%20file.lua",
         llscheck.uri_to_path("file:///test/space%2520file.lua")
      )
   end)

   test("uri_to_path handles special characters", function()
      assert.are_equal("/test/file[1].lua", llscheck.uri_to_path("file:///test/file%5B1%5D.lua"))
   end)

   test("generate_report handles multi-line diagnostic messages", function()
      local multiline_diagnosis = {
         ["file://" .. path.abspath("test/main.lua")] = {
            {
               code = "type-mismatch",
               message = "Cannot assign `string` to `number`.\nExpected: number\nGot: string",
               range = {
                  start = { line = 0, character = 0 },
                  ["end"] = { character = 5 },
               },
               severity = 1,
            },
         },
      }
      local report = llscheck.generate_report(multiline_diagnosis)
      assert.matches("Cannot assign", report)
      assert.matches("Expected: number", report)
      assert.matches("Got: string", report)
   end)

   test("generate_report handles diagnostics at same position with different severities", function()
      local same_position_diagnosis = {
         ["file://" .. path.abspath("test/main.lua")] = {
            {
               code = "error-code",
               message = "Error message",
               range = {
                  start = { line = 0, character = 0 },
                  ["end"] = { character = 5 },
               },
               severity = 1, -- Error
            },
            {
               code = "warning-code",
               message = "Warning message",
               range = {
                  start = { line = 0, character = 0 },
                  ["end"] = { character = 5 },
               },
               severity = 2, -- Warning
            },
         },
      }
      local _, stats = llscheck.generate_report(same_position_diagnosis)
      assert.are_equal(2, stats.total)
      assert.are_equal(1, stats[1]) -- 1 Error
      assert.are_equal(1, stats[2]) -- 1 Warning
   end)

   test("generate_report handles multiple files", function()
      local multi_file_diagnosis = {
         ["file://" .. path.abspath("test/a.lua")] = {
            {
               code = "unused-local",
               message = "Unused",
               range = {
                  start = { line = 0, character = 0 },
                  ["end"] = { character = 5 },
               },
               severity = 2,
            },
         },
         ["file://" .. path.abspath("test/b.lua")] = {
            {
               code = "undefined-global",
               message = "Undefined",
               range = {
                  start = { line = 0, character = 0 },
                  ["end"] = { character = 5 },
               },
               severity = 1,
            },
         },
      }
      local _, stats = llscheck.generate_report(multi_file_diagnosis)
      assert.are_equal(2, stats.total)
      assert.are_equal(2, stats.files)
   end)
end)
