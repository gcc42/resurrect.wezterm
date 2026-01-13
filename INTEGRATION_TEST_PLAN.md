# Integration Test Implementation Plan

## Overview

| What | Details |
|------|---------|
| Goal | Add integration tests that run against real WezTerm mux-server |
| Location | `test/integration/` |
| Runner | WSL with isolated `WEZTERM_UNIX_SOCKET` |
| CI | GitHub Actions on Ubuntu |

## Directory Structure

```
test/integration/
├── init.lua           # Entry point
├── runner.lua         # Test harness (test/assert functions)
├── helpers.lua        # WezTerm CLI wrappers
├── cases/
│   ├── 01_smoke.lua         # Basic mux connectivity
│   ├── 02_save_restore.lua  # Core save/restore
│   └── 03_workspace.lua     # Workspace naming
└── run.sh             # Shell wrapper script
```

---

## Step 1: Create Directory Structure

**Command:**
```bash
mkdir -p test/integration/cases
```

---

## Step 2: Create Shell Runner

**File:** `test/integration/run.sh`

```bash
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Isolated socket (won't affect other WezTerm instances)
export WEZTERM_UNIX_SOCKET="/tmp/resurrect-test-$$.sock"

cleanup() {
    echo "Cleaning up..."
    pkill -f "wezterm-mux-server.*$WEZTERM_UNIX_SOCKET" 2>/dev/null || true
    rm -f "$WEZTERM_UNIX_SOCKET"
}
trap cleanup EXIT

echo "=== Starting isolated mux-server ==="
echo "Socket: $WEZTERM_UNIX_SOCKET"
wezterm-mux-server --daemonize
sleep 2

echo "=== Running integration tests ==="
wezterm cli spawn --domain-name local -- lua "$SCRIPT_DIR/init.lua"

echo "=== Tests complete ==="
```

---

## Step 3: Create Test Runner

**File:** `test/integration/runner.lua`

```lua
-- Test harness with simple test/assert API
local M = {}

M.results = { passed = 0, failed = 0, skipped = 0, errors = {} }
M.current_test = nil

function M.test(name, fn)
    M.current_test = name
    io.write("  " .. name .. " ... ")
    io.flush()

    local ok, err = pcall(fn)

    if ok then
        M.results.passed = M.results.passed + 1
        print("✓")
    else
        M.results.failed = M.results.failed + 1
        print("✗")
        print("    Error: " .. tostring(err))
        table.insert(M.results.errors, { name = name, err = tostring(err) })
    end

    M.current_test = nil
end

function M.skip(name, reason)
    M.results.skipped = M.results.skipped + 1
    print("  " .. name .. " ... SKIPPED" .. (reason and (" (" .. reason .. ")") or ""))
end

function M.eq(actual, expected, msg)
    if actual ~= expected then
        error(string.format("%s: expected [%s], got [%s]",
            msg or "equality check", tostring(expected), tostring(actual)))
    end
end

function M.truthy(value, msg)
    if not value then
        error(msg or "expected truthy value, got " .. tostring(value))
    end
end

function M.gt(actual, expected, msg)
    if not (actual > expected) then
        error(string.format("%s: expected > %s, got %s",
            msg or "greater than check", tostring(expected), tostring(actual)))
    end
end

function M.summary()
    print("")
    print(string.format("Results: %d passed, %d failed, %d skipped",
        M.results.passed, M.results.failed, M.results.skipped))

    if #M.results.errors > 0 then
        print("\nFailures:")
        for _, e in ipairs(M.results.errors) do
            print("  - " .. e.name .. ": " .. e.err)
        end
    end

    return M.results.failed == 0
end

return M
```

---

## Step 4: Create Helpers

**File:** `test/integration/helpers.lua`

```lua
local wezterm = require("wezterm")
local mux = wezterm.mux

local M = {}

-- Create window with optional splits
function M.create_window(opts)
    opts = opts or {}
    local tab, pane, window = mux.spawn_window({ cwd = opts.cwd or "/tmp" })

    if opts.hsplit then
        pane:split({ direction = "Right", cwd = opts.hsplit })
    end
    if opts.vsplit then
        pane:split({ direction = "Bottom", cwd = opts.vsplit })
    end

    return window, tab, pane
end

-- Count panes in a tab
function M.pane_count(tab)
    return #tab:panes()
end

-- Get all pane cwds in a tab
function M.get_cwds(tab)
    local cwds = {}
    for _, pane in ipairs(tab:panes()) do
        local cwd = pane:get_current_working_dir()
        table.insert(cwds, cwd and cwd.file_path or "unknown")
    end
    return cwds
end

-- Close all windows
function M.close_all()
    for _, win in ipairs(mux.all_windows()) do
        for _, tab in ipairs(win:tabs()) do
            for _, pane in ipairs(tab:panes()) do
                pane:close()
            end
        end
    end
end

-- Wait for shell to settle (cwd to propagate)
function M.settle()
    wezterm.sleep_ms(200)
end

return M
```

---

## Step 5: Create Smoke Tests

**File:** `test/integration/cases/01_smoke.lua`

```lua
local runner = require("integration.runner")
local wezterm = require("wezterm")
local mux = wezterm.mux

print("\n[Smoke Tests]")

runner.test("wezterm module loads", function()
    runner.truthy(wezterm, "wezterm not loaded")
    runner.truthy(wezterm.mux, "wezterm.mux not available")
end)

runner.test("can list windows", function()
    local windows = mux.all_windows()
    runner.truthy(type(windows) == "table", "all_windows returns table")
end)

runner.test("can spawn window", function()
    local tab, pane, window = mux.spawn_window({ cwd = "/tmp" })
    runner.truthy(window, "window created")
    runner.truthy(tab, "tab created")
    runner.truthy(pane, "pane created")
end)

runner.test("can split pane", function()
    local tab, pane, window = mux.spawn_window({ cwd = "/tmp" })
    local new_pane = pane:split({ direction = "Right" })
    runner.truthy(new_pane, "split created")
    runner.eq(#tab:panes(), 2, "tab has 2 panes")
end)

runner.test("resurrect module loads", function()
    local ok, res = pcall(require, "resurrect")
    runner.truthy(ok, "resurrect failed to load: " .. tostring(res))
    runner.truthy(res.workspace_state, "workspace_state missing")
    runner.truthy(res.state_manager, "state_manager missing")
end)
```

---

## Step 6: Create Save/Restore Tests

**File:** `test/integration/cases/02_save_restore.lua`

```lua
local runner = require("integration.runner")
local helpers = require("integration.helpers")
local wezterm = require("wezterm")
local mux = wezterm.mux
local resurrect = require("resurrect")

print("\n[Save/Restore Tests]")

runner.test("save captures single pane", function()
    helpers.close_all()
    local window, tab = helpers.create_window({ cwd = "/tmp" })
    helpers.settle()

    local state = resurrect.workspace_state.get_workspace_state()

    runner.eq(#state.window_states, 1, "window count")
    runner.eq(#state.window_states[1].tabs, 1, "tab count")
    runner.truthy(state.window_states[1].tabs[1].pane_tree, "pane_tree exists")
end)

runner.test("save captures horizontal split", function()
    helpers.close_all()
    local window, tab = helpers.create_window({ cwd = "/tmp", hsplit = "/var" })
    helpers.settle()

    local state = resurrect.workspace_state.get_workspace_state()
    local tree = state.window_states[1].tabs[1].pane_tree

    runner.truthy(tree.right, "right split captured")
end)

runner.test("restore recreates split", function()
    helpers.close_all()

    -- Create and save
    local window1, tab1 = helpers.create_window({ cwd = "/tmp", hsplit = "/var" })
    helpers.settle()
    local state = resurrect.workspace_state.get_workspace_state()
    local before_count = helpers.pane_count(tab1)

    -- Restore into new window
    local window2, tab2 = helpers.create_window({})
    resurrect.workspace_state.restore_workspace(state, {
        window = window2,
        close_open_tabs = true,
    })
    helpers.settle()

    local after_count = helpers.pane_count(window2:active_tab())
    runner.eq(after_count, before_count, "pane count matches")
end)
```

---

## Step 7: Create Workspace Tests

**File:** `test/integration/cases/03_workspace.lua`

```lua
local runner = require("integration.runner")
local helpers = require("integration.helpers")
local wezterm = require("wezterm")
local mux = wezterm.mux
local resurrect = require("resurrect")

print("\n[Workspace Tests]")

runner.test("save captures workspace name", function()
    mux.rename_workspace(mux.get_active_workspace(), "test-workspace")

    local state = resurrect.workspace_state.get_workspace_state()

    runner.eq(state.workspace, "test-workspace", "workspace name")
end)

runner.test("restore renames workspace", function()
    helpers.close_all()

    -- Save with specific name
    mux.rename_workspace(mux.get_active_workspace(), "original-name")
    local window, tab = helpers.create_window({})
    local state = resurrect.workspace_state.get_workspace_state()

    -- Change name
    mux.rename_workspace(mux.get_active_workspace(), "changed-name")
    runner.eq(mux.get_active_workspace(), "changed-name", "name changed")

    -- Restore should rename back
    resurrect.workspace_state.restore_workspace(state, { window = window })

    runner.eq(mux.get_active_workspace(), "original-name", "name restored")
end)
```

---

## Step 8: Create Entry Point

**File:** `test/integration/init.lua`

```lua
#!/usr/bin/env lua
-- Integration test entry point
-- Run via: wezterm cli spawn -- lua test/integration/init.lua

-- Setup paths
local script_path = debug.getinfo(1, "S").source:match("@(.*/)")
local plugin_path = script_path:match("(.*/plugins/resurrect/)")
    or script_path:gsub("/test/integration/$", "/")

package.path = table.concat({
    plugin_path .. "plugin/?.lua",
    plugin_path .. "plugin/?/init.lua",
    plugin_path .. "test/integration/?.lua",
    plugin_path .. "test/integration/?/init.lua",
    package.path,
}, ";")

-- Load test framework
local runner = require("runner")

print("==========================================")
print("  Resurrect Integration Tests")
print("==========================================")

-- Run test suites
dofile(script_path .. "cases/01_smoke.lua")
dofile(script_path .. "cases/02_save_restore.lua")
dofile(script_path .. "cases/03_workspace.lua")

-- Exit with status
local success = runner.summary()
os.exit(success and 0 or 1)
```

---

## Step 9: Update Makefile

Add to existing Makefile:

```makefile
# Integration tests (requires wezterm)
test-integration:
	@chmod +x test/integration/run.sh
	@./test/integration/run.sh

# All tests
test-all: test test-integration
```

---

## Step 10: Validate in WSL

```bash
cd ~/.config/wezterm/plugins/resurrect
chmod +x test/integration/run.sh
./test/integration/run.sh
```

**Expected output:**
```
=== Starting isolated mux-server ===
Socket: /tmp/resurrect-test-12345.sock
=== Running integration tests ===
==========================================
  Resurrect Integration Tests
==========================================

[Smoke Tests]
  wezterm module loads ... ✓
  can list windows ... ✓
  can spawn window ... ✓
  can split pane ... ✓
  resurrect module loads ... ✓

[Save/Restore Tests]
  save captures single pane ... ✓
  save captures horizontal split ... ✓
  restore recreates split ... ✓

[Workspace Tests]
  save captures workspace name ... ✓
  restore renames workspace ... ✓

Results: 10 passed, 0 failed, 0 skipped
=== Tests complete ===
```

---

## Step 11: Add GitHub Actions CI

**File:** `.github/workflows/test.yml`

```yaml
name: Tests
on: [push, pull_request]

jobs:
  unit-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install Lua
        run: sudo apt-get update && sudo apt-get install -y lua5.4
      - name: Run unit tests
        run: make test

  integration-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install WezTerm
        run: |
          curl -fsSL https://apt.fury.io/wez/gpg.key | sudo gpg --dearmor -o /usr/share/keyrings/wezterm-fury.gpg
          echo 'deb [signed-by=/usr/share/keyrings/wezterm-fury.gpg] https://apt.fury.io/wez/ * *' | sudo tee /etc/apt/sources.list.d/wezterm.list
          sudo apt-get update && sudo apt-get install -y wezterm
      - name: Run integration tests
        run: make test-integration
```

---

## Success Criteria

| Check | Expected |
|-------|----------|
| WSL mux-server starts isolated | ✓ |
| Windows WezTerm unaffected | ✓ |
| Smoke tests pass | ✓ |
| Save/restore tests pass | ✓ |
| Workspace tests pass | ✓ |
| CI runs on push | ✓ |
