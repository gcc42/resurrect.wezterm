-- Fake Mux API for testing
-- Provides behavioral fakes with builder pattern for workspace/window/tab/pane

local mux = {}

--------------------------------------------------------------------------------
-- Internal ID generators
--------------------------------------------------------------------------------

local next_pane_id = 1
local next_tab_id = 1
local next_window_id = 1

local function gen_pane_id()
    local id = next_pane_id
    next_pane_id = next_pane_id + 1
    return id
end

local function gen_tab_id()
    local id = next_tab_id
    next_tab_id = next_tab_id + 1
    return id
end

local function gen_window_id()
    local id = next_window_id
    next_window_id = next_window_id + 1
    return id
end

--------------------------------------------------------------------------------
-- Domain Registry
--------------------------------------------------------------------------------

local domains = {
    ["local"] = { name = "local", spawnable = true },
}

function mux.get_domain(name)
    local domain = domains[name]
    if domain then
        return {
            name = domain.name,
            is_spawnable = function() return domain.spawnable end,
        }
    end
    -- Default: unknown domains are spawnable
    return {
        name = name,
        is_spawnable = function() return true end,
    }
end

function mux.set_domain_spawnable(name, spawnable)
    domains[name] = { name = name, spawnable = spawnable }
end

--------------------------------------------------------------------------------
-- FakePane
--------------------------------------------------------------------------------

---@class FakePane
---@field _id number
---@field left number
---@field top number
---@field width number
---@field height number
---@field cwd string
---@field domain string
---@field text string[]
---@field is_active boolean
---@field is_zoomed boolean
---@field _process table?
---@field _alt_screen boolean
---@field _splits FakePane[]
---@field _tab FakeTab?
local FakePane = {}
FakePane.__index = FakePane

function FakePane.new(opts)
    opts = opts or {}
    local self = setmetatable({}, FakePane)
    self._id = gen_pane_id()
    self.left = opts.left or 0
    self.top = opts.top or 0
    self.width = opts.width or 160
    self.height = opts.height or 48
    self.cwd = opts.cwd or "/home/user"
    self.domain = opts.domain or "local"
    self.text = opts.text and { opts.text } or {}
    self.is_active = opts.is_active or false
    self.is_zoomed = opts.is_zoomed or false
    self._process = opts.process or nil
    self._alt_screen = opts.alt_screen or false
    self._splits = {}
    self._tab = nil
    return self
end

function FakePane:pane_id()
    return self._id
end

function FakePane:get_domain_name()
    return self.domain
end

function FakePane:get_current_working_dir()
    if not self.cwd or self.cwd == "" then
        return nil
    end
    return { file_path = self.cwd }
end

function FakePane:get_lines_as_escapes(nlines)
    -- Return scrollback as escape sequences
    local lines = {}
    for i = 1, math.min(nlines or #self.text, #self.text) do
        lines[#lines + 1] = self.text[i]
    end
    return table.concat(lines, "\r\n")
end

function FakePane:is_alt_screen_active()
    return self._alt_screen
end

function FakePane:get_foreground_process_info()
    return self._process
end

function FakePane:get_dimensions()
    return { scrollback_rows = #self.text, cols = self.width, rows = self.height }
end

-- Split creates a new pane and tracks it
function FakePane:split(args)
    args = args or {}
    local direction = args.direction or "Right"
    local size = args.size

    local new_pane = FakePane.new({
        cwd = args.cwd or self.cwd,
        domain = args.domain and args.domain.DomainName or self.domain,
    })

    -- Calculate geometry based on split direction
    if direction == "Right" then
        -- Horizontal split: new pane to the right
        local split_width = size and math.floor(self.width * size) or math.floor(self.width / 2)
        new_pane.left = self.left + self.width - split_width + 1
        new_pane.top = self.top
        new_pane.width = split_width
        new_pane.height = self.height
        self.width = self.width - split_width - 1
    elseif direction == "Bottom" then
        -- Vertical split: new pane below
        local split_height = size and math.floor(self.height * size) or math.floor(self.height / 2)
        new_pane.left = self.left
        new_pane.top = self.top + self.height - split_height + 1
        new_pane.width = self.width
        new_pane.height = split_height
        self.height = self.height - split_height - 1
    end

    table.insert(self._splits, new_pane)

    -- Add to tab's pane list if we have a reference
    if self._tab then
        new_pane._tab = self._tab
        table.insert(self._tab._panes, new_pane)
    end

    return new_pane
end

function FakePane:send_text(text)
    table.insert(self.text, text)
end

function FakePane:inject_output(text)
    table.insert(self.text, text)
end

function FakePane:activate()
    -- Deactivate other panes in the same tab
    if self._tab then
        for _, pane in ipairs(self._tab._panes) do
            pane.is_active = false
        end
    end
    self.is_active = true
end

function FakePane:tab()
    return self._tab
end

function FakePane:get_lines()
    return table.concat(self.text, "\n")
end

--------------------------------------------------------------------------------
-- FakeTab
--------------------------------------------------------------------------------

---@class FakeTab
---@field _id number
---@field _title string
---@field _panes FakePane[]
---@field _active_pane FakePane?
---@field _window FakeWindow?
---@field _is_zoomed boolean
local FakeTab = {}
FakeTab.__index = FakeTab

function FakeTab.new(opts)
    opts = opts or {}
    local self = setmetatable({}, FakeTab)
    self._id = gen_tab_id()
    self._title = opts.title or ""
    self._panes = {}
    self._active_pane = nil
    self._window = nil
    self._is_zoomed = false
    return self
end

function FakeTab:tab_id()
    return self._id
end

function FakeTab:get_title()
    return self._title
end

function FakeTab:set_title(title)
    self._title = title
end

function FakeTab:panes()
    return self._panes
end

function FakeTab:panes_with_info()
    local result = {}
    for _, pane in ipairs(self._panes) do
        result[#result + 1] = {
            pane = pane, is_active = pane == self._active_pane or pane.is_active, is_zoomed = pane.is_zoomed,
            left = pane.left, top = pane.top, width = pane.width, height = pane.height,
        }
    end
    return result
end

function FakeTab:active_pane()
    return self._active_pane or self._panes[1]
end

function FakeTab:get_size()
    -- Compute from pane dimensions
    local max_width, max_height = 0, 0
    for _, p in ipairs(self._panes) do
        max_width = math.max(max_width, p.left + p.width)
        max_height = math.max(max_height, p.top + p.height)
    end
    return { cols = max_width, rows = max_height, pixel_width = max_width * 10, pixel_height = max_height * 20 }
end

function FakeTab:window()
    return self._window
end

function FakeTab:activate()
    if self._window then
        self._window._active_tab = self
    end
end

function FakeTab:set_zoomed(zoomed)
    self._is_zoomed = zoomed
    -- Set zoomed on active pane
    if self._active_pane then
        self._active_pane.is_zoomed = zoomed
    end
end

-- Internal: add a pane to the tab
function FakeTab:_add_pane(pane)
    pane._tab = self
    table.insert(self._panes, pane)
    if not self._active_pane then
        self._active_pane = pane
        pane.is_active = true
    end
end

--------------------------------------------------------------------------------
-- FakeWindow
--------------------------------------------------------------------------------

---@class FakeWindow
---@field _id number
---@field _title string
---@field _workspace string
---@field _tabs FakeTab[]
---@field _active_tab FakeTab?
---@field _gui_window FakeGuiWindow?
local FakeWindow = {}
FakeWindow.__index = FakeWindow

function FakeWindow.new(opts)
    opts = opts or {}
    local self = setmetatable({}, FakeWindow)
    self._id = gen_window_id()
    self._title = opts.title or ""
    self._workspace = opts.workspace or "default"
    self._tabs = {}
    self._active_tab = nil
    self._gui_window = nil
    return self
end

function FakeWindow:window_id()
    return self._id
end

function FakeWindow:get_title()
    return self._title
end

function FakeWindow:set_title(title)
    self._title = title
end

function FakeWindow:get_workspace()
    return self._workspace
end

function FakeWindow:tabs()
    return self._tabs
end

function FakeWindow:tabs_with_info()
    local result = {}
    for _, tab in ipairs(self._tabs) do
        result[#result + 1] = { tab = tab, is_active = tab == self._active_tab }
    end
    return result
end

function FakeWindow:active_tab()
    return self._active_tab or self._tabs[1]
end

function FakeWindow:active_pane()
    local tab = self:active_tab()
    return tab and tab:active_pane()
end

function FakeWindow:spawn_tab(args)
    args = args or {}
    local tab = FakeTab.new({ title = args.title or "" })
    local pane = FakePane.new({
        cwd = args.cwd,
        domain = args.domain and args.domain.DomainName or "local",
    })
    tab:_add_pane(pane)
    tab._window = self
    table.insert(self._tabs, tab)
    if not self._active_tab then
        self._active_tab = tab
    end
    return tab, pane, self
end

function FakeWindow:gui_window()
    if not self._gui_window then
        self._gui_window = FakeGuiWindow.new(self)
    end
    return self._gui_window
end

-- Internal: add a tab to the window
function FakeWindow:_add_tab(tab)
    tab._window = self
    table.insert(self._tabs, tab)
    if not self._active_tab then
        self._active_tab = tab
    end
end

--------------------------------------------------------------------------------
-- FakeGuiWindow (for perform_action and set_inner_size)
--------------------------------------------------------------------------------

---@class FakeGuiWindow
---@field _mux_window FakeWindow
---@field _inner_width number
---@field _inner_height number
---@field _performed_actions table[]
local FakeGuiWindow = {}
FakeGuiWindow.__index = FakeGuiWindow

function FakeGuiWindow.new(mux_window)
    local self = setmetatable({}, FakeGuiWindow)
    self._mux_window = mux_window
    self._inner_width = 1600
    self._inner_height = 960
    self._performed_actions = {}
    return self
end

function FakeGuiWindow:set_inner_size(width, height)
    self._inner_width = width
    self._inner_height = height
end

function FakeGuiWindow:perform_action(action, pane)
    table.insert(self._performed_actions, { action = action, pane = pane })
end

function FakeGuiWindow:is_focused()
    return true
end

--------------------------------------------------------------------------------
-- Builder Pattern
--------------------------------------------------------------------------------

---@class WorkspaceBuilder
---@field _name string
---@field _windows WindowBuilder[]
---@field _current_window WindowBuilder?
local WorkspaceBuilder = {}
WorkspaceBuilder.__index = WorkspaceBuilder

---@class WindowBuilder
---@field _title string
---@field _tabs TabBuilder[]
---@field _current_tab TabBuilder?
---@field _workspace_builder WorkspaceBuilder
local WindowBuilder = {}
WindowBuilder.__index = WindowBuilder

---@class TabBuilder
---@field _title string
---@field _panes PaneConfig[]
---@field _window_builder WindowBuilder
local TabBuilder = {}
TabBuilder.__index = TabBuilder

---@alias PaneConfig {left: number, top: number, width: number, height: number, cwd: string, domain: string?, text: string?, is_active: boolean?, is_zoomed: boolean?, process: table?, alt_screen: boolean?}

-- WorkspaceBuilder methods

function WorkspaceBuilder.new(name)
    local self = setmetatable({}, WorkspaceBuilder)
    self._name = name or "default"
    self._windows = {}
    self._current_window = nil
    return self
end

function WorkspaceBuilder:window(title)
    local win_builder = WindowBuilder.new(title, self)
    table.insert(self._windows, win_builder)
    self._current_window = win_builder
    return win_builder
end

function WorkspaceBuilder:build()
    local windows = {}
    for _, win_builder in ipairs(self._windows) do
        local window = win_builder:_build(self._name)
        table.insert(windows, window)
    end
    return {
        name = self._name,
        windows = windows,
    }
end

-- WindowBuilder methods

function WindowBuilder.new(title, workspace_builder)
    local self = setmetatable({}, WindowBuilder)
    self._title = title or ""
    self._tabs = {}
    self._current_tab = nil
    self._workspace_builder = workspace_builder
    return self
end

function WindowBuilder:tab(title)
    local tab_builder = TabBuilder.new(title, self)
    table.insert(self._tabs, tab_builder)
    self._current_tab = tab_builder
    return tab_builder
end

function WindowBuilder:window(title)
    -- Delegate to workspace builder to add another window
    return self._workspace_builder:window(title)
end

function WindowBuilder:build()
    return self._workspace_builder:build()
end

function WindowBuilder:_build(workspace_name)
    local window = FakeWindow.new({
        title = self._title,
        workspace = workspace_name,
    })

    for _, tab_builder in ipairs(self._tabs) do
        local tab = tab_builder:_build()
        window:_add_tab(tab)
    end

    return window
end

-- TabBuilder methods

function TabBuilder.new(title, window_builder)
    local self = setmetatable({}, TabBuilder)
    self._title = title or ""
    self._panes = {}
    self._window_builder = window_builder
    return self
end

function TabBuilder:pane(config)
    config = config or {}
    config.is_first = #self._panes == 0
    table.insert(self._panes, { type = "pane", config = config })
    return self
end

function TabBuilder:hsplit(config)
    config = config or {}
    config.split_direction = "Right"
    table.insert(self._panes, { type = "split", config = config })
    return self
end

function TabBuilder:vsplit(config)
    config = config or {}
    config.split_direction = "Bottom"
    table.insert(self._panes, { type = "split", config = config })
    return self
end

function TabBuilder:tab(title)
    return self._window_builder:tab(title)
end

function TabBuilder:window(title)
    return self._window_builder:window(title)
end

function TabBuilder:build()
    return self._window_builder:build()
end

function TabBuilder:_build()
    local tab = FakeTab.new({ title = self._title })
    local active_pane = nil

    for _, pane_spec in ipairs(self._panes) do
        local config = pane_spec.config
        local pane

        if pane_spec.type == "pane" or pane_spec.config.is_first then
            -- Create initial pane with explicit geometry
            pane = FakePane.new({
                left = config.left or 0,
                top = config.top or 0,
                width = config.width or 160,
                height = config.height or 48,
                cwd = config.cwd or "/home/user",
                domain = config.domain or "local",
                text = config.text,
                is_active = config.is_active,
                is_zoomed = config.is_zoomed,
                process = config.process,
                alt_screen = config.alt_screen,
            })
            tab:_add_pane(pane)
        else
            -- Split from the last pane in the tab
            local parent = tab._panes[#tab._panes]
            pane = FakePane.new({
                left = config.left or 0,
                top = config.top or 0,
                width = config.width or 80,
                height = config.height or 48,
                cwd = config.cwd or parent.cwd,
                domain = config.domain or parent.domain,
                text = config.text,
                is_active = config.is_active,
                is_zoomed = config.is_zoomed,
                process = config.process,
                alt_screen = config.alt_screen,
            })
            pane._tab = tab
            table.insert(tab._panes, pane)
        end

        if config.is_active then
            active_pane = pane
        end
    end

    -- Set active pane
    if active_pane then
        tab._active_pane = active_pane
    elseif #tab._panes > 0 then
        tab._active_pane = tab._panes[1]
        tab._panes[1].is_active = true
    end

    return tab
end

--------------------------------------------------------------------------------
-- Mux State Management
--------------------------------------------------------------------------------

local active_workspace = "default"
local workspaces = {}
local all_windows = {}

function mux.reset()
    active_workspace = "default"
    workspaces = {}
    all_windows = {}
    domains = {
        ["local"] = { name = "local", spawnable = true },
    }
    -- Reset ID generators
    next_pane_id = 1
    next_tab_id = 1
    next_window_id = 1
end

function mux.get_active_workspace()
    return active_workspace
end

function mux.set_active(workspace_data)
    if type(workspace_data) == "string" then
        active_workspace = workspace_data
    elseif workspace_data and workspace_data.name then
        active_workspace = workspace_data.name
        workspaces[workspace_data.name] = workspace_data
        -- Add windows to all_windows
        for _, win in ipairs(workspace_data.windows or {}) do
            all_windows[#all_windows + 1] = win
        end
    end
end

function mux.all_windows()
    return all_windows
end

function mux.spawn_window(args)
    args = args or {}
    local workspace_name = args.workspace or active_workspace

    local window = FakeWindow.new({
        workspace = workspace_name,
    })

    local tab = FakeTab.new({})
    local pane = FakePane.new({
        cwd = args.cwd,
        width = args.width or 160,
        height = args.height or 48,
    })
    tab:_add_pane(pane)
    window:_add_tab(tab)

    all_windows[#all_windows + 1] = window

    return tab, pane, window
end

--------------------------------------------------------------------------------
-- Builder Entry Point
--------------------------------------------------------------------------------

function mux.workspace(name)
    return WorkspaceBuilder.new(name)
end

-- Create workspace from fixture data
function mux.from_fixture(fixture)
    -- Simple fixture format: just panes with geometry
    local builder = mux.workspace("fixture")
        :window("main")
            :tab("tab")

    for i, pane_config in ipairs(fixture.panes or {}) do
        if i == 1 then
            builder:pane(pane_config)
        else
            -- Determine split direction based on position
            if pane_config.left > 0 and pane_config.top == 0 then
                builder:hsplit(pane_config)
            else
                builder:vsplit(pane_config)
            end
        end
    end

    return builder:build()
end

return mux
