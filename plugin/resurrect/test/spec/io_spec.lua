-- Tests for shell/io.lua
-- Verifies file I/O operations: save, load, delete, and directory management

local mux = require("mux")
local fixtures = require("pane_layouts")
local fs = require("fs")

-- Import modules under test
local shell_io = require("resurrect.shell.io")
local workspace_state_mod = require("resurrect.workspace_state")
local window_state_mod = require("resurrect.window_state")
local tab_state_mod = require("resurrect.tab_state")

--------------------------------------------------------------------------------
-- Helper: Find event by name
--------------------------------------------------------------------------------

---@class EmittedEvent
---@field name string Event name
---@field args any[] Event arguments

---Find an event by name in a list of emitted events
---@param events EmittedEvent[] List of emitted events
---@param name string Event name to find
---@return EmittedEvent|nil event The found event, or nil
local function find_event(events, name)
	for _, event in ipairs(events) do
		if event.name == name then
			return event
		end
	end
	return nil
end

---Check if an event exists in a list of emitted events
---@param events EmittedEvent[] List of emitted events
---@param name string Event name to check
---@return boolean exists True if the event exists
local function has_event(events, name)
	return find_event(events, name) ~= nil
end

--------------------------------------------------------------------------------
-- Setup / Teardown
--------------------------------------------------------------------------------

describe("Shell IO", function()
	before(function()
		mux.reset()
		wezterm._test.reset()
		wezterm._test.set_mux(mux)
		local test_root = fs.setup() .. "/"
		shell_io.change_state_dir(test_root)
	end)

	after(function()
		fs.teardown()
	end)

	---------------------------------------------------------------------------
	-- File Path Construction Tests
	---------------------------------------------------------------------------

	describe("build_file_path", function()
		it("constructs correct paths for all state types", function()
			local workspace_path = shell_io.build_file_path("my-workspace", "workspace")
			expect(workspace_path).to.match("workspace")
			expect(workspace_path).to.match("my%-workspace%.json$")

			local window_path = shell_io.build_file_path("my-window", "window")
			expect(window_path).to.match("window")
			expect(window_path).to.match("my%-window%.json$")

			local tab_path = shell_io.build_file_path("my-tab", "tab")
			expect(tab_path).to.match("tab")
			expect(tab_path).to.match("my%-tab%.json$")
		end)

		it("sanitizes filename with invalid characters", function()
			local path = shell_io.build_file_path("my/bad:name", "workspace")

			expect(path).to_not.match("/bad:")
			expect(path).to.match("my%+bad_name%.json$")
		end)
	end)

	---------------------------------------------------------------------------
	-- Save Workflow Tests
	---------------------------------------------------------------------------

	describe("save", function()
		it("saves all state types to file", function()
			local workspace = mux.workspace("save-test")
				:window("my-window")
				:tab("my-tab")
				:pane({ left = 0, top = 0, width = 160, height = 48, cwd = "/home", is_active = true })
				:build()
			mux.set_active(workspace)

			-- Workspace
			local ws_state = workspace_state_mod.get_workspace_state()
			expect(shell_io.save(ws_state)).to.equal(true)
			expect(fs.exists(fs.get_root() .. "/workspace/save-test.json")).to.equal(true)

			-- Window
			local win_state = window_state_mod.get_window_state(workspace.windows[1])
			expect(shell_io.save(win_state)).to.equal(true)
			expect(fs.exists(fs.get_root() .. "/window/my-window.json")).to.equal(true)

			-- Tab
			local tab_state = tab_state_mod.get_tab_state(workspace.windows[1]:tabs()[1])
			expect(shell_io.save(tab_state)).to.equal(true)
			expect(fs.exists(fs.get_root() .. "/tab/my-tab.json")).to.equal(true)
		end)

		it("uses custom name when provided", function()
			local workspace = mux.workspace("workspace-name")
				:window("main")
				:tab("tab")
				:pane({ left = 0, top = 0, width = 160, height = 48, cwd = "/home", is_active = true })
				:build()
			mux.set_active(workspace)

			local state = workspace_state_mod.get_workspace_state()
			shell_io.save(state, "custom-name")

			expect(fs.exists(fs.get_root() .. "/workspace/custom-name.json")).to.equal(true)
		end)

		it("emits write_state events", function()
			local workspace = mux.workspace("event-test")
				:window("main")
				:tab("tab")
				:pane({ left = 0, top = 0, width = 160, height = 48, cwd = "/home", is_active = true })
				:build()
			mux.set_active(workspace)

			wezterm._test.clear_emitted_events()

			local state = workspace_state_mod.get_workspace_state()
			shell_io.save(state)

			local events = wezterm._test.get_emitted_events()
			expect(has_event(events, "resurrect.file_io.write_state.start")).to.equal(true)
			expect(has_event(events, "resurrect.file_io.write_state.finished")).to.equal(true)
		end)

		it("returns false and emits error for unknown state type", function()
			wezterm._test.clear_emitted_events()

			local success = shell_io.save({ unknown = "data" })

			expect(success).to.equal(false)

			local events = wezterm._test.get_emitted_events()
			expect(has_event(events, "resurrect.error")).to.equal(true)
		end)
	end)

	---------------------------------------------------------------------------
	-- Load Workflow Tests
	---------------------------------------------------------------------------

	describe("load", function()
		it("loads all state types from file", function()
			fs.mkdir(fs.get_root() .. "/workspace")
			fs.mkdir(fs.get_root() .. "/window")
			fs.mkdir(fs.get_root() .. "/tab")

			fs.write(fs.get_root() .. "/workspace/loaded-ws.json", '{"workspace":"loaded-ws","window_states":[]}')
			fs.write(fs.get_root() .. "/window/loaded-win.json", '{"title":"loaded-win","tabs":[]}')
			fs.write(fs.get_root() .. "/tab/loaded-tab.json", '{"title":"loaded-tab","pane_tree":{}}')

			local ws_state = shell_io.load("loaded-ws", "workspace")
			expect(ws_state.workspace).to.equal("loaded-ws")

			local win_state = shell_io.load("loaded-win", "window")
			expect(win_state.title).to.equal("loaded-win")

			local tab_state = shell_io.load("loaded-tab", "tab")
			expect(tab_state.title).to.equal("loaded-tab")
		end)

		it("emits load_state events on success", function()
			fs.mkdir(fs.get_root() .. "/workspace")
			fs.write(fs.get_root() .. "/workspace/event-load.json", '{"workspace":"event-load"}')

			wezterm._test.clear_emitted_events()

			shell_io.load("event-load", "workspace")

			local events = wezterm._test.get_emitted_events()
			expect(has_event(events, "resurrect.state_manager.load_state.start")).to.equal(true)
			expect(has_event(events, "resurrect.state_manager.load_state.finished")).to.equal(true)
		end)

		it("returns nil and emits error event for invalid JSON", function()
			fs.mkdir(fs.get_root() .. "/workspace")
			fs.write(fs.get_root() .. "/workspace/bad-json.json", "not valid json {{{")

			wezterm._test.clear_emitted_events()

			local state = shell_io.load("bad-json", "workspace")

			expect(state).to.equal(nil)

			local events = wezterm._test.get_emitted_events()
			expect(has_event(events, "resurrect.error")).to.equal(true)
		end)
	end)

	---------------------------------------------------------------------------
	-- Delete Workflow Tests
	---------------------------------------------------------------------------

	describe("delete", function()
		it("deletes existing state file and emits events", function()
			fs.mkdir(fs.get_root() .. "/workspace")
			fs.write(fs.get_root() .. "/workspace/to-delete.json", '{"workspace":"to-delete"}')

			expect(fs.exists(fs.get_root() .. "/workspace/to-delete.json")).to.equal(true)

			wezterm._test.clear_emitted_events()
			local success = shell_io.delete("workspace/to-delete.json")

			expect(success).to.equal(true)
			expect(fs.exists(fs.get_root() .. "/workspace/to-delete.json")).to.equal(false)

			local events = wezterm._test.get_emitted_events()
			expect(has_event(events, "resurrect.state_manager.delete_state.start")).to.equal(true)
			expect(has_event(events, "resurrect.state_manager.delete_state.finished")).to.equal(true)
		end)

		it("returns false and emits error for non-existent file", function()
			wezterm._test.clear_emitted_events()

			local success = shell_io.delete("workspace/nonexistent.json")

			expect(success).to.equal(false)

			local events = wezterm._test.get_emitted_events()
			expect(has_event(events, "resurrect.error")).to.equal(true)
		end)
	end)

	---------------------------------------------------------------------------
	-- Current State Tracking Tests
	---------------------------------------------------------------------------

	describe("current state tracking", function()
		it("writes and reads current state", function()
			local success, _ = shell_io.write_current_state("my-workspace", "workspace")
			expect(success).to.equal(true)

			local name, state_type = shell_io.read_current_state()
			expect(name).to.equal("my-workspace")
			expect(state_type).to.equal("workspace")
		end)

		it("returns nil for missing or invalid current state", function()
			-- Reset to a fresh directory
			local new_root = fs.reset() .. "/"
			shell_io.change_state_dir(new_root)

			local name, state_type = shell_io.read_current_state()
			expect(name).to.equal(nil)
			expect(state_type).to.equal(nil)

			-- Write an invalid state type directly to file
			fs.write(fs.get_root() .. "/current_state", "my-workspace\ninvalid-type")
			name, state_type = shell_io.read_current_state()
			expect(name).to.equal(nil)
			expect(state_type).to.equal(nil)
		end)
	end)

	---------------------------------------------------------------------------
	-- Round-Trip Tests (shell_io layer - complex layouts and scrollback)
	-- Note: Basic round-trip tests are in persistence_spec.lua
	---------------------------------------------------------------------------

	describe("round-trip", function()
		it("preserves complex IDE layout with nested structure", function()
			local workspace = mux.workspace("complex-roundtrip")
				:window("IDE")
				:tab("dev")
				:pane(fixtures.ide_layout.panes[1])
				:hsplit(fixtures.ide_layout.panes[2])
				:vsplit(fixtures.ide_layout.panes[3])
				:build()
			mux.set_active(workspace)

			local original = workspace_state_mod.get_workspace_state()
			shell_io.save(original)

			local loaded = shell_io.load("complex-roundtrip", "workspace")

			local tree = loaded.window_states[1].tabs[1].pane_tree
			expect(tree).to.exist()
			expect(tree.right).to.exist()
			expect(tree.right.bottom).to.exist()
		end)

		it("preserves scrollback text through round-trip", function()
			local workspace = mux.workspace("scrollback-test")
				:window("main")
				:tab("tab")
				:pane({
					left = 0,
					top = 0,
					width = 160,
					height = 48,
					cwd = "/home",
					text = "$ ls\nfile1.txt\nfile2.txt\n$ ",
					is_active = true,
				})
				:build()
			mux.set_active(workspace)

			local original = workspace_state_mod.get_workspace_state()
			shell_io.save(original)

			local loaded = shell_io.load("scrollback-test", "workspace")

			expect(loaded.window_states[1].tabs[1].pane_tree.text).to.match("file1.txt")
		end)
	end)

	---------------------------------------------------------------------------
	-- Directory Management Tests
	---------------------------------------------------------------------------

	describe("change_state_dir", function()
		it("creates subdirectories for each state type", function()
			local new_root = fs.get_root() .. "/new-state-dir/"
			shell_io.change_state_dir(new_root)

			-- Directories should be created
			expect(shell_io.save_state_dir).to.equal(new_root)

			-- Verify by saving state
			local workspace = mux.workspace("dir-test")
				:window("main")
				:tab("tab")
				:pane({ left = 0, top = 0, width = 160, height = 48, cwd = "/home", is_active = true })
				:build()
			mux.set_active(workspace)

			local state = workspace_state_mod.get_workspace_state()
			shell_io.save(state)

			expect(fs.exists(new_root .. "workspace/dir-test.json")).to.equal(true)
		end)
	end)
end)
