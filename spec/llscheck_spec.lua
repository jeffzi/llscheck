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

   describe("uri_to_path", function()
      it("converts file URI to path", function()
         assert.are_equal("/test/file.lua", llscheck.uri_to_path("file:///test/file.lua"))
      end)

      it("handles windows paths", function()
         assert.are_equal("C:/test/file.lua", llscheck.uri_to_path("file:///C:/test/file.lua"))
      end)

      it("decodes percent-encoded characters", function()
         assert.are_equal(
            "/test/space file.lua",
            llscheck.uri_to_path("file:///test/space%20file.lua")
         )
      end)
   end)

   describe("compare_diagnostics", function()
      it("sorts by line number first", function()
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

      it("sorts by character position when lines are equal", function()
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

      it("sorts by severity when position is equal", function()
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
   end)

   describe("generate_report", function()
      it("generates correct stats", function()
         local _, stats = llscheck.generate_report(sample_diagnosis)
         assert.are_equal(2, stats.total)
         assert.are_equal(1, stats.files)
         assert.are_equal(1, stats[1]) -- 1 Error
         assert.are_equal(1, stats[2]) -- 1 Warning
         assert.is_nil(stats[3]) -- 0 Information
         assert.is_nil(stats[4]) -- 0 Hint
      end)

      it("generates report with no issues", function()
         local report, stats = llscheck.generate_report({})
         assert.are_equal(0, stats.total)
         assert.are_equal(0, stats.files)
         assert.matches("no problems found", report)
      end)

      it("formats diagnostic lines correctly", function()
         local report = llscheck.generate_report(sample_diagnosis)
         assert.matches("test/main%.lua:1:7%-9: unused%-local", report)
         assert.matches("test/main%.lua:2:1%-3: undefined%-global", report)
         assert.matches("Total 2: 1 Errors / 1 Warnings in 1 files", report)
      end)

      it("formats colored diagnostic lines correctly", function()
         llscheck.setup_colorize(true)
         local report = llscheck.generate_report(sample_diagnosis)

         -- Check for specific colored components
         assert.matches("\27%[34mtest/main%.lua", report) -- blue filepath
         assert.matches("\27%[33munused%-local", report) -- yellow warning
         assert.matches("\27%[31mundefined%-global", report) -- red error
         -- Verify reset codes
         assert.matches("\27%[0m", report) -- Color reset sequence
      end)
   end)

   describe("executes lua-language-server --check", function()
      local diagnosis = llscheck.check_workspace(".", "Hint")
      local report, stats = llscheck.generate_report(diagnosis)
      assert.are_equal(0, stats.total)
      assert.are_equal(0, stats.files)
      assert.matches("no problems found", report)
   end)

   describe("is executable", function()
      local llscheck_path = path.join("src", "llscheck.lua")
      assert.are_equal(0, os.execute("lua " .. llscheck_path))
   end)
end)
