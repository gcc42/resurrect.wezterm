-- Test runner for resurrect.wezterm plugin
-- Uses lust (https://github.com/bjornbytes/lust) for assertions
-- Run with: lua plugin/resurrect/test/init.lua

-- Setup paths
local script_dir = debug.getinfo(1, "S").source:match("@(.*/)")
-- Add paths for:
-- 1. lib/?.lua - lust test framework
-- 2. ../../?.lua - for require("resurrect.utils") pattern (plugin/resurrect/utils.lua)
-- 3. ../?.lua - for direct require("utils") pattern if needed
package.path = script_dir .. "lib/?.lua;" .. script_dir .. "../../?.lua;" .. script_dir .. "../?.lua;" .. package.path

-- Load lust test framework
local lust = require("lust")
local describe, it, expect = lust.describe, lust.it, lust.expect

-- Load WezTerm fake and inject into package.loaded
local wezterm_fake = dofile(script_dir .. "fakes/wezterm.lua")
package.loaded["wezterm"] = wezterm_fake

-- Export lust globals for test files
_G.describe = describe
_G.it = it
_G.expect = expect
_G.lust = lust
_G.before = lust.before
_G.after = lust.after
_G.wezterm = wezterm_fake

-- Reset fake state between test files
local function reset_test_state()
    wezterm_fake._test.reset()
end

-- Discover and run test files
local function run_tests()
    print("\n" .. string.char(27) .. "[36mResurrect.wezterm Test Suite" .. string.char(27) .. "[0m")
    print(string.rep("=", 50))

    -- Find test files (test_*.lua) in this directory
    local test_files = {}
    local handle = io.popen('ls "' .. script_dir .. '"test_*.lua 2>/dev/null')
    if handle then
        for file in handle:lines() do
            test_files[#test_files + 1] = file
        end
        handle:close()
    end

    -- Also check command line args for specific test files
    if #arg > 0 then
        test_files = arg
    end

    -- Run each test file
    for _, file in ipairs(test_files) do
        print(string.char(27) .. "[33m\nRunning: " .. file .. string.char(27) .. "[0m")
        reset_test_state()
        dofile(file)
    end

    -- Print summary
    print("\n" .. string.rep("-", 50))
    local color = lust.errors == 0 and string.char(27) .. "[32m" or string.char(27) .. "[31m"
    local total = lust.passes + lust.errors
    print(color .. "Tests: " .. lust.passes .. " passed, " .. lust.errors .. " failed, " .. total .. " total" .. string.char(27) .. "[0m")

    return lust.errors == 0 and 0 or 1
end

-- Run if executed directly
if arg then
    os.exit(run_tests())
end

return {
    lust = lust,
    describe = describe,
    it = it,
    expect = expect,
}
