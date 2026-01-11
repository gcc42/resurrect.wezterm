# Resurrect.wezterm Refactoring Plan

## Goal
Separate **functional core** (pure, testable) from **imperative shell** (I/O, WezTerm API).

## Constraints

- **Pure refactor**: No functionality changes
- **Preserve events**: They are documented public API
- **Tests must pass**: All 151 tests + type checks + lint at each step
- **Type safety**: Maintain strict LuaLS type annotations

---

## Current Infrastructure

### Quality Gates (must pass at each step)
```bash
make all  # Runs: fix → lint → check → test
```

| Gate | Tool | Config |
|------|------|--------|
| Format | stylua | Default |
| Lint | luacheck | `.luacheckrc` |
| Types | lua-language-server | `.luarc.json` |
| Tests | lust | `make test` |

### Type Definitions
```
plugin/resurrect/types/
├── wezterm.lua    # WezTerm API stubs (Pane, MuxTab, MuxWindow, etc.)
├── mux.lua        # Mux domain types
└── resurrect.lua  # Internal types (WorkspaceState, PaneTree, RestoreOptions, etc.)
```

Key types already defined:
- `WorkspaceState`, `WindowState`, `TabState`, `PaneTree`
- `RestoreOptions`, `SplitCommand`
- `RawPaneData` (for extracted pane data - ready for Phase 2)

---

## Current Architecture (Problem)

```
┌─────────────────────────────────────────────────────────────────┐
│  Everything mixed: API calls + logic + I/O + events in same fn  │
│                                                                 │
│  workspace_state ──► window_state ──► tab_state ──► pane_tree  │
│       ↓                   ↓              ↓             ↓        │
│   wezterm.mux        wezterm.mux    wezterm.mux   pane:get_*()  │
└─────────────────────────────────────────────────────────────────┘
```

### Current Pure vs Impure Analysis

| File | Pure Functions | Impure (WezTerm API) |
|------|---------------|---------------------|
| `pane_tree.lua` | `compare_pane_by_coord`, `is_right`, `is_bottom`, `pop_connected_*`, `map`, `fold` | `insert_panes` (main problem) |
| `state_manager.lua` | `sanitize_filename` ✓ | `save_state`, `load_state`, `periodic_save` |
| `tab_state.lua` | `make_splits` (partial) | `get_tab_state`, `restore_tab` |
| `window_state.lua` | - | All impure |
| `workspace_state.lua` | - | All impure |
| `file_io.lua` | `sanitize_json` | `write_file`, `read_file`, `load_json` |

---

## Target Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      IMPERATIVE SHELL                            │
│            (WezTerm API, File I/O, Events, UI)                  │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐    ┌──────────────────────────────────────┐    │
│  │  init.lua   │    │  shell/api.lua                       │    │
│  │  (entry)    │    │  - extract_pane(), extract_tab()     │    │
│  └─────────────┘    │  - extract_window(), get_workspace() │    │
│                     └──────────────────────────────────────┘    │
│                                    │                            │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  shell/io.lua                                            │   │
│  │  - Workflow orchestration (capture → save, load → restore)│  │
│  │  - File I/O, Event emission, Fuzzy loader UI             │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                    │                            │
└────────────────────────────────────┼────────────────────────────┘
                                     │
                                     ▼
┌─────────────────────────────────────────────────────────────────┐
│                      FUNCTIONAL CORE                             │
│         (Pure functions, no side effects, no wezterm require)   │
├─────────────────────────────────────────────────────────────────┤
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  core/pane_tree.lua                                      │   │
│  │  - build(raw_panes) → tree, warnings                     │   │
│  │  - map(tree, fn), fold(tree, init, fn)                   │   │
│  │  - plan_splits(tree) → SplitCommand[]                    │   │
│  │  - sanitize_filename(name) → safe_name                   │   │
│  │  - build_workspace/window/tab(raw_data) → state          │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Refactoring Phases

### Phase 1: Create `shell/api.lua` (HIGHEST PRIORITY)

**Goal**: Extract WezTerm API calls from tree building.

**Create** `plugin/resurrect/shell/api.lua`:
```lua
local wezterm = require("wezterm")

---@class ShellApi
local M = {}

---Extract raw data from a WezTerm pane (IMPURE - all API calls here)
---@param pane Pane
---@param max_lines number
---@return RawPaneData
function M.extract_pane(pane, max_lines)
    local domain = pane:get_domain_name()
    local cwd_obj = pane:get_current_working_dir()
    return {
        left = pane.left,
        top = pane.top,
        width = pane.width,
        height = pane.height,
        domain = domain,
        is_spawnable = wezterm.mux.get_domain(domain):is_spawnable(),
        cwd = cwd_obj and cwd_obj.file_path or "",
        text = pane:get_lines_as_escapes(max_lines or 2000),
        process = pane:get_foreground_process_info(),
        is_active = pane.is_active,
        is_zoomed = pane.is_zoomed,
        alt_screen_active = pane:is_alt_screen_active(),
    }
end

---Extract panes from tab
---@param pane_infos PaneInformation[]
---@param max_lines number
---@return RawPaneData[]
function M.extract_panes(pane_infos, max_lines)
    local result = {}
    for _, info in ipairs(pane_infos) do
        local raw = M.extract_pane(info.pane, max_lines)
        raw.left = info.left
        raw.top = info.top
        raw.width = info.width
        raw.height = info.height
        raw.is_active = info.is_active
        raw.is_zoomed = info.is_zoomed
        result[#result + 1] = raw
    end
    return result
end

---@param mux_tab MuxTab
---@param max_lines number
---@return {title: string, panes: RawPaneData[], is_active: boolean, is_zoomed: boolean}
function M.extract_tab(mux_tab, max_lines)
    return {
        title = mux_tab:get_title(),
        panes = M.extract_panes(mux_tab:panes_with_info(), max_lines),
        is_active = false,  -- Set by caller
        is_zoomed = false,  -- Set by caller
    }
end

---@param mux_win MuxWindow
---@param max_lines number
---@return {title: string, tabs: table[], size: TabSize}
function M.extract_window(mux_win, max_lines)
    local tabs = {}
    for _, tab_info in ipairs(mux_win:tabs_with_info()) do
        local tab = M.extract_tab(tab_info.tab, max_lines)
        tab.is_active = tab_info.is_active
        tabs[#tabs + 1] = tab
    end
    return {
        title = mux_win:get_title(),
        tabs = tabs,
        size = tabs[1] and tabs[1].panes[1] and {
            cols = 0, rows = 0,  -- Computed from panes
            pixel_width = 0, pixel_height = 0, dpi = 96
        } or nil
    }
end

return M
```

**Type additions** to `plugin/resurrect/types/resurrect.lua`:
```lua
---@class ShellApi
---@field extract_pane fun(pane: Pane, max_lines: number): RawPaneData
---@field extract_panes fun(pane_infos: PaneInformation[], max_lines: number): RawPaneData[]
---@field extract_tab fun(mux_tab: MuxTab, max_lines: number): table
---@field extract_window fun(mux_win: MuxWindow, max_lines: number): table
```

**Validation**:
```bash
make all  # Must pass
```

---

### Phase 2: Create `core/pane_tree.lua` (Pure Logic)

**Goal**: Pure tree building with no WezTerm dependency.

**Create** `plugin/resurrect/core/pane_tree.lua`:
```lua
-- NO wezterm require allowed!

---@class CorePaneTree
local M = {}

---Build pane tree from raw extracted data (PURE)
---@param panes RawPaneData[]
---@return PaneTree?, string[]
function M.build(panes)
    if not panes or #panes == 0 then
        return nil, {}
    end

    local warnings = {}
    table.sort(panes, M.compare_by_coord)

    local root = table.remove(panes, 1)
    if not root.is_spawnable then
        warnings[#warnings + 1] = "Domain " .. (root.domain or "unknown") .. " not spawnable"
    end

    return M.insert(root, panes, warnings), warnings
end

-- Move existing pure functions here:
-- compare_pane_by_coord, is_right, is_bottom, pop_connected_*, insert, map, fold

---Plan splits needed to restore pane tree (PURE)
---@param tree PaneTree
---@param opts {relative: boolean}
---@return SplitCommand[]
function M.plan_splits(tree, opts)
    local commands = {}
    M.fold(tree, nil, function(_, node)
        if node.right then
            commands[#commands + 1] = {
                direction = "Right",
                cwd = node.right.cwd,
                text = node.right.text,
                domain = node.right.domain,
                size = opts.relative and node.right.width / (node.width + node.right.width) or nil,
            }
        end
        if node.bottom then
            commands[#commands + 1] = {
                direction = "Bottom",
                cwd = node.bottom.cwd,
                text = node.bottom.text,
                domain = node.bottom.domain,
                size = opts.relative and node.bottom.height / (node.height + node.bottom.height) or nil,
            }
        end
    end)
    return commands
end

---Sanitize string for use as filename (PURE)
---@param name string?
---@return string
function M.sanitize_filename(name)
    -- Move from state_manager.lua
end

return M
```

**Add tests** `plugin/resurrect/test/spec/core_spec.lua`:
- Test `build()` with raw data fixtures (no mocks!)
- Test `plan_splits()` with various layouts
- Test pure functions directly

---

### Phase 3: Create `shell/io.lua` (Orchestration)

**Goal**: Single orchestrator for workflows.

**Create** `plugin/resurrect/shell/io.lua`:
```lua
local wezterm = require("wezterm")
local api = require("resurrect.shell.api")
local core = require("resurrect.core.pane_tree")

---@class ShellIO
local M = {}

M.state_dir = wezterm.config_dir .. "/resurrect/"
M.max_nlines = 2000

---Capture current workspace state
---@return WorkspaceState
function M.capture_workspace()
    local workspace = wezterm.mux.get_active_workspace()
    local raw_windows = {}
    for _, win in ipairs(wezterm.mux.all_windows()) do
        if win:get_workspace() == workspace then
            raw_windows[#raw_windows + 1] = api.extract_window(win, M.max_nlines)
        end
    end
    return core.build_workspace(workspace, raw_windows)
end

---Save state to file
---@param state WorkspaceState|WindowState|TabState
---@param name string?
---@param state_type "workspace"|"window"|"tab"
---@return boolean
function M.save(state, name, state_type)
    local filename = core.sanitize_filename(name or state.workspace or state.title)
    local path = M.state_dir .. state_type .. "/" .. filename .. ".json"

    wezterm.emit("resurrect.save.start", path)

    local file = io.open(path, "w")
    if not file then
        wezterm.emit("resurrect.error", "Failed to open: " .. path)
        return false
    end

    file:write(wezterm.json_encode(state))
    file:close()

    wezterm.emit("resurrect.save.finished", path)
    return true
end

-- ... load, restore_workspace, execute_splits, etc.

return M
```

---

### Phase 4: Update Existing Modules

**Goal**: Delegate to new modules, keep backward compatibility.

1. **`pane_tree.lua`**: Delegate to `core/pane_tree.lua` + `shell/api.lua`
2. **`tab_state.lua`**: Use `core.plan_splits()` in `make_splits()`
3. **`state_manager.lua`**: Delegate to `shell/io.lua`
4. **`init.lua`**: Keep unchanged (public API)

---

## File Structure After Refactoring

```
plugin/
├── init.lua                    # Entry point (unchanged public API)
└── resurrect/
    ├── core/
    │   └── pane_tree.lua       # ALL pure logic
    │
    ├── shell/
    │   ├── api.lua             # WezTerm data extraction
    │   └── io.lua              # File I/O, orchestration, events
    │
    ├── types/
    │   ├── wezterm.lua         # WezTerm API type stubs
    │   ├── mux.lua             # Mux types
    │   └── resurrect.lua       # Internal types
    │
    ├── test/
    │   ├── spec/
    │   │   ├── capture_spec.lua
    │   │   ├── restore_spec.lua
    │   │   ├── persistence_spec.lua
    │   │   ├── events_spec.lua
    │   │   └── core_spec.lua   # NEW: Pure function tests
    │   ├── fakes/
    │   └── fixtures/
    │
    └── [legacy modules - thin wrappers for compatibility]
        ├── pane_tree.lua
        ├── tab_state.lua
        ├── window_state.lua
        ├── workspace_state.lua
        ├── state_manager.lua
        └── file_io.lua
```

---

## Implementation Checklist

### Phase 1: shell/api.lua
- [ ] Create `plugin/resurrect/shell/api.lua`
- [ ] Add `ShellApi` type to `types/resurrect.lua`
- [ ] Add `plugin/resurrect/test/spec/api_spec.lua`
- [ ] Run `make all` - must pass

### Phase 2: core/pane_tree.lua
- [ ] Create `plugin/resurrect/core/pane_tree.lua`
- [ ] Move pure functions from `pane_tree.lua`
- [ ] Implement `build(raw_panes)` with warnings return
- [ ] Implement `plan_splits(tree, opts)`
- [ ] Move `sanitize_filename` from `state_manager.lua`
- [ ] Add `plugin/resurrect/test/spec/core_spec.lua`
- [ ] Run `make all` - must pass

### Phase 3: shell/io.lua
- [ ] Create `plugin/resurrect/shell/io.lua`
- [ ] Implement capture/save/load/restore workflows
- [ ] Preserve all event emissions
- [ ] Run `make all` - must pass

### Phase 4: Integration
- [ ] Update `pane_tree.lua` to delegate to core + shell
- [ ] Update `tab_state.lua` to use `plan_splits()`
- [ ] Update `state_manager.lua` to delegate to `shell/io.lua`
- [ ] Run `make all` - must pass
- [ ] Manual smoke test with complex layouts

---

## Type Checking Guidelines

1. **All new functions must have type annotations**:
   ```lua
   ---@param panes RawPaneData[]
   ---@return PaneTree?, string[]
   function M.build(panes)
   ```

2. **Add types to `types/resurrect.lua`** for any new classes/interfaces

3. **Run `make check`** after each file change

4. **Core module must not require wezterm** - LuaLS will catch this

5. **Use existing types**: `RawPaneData`, `SplitCommand`, `PaneTree`, etc.

---

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Public API breakage | Keep `init.lua` unchanged |
| Layout regressions | 151 tests cover many scenarios |
| Type errors | `make check` at each step |
| Windows path issues | Keep existing fix in `shell/api.lua` |
| Module load order | Core never requires shell |

---

## Estimated Effort

| Phase | Effort | Risk |
|-------|--------|------|
| Phase 1: shell/api.lua | ~4 hours | Medium |
| Phase 2: core/pane_tree.lua | ~3 hours | Low |
| Phase 3: shell/io.lua | ~4 hours | Medium |
| Phase 4: Integration | ~2 hours | Low |

**Total: ~13 hours / 2 days**
