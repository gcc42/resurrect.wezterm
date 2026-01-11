---@meta
-- WezTerm Mux object type definitions

---@class MuxDomain
local MuxDomain = {}

---Check if domain can spawn new panes
---@return boolean
function MuxDomain:is_spawnable() end

---Get domain name
---@return string
function MuxDomain:name() end

---@class MuxWindow
local MuxWindow = {}

---Get window title
---@return string
function MuxWindow:get_title() end

---Set window title
---@param title string
function MuxWindow:set_title(title) end

---Get workspace name
---@return string
function MuxWindow:get_workspace() end

---Get all tabs in window
---@return MuxTab[]
function MuxWindow:tabs() end

---Get tabs with metadata
---@return TabInfo[]
function MuxWindow:tabs_with_info() end

---Spawn new tab
---@param args? SpawnTabArgs
---@return MuxTab tab
---@return Pane pane
---@return MuxWindow window
function MuxWindow:spawn_tab(args) end

---Get associated GUI window
---@return GuiWindow?
function MuxWindow:gui_window() end

---Get the active tab
---@return MuxTab
function MuxWindow:active_tab() end

---Get the active pane
---@return Pane
function MuxWindow:active_pane() end

---@class SpawnTabArgs
---@field cwd? string
---@field domain? table

---@class TabInfo
---@field tab MuxTab
---@field is_active boolean

---@class MuxTab
local MuxTab = {}

---Get tab title
---@return string
function MuxTab:get_title() end

---Set tab title
---@param title string
function MuxTab:set_title(title) end

---Get tab ID
---@return number
function MuxTab:tab_id() end

---Get all panes with layout info
---@return PaneInfo[]
function MuxTab:panes_with_info() end

---Get tab size
---@return TabSize
function MuxTab:get_size() end

---Set zoomed pane
---@param zoomed boolean|Pane
function MuxTab:set_zoomed(zoomed) end

---Get all panes in this tab
---@return Pane[]
function MuxTab:panes() end

---Activate this tab
function MuxTab:activate() end

---Get the parent window
---@return MuxWindow
function MuxTab:window() end

---Get the active pane
---@return Pane
function MuxTab:active_pane() end

---@class TabSize
---@field rows number
---@field cols number
---@field pixel_width number
---@field pixel_height number
---@field dpi number

---@class PaneInfo
---@field pane Pane
---@field is_active boolean
---@field is_zoomed boolean
---@field left number
---@field top number
---@field width number
---@field height number

---@class Pane
local Pane = {}

---Get pane ID
---@return number
function Pane:pane_id() end

---Get domain name
---@return string
function Pane:get_domain_name() end

---Get current working directory
---@return PaneUrl?
function Pane:get_current_working_dir() end

---Check if alt screen is active (e.g., vim, less)
---@return boolean
function Pane:is_alt_screen_active() end

---Get foreground process info
---@return ProcessInfo?
function Pane:get_foreground_process_info() end

---Get scrollback as escape sequences
---@param nlines? number Max lines to retrieve
---@return string
function Pane:get_lines_as_escapes(nlines) end

---Get pane dimensions
---@return PaneDimensions
function Pane:get_dimensions() end

---Split the pane
---@param args SplitArgs
---@return Pane
function Pane:split(args) end

---Activate this pane
function Pane:activate() end

---Send text to pane
---@param text string
function Pane:send_text(text) end

---Inject output into pane (appears in scrollback)
---@param text string
function Pane:inject_output(text) end

---Get the parent tab
---@return MuxTab
function Pane:tab() end

---@class SplitArgs
---@field direction? "Right"|"Left"|"Top"|"Bottom"
---@field size? number Proportion (0-1)
---@field cwd? string
---@field domain? table
---@field top_level? boolean

---@class PaneUrl
---@field file_path string

---@class ProcessInfo
---@field name string
---@field executable string
---@field argv string[]
---@field children? ProcessInfo[] Child processes
---@field pid? number Process ID
---@field ppid? number Parent process ID
---@field cwd? string Current working directory

---@class PaneDimensions
---@field cols number
---@field rows number
---@field scrollback_rows number
---@field pixel_width number
---@field pixel_height number

---@class GuiWindow
local GuiWindow = {}

---Set inner window size
---@param width number
---@param height number
function GuiWindow:set_inner_size(width, height) end

---Perform action
---@param action table
---@param pane? Pane
function GuiWindow:perform_action(action, pane) end

---Get the mux window associated with this GUI window
---@return MuxWindow
function GuiWindow:mux_window() end

---Check if this window is focused
---@return boolean
function GuiWindow:is_focused() end

---Get the active tab
---@return MuxTab
function GuiWindow:active_tab() end
