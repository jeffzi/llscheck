-- Demo file with intentional errors to showcase llscheck output

-- Unused local variables (unused-local warning)
local unused_var = 42
local another_unused = "hello"
local _, also_unused = pcall(function() end)

-- Undefined globals (undefined-global error)
print(undefined_variable)
some_undefined_function()
x = undefined_global + 1

-- Duplicate local definitions (duplicate-set-field)
local duplicate = 1
local duplicate = 2

-- Unused functions (unused-function warning)
local function unused_function()
    return "never called"
end

-- Type mismatches
local number_var = 42
number_var = "now a string" -- type mismatch

-- Missing self parameter (need-check-nil)
local obj = {}
function obj.method()
    print(self.value) -- self is undefined
end

-- Unreachable code after return (unreachable-code)
local function unreachable_example()
    return true
    print("this is unreachable")
end

-- Lowercase global (lowercase-global)
globalVar = "should use local"

-- Deprecated code patterns
local a = 1
local b = 2
a, b = b, a  -- this is fine, but let's add issues

-- Empty block
if true then
end

-- Redundant return
local function redundant()
    return nil
end

-- Undefined field access
local tbl = { foo = 1 }
print(tbl.bar) -- bar is undefined

-- Missing return value
---@return number
local function should_return_number()
    -- forgot to return
end

-- Wrong number of arguments
string.format("%s %s", "only one arg")

-- Invalid escape sequence
local bad_string = "hello\z world"

-- Assign to constant (if using const annotation)
---@type string
local const_val = "constant"
const_val = "changed"

-- Trailing whitespace and formatting issues (if configured)
local formatted   =    "badly formatted"

-- Circular require (can't demo in single file)

-- Call non-function
local not_a_function = 42
not_a_function()

-- Index nil value
local nil_var = nil
print(nil_var.field)

-- Cast errors
---@type integer
local int_val = 3.14

-- Param type mismatch
---@param x integer
local function takes_int(x)
    return x + 1
end
takes_int("not an int")

-- Missing required parameter
---@param required string
---@param optional? string
local function has_required(required, optional)
    print(required, optional)
end
has_required()

-- Duplicate key in table
local dup_table = {
    key = 1,
    key = 2,
}

-- Comparison with incompatible types
local num = 42
local str = "42"
if num == str then -- comparing number to string
    print("equal")
end

print("End of error demo")
