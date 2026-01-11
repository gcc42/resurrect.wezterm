-- Tests for shell/io.lua
-- Verifies workflow orchestration, capture, save, load, and delete operations

local mux = require("mux")
local fixtures = require("pane_layouts")
local fs = require("fs")

-- Import module under test
local shell_io = require("resurrect.shell.io")
local core = require("resurrect.core.pane_tree")

--------------------------------------------------------------------------------
-- Helper: Find event by name
--------------------------------------------------------------------------------

local function find_event(events, name)
	for _, event in ipairs(events) do
		if event.name == name then
			return event
		end
	end
	return nil
end

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
		it("constructs correct path for workspace state", function()
			local path = shell_io.build_file_path("my-workspace", "workspace")

			expect(path).to.match("workspace")
			expect(path).to.match("my%-workspace%.json$")
		end)

		it("constructs correct path for window state", function()
			local path = shell_io.build_file_path("my-window", "window")

			expect(path).to.match("window")
			expect(path).to.match("my%-window%.json$")
		end)

		it("constructs correct path for tab state", function()
			local path = shell_io.build_file_path("my-tab", "tab")

			expect(path).to.match("tab")
			expect(path).to.match("my%-tab%.json$")
		end)

		it("sanitizes filename with invalid characters", function()
			local path = shell_io.build_file_path("my/bad:name", "workspace")

			-- Should not contain the invalid characters
			expect(path).to_not.match("/bad:")
			expect(path).to.match("my%+bad_name%.json$")
		end)
	end)

	---------------------------------------------------------------------------
	-- Capture Workflow Tests
	---------------------------------------------------------------------------

	describe("capture_workspace", function()
		it("captures current workspace with single window", function()
			local workspace = mux.workspace("capture-test")
				:window("main")
				:tab("dev")
				:pane({
					left = 0,
					top = 0,
					width = 160,
					height = 48,
					cwd = "/project",
					is_active = true,
				})
				:build()
			mux.set_active(workspace)

			local state = shell_io.capture_workspace()

			expect(state.workspace).to.equal("capture-test")
			expect(#state.window_states).to.equal(1)
			expect(state.window_states[1].title).to.equal("main")
		end)

		it("captures workspace with multiple windows", function()
			local workspace = mux.workspace("multi-win")
				:window("Window 1")
				:tab("tab")
				:pane({ left = 0, top = 0, width = 160, height = 48, cwd = "/a", is_active = true })
				:window("Window 2")
				:tab("tab")
				:pane({ left = 0, top = 0, width = 160, height = 48, cwd = "/b", is_active = true })
				:build()
			mux.set_active(workspace)

			local state = shell_io.capture_workspace()

			expect(#state.window_states).to.equal(2)
		end)
	end)

	describe("capture_window", function()
		it("captures window with single tab", function()
			local workspace = mux.workspace("win-test")
				:window("my-window")
				:tab("dev")
				:pane({
					left = 0,
					top = 0,
					width = 160,
					height = 48,
					cwd = "/project",
					is_active = true,
				})
				:build()
			mux.set_active(workspace)

			local mux_win = workspace.windows[1]
			local state = shell_io.capture_window(mux_win)

			expect(state.title).to.equal("my-window")
			expect(#state.tabs).to.equal(1)
			expect(state.tabs[1].title).to.equal("dev")
		end)

		it("captures window with multiple tabs", function()
			local workspace = mux.workspace("multi-tab")
				:window("main")
				:tab("Tab 1")
				:pane({ left = 0, top = 0, width = 160, height = 48, cwd = "/a", is_active = true })
				:tab("Tab 2")
				:pane({ left = 0, top = 0, width = 160, height = 48, cwd = "/b", is_active = true })
				:tab("Tab 3")
				:pane({ left = 0, top = 0, width = 160, height = 48, cwd = "/c", is_active = true })
				:build()
			mux.set_active(workspace)

			local mux_win = workspace.windows[1]
			local state = shell_io.capture_window(mux_win)

			expect(#state.tabs).to.equal(3)
			expect(state.tabs[1].title).to.equal("Tab 1")
			expect(state.tabs[2].title).to.equal("Tab 2")
			expect(state.tabs[3].title).to.equal("Tab 3")
		end)

		it("tracks active tab info from tabs_with_info", function()
			local workspace = mux.workspace("active-tab")
				:window("main")
				:tab("Tab 1")
				:pane({ left = 0, top = 0, width = 160, height = 48, cwd = "/a", is_active = true })
				:tab("Tab 2")
				:pane({ left = 0, top = 0, width = 160, height = 48, cwd = "/b", is_active = true })
				:build()
			mux.set_active(workspace)

			local mux_win = workspace.windows[1]
			local state = shell_io.capture_window(mux_win)

			-- At least one tab should have is_active set
			-- (mux fake sets first tab as active by default)
			expect(state.tabs[1].is_active).to.equal(true)
			expect(state.tabs[2].is_active).to.equal(false)
		end)
	end)

	describe("capture_tab", function()
		it("captures tab with single pane", function()
			local workspace = mux.workspace("tab-test")
				:window("main")
				:tab("my-tab")
				:pane({
					left = 0,
					top = 0,
					width = 160,
					height = 48,
					cwd = "/project",
					is_active = true,
				})
				:build()
			mux.set_active(workspace)

			local mux_tab = workspace.windows[1]:tabs()[1]
			local state = shell_io.capture_tab(mux_tab)

			expect(state.title).to.equal("my-tab")
			expect(state.pane_tree).to.exist()
			expect(state.pane_tree.cwd).to.equal("/project")
		end)

		it("captures tab with horizontal split", function()
			local workspace = mux.workspace("hsplit")
				:window("main")
				:tab("split-tab")
				:pane(fixtures.hsplit.panes[1])
				:hsplit(fixtures.hsplit.panes[2])
				:build()
			mux.set_active(workspace)

			local mux_tab = workspace.windows[1]:tabs()[1]
			local state = shell_io.capture_tab(mux_tab)

			expect(state.pane_tree).to.exist()
			expect(state.pane_tree.right).to.exist()
		end)

		it("captures tab with complex layout", function()
			local workspace = mux.workspace("ide-layout")
				:window("main")
				:tab("ide")
				:pane(fixtures.ide_layout.panes[1])
				:hsplit(fixtures.ide_layout.panes[2])
				:vsplit(fixtures.ide_layout.panes[3])
				:build()
			mux.set_active(workspace)

			local mux_tab = workspace.windows[1]:tabs()[1]
			local state = shell_io.capture_tab(mux_tab)

			expect(state.pane_tree).to.exist()
			expect(state.pane_tree.right).to.exist()
			expect(state.pane_tree.right.bottom).to.exist()
		end)
	end)

	---------------------------------------------------------------------------
	-- Save Workflow Tests
	---------------------------------------------------------------------------

	describe("save", function()
		it("saves workspace state to file", function()
			local workspace = mux.workspace("save-test")
				:window("main")
				:tab("tab")
				:pane({ left = 0, top = 0, width = 160, height = 48, cwd = "/home", is_active = true })
				:build()
			mux.set_active(workspace)

			local state = shell_io.capture_workspace()
			local success = shell_io.save(state)

			expect(success).to.equal(true)

			local file_path = fs.get_root() .. "/workspace/save-test.json"
			expect(fs.exists(file_path)).to.equal(true)
		end)

		it("saves window state to file", function()
			local workspace = mux.workspace("win-save")
				:window("my-window")
				:tab("tab")
				:pane({ left = 0, top = 0, width = 160, height = 48, cwd = "/home", is_active = true })
				:build()
			mux.set_active(workspace)

			local state = shell_io.capture_window(workspace.windows[1])
			local success = shell_io.save(state)

			expect(success).to.equal(true)

			local file_path = fs.get_root() .. "/window/my-window.json"
			expect(fs.exists(file_path)).to.equal(true)
		end)

		it("saves tab state to file", function()
			local workspace = mux.workspace("tab-save")
				:window("main")
				:tab("my-tab")
				:pane({ left = 0, top = 0, width = 160, height = 48, cwd = "/home", is_active = true })
				:build()
			mux.set_active(workspace)

			local state = shell_io.capture_tab(workspace.windows[1]:tabs()[1])
			local success = shell_io.save(state)

			expect(success).to.equal(true)

			local file_path = fs.get_root() .. "/tab/my-tab.json"
			expect(fs.exists(file_path)).to.equal(true)
		end)

		it("uses custom name when provided", function()
			local workspace = mux.workspace("workspace-name")
				:window("main")
				:tab("tab")
				:pane({ left = 0, top = 0, width = 160, height = 48, cwd = "/home", is_active = true })
				:build()
			mux.set_active(workspace)

			local state = shell_io.capture_workspace()
			shell_io.save(state, "custom-name")

			local file_path = fs.get_root() .. "/workspace/custom-name.json"
			expect(fs.exists(file_path)).to.equal(true)
		end)

		it("emits write_state events", function()
			local workspace = mux.workspace("event-test")
				:window("main")
				:tab("tab")
				:pane({ left = 0, top = 0, width = 160, height = 48, cwd = "/home", is_active = true })
				:build()
			mux.set_active(workspace)

			wezterm._test.clear_emitted_events()

			local state = shell_io.capture_workspace()
			shell_io.save(state)

			local events = wezterm._test.get_emitted_events()
			expect(has_event(events, "resurrect.file_io.write_state.start")).to.equal(true)
			expect(has_event(events, "resurrect.file_io.write_state.finished")).to.equal(true)
		end)

		it("returns false for unknown state type", function()
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
		it("loads workspace state from file", function()
			fs.mkdir(fs.get_root() .. "/workspace")
			local json_data = '{"workspace":"loaded-ws","window_states":[]}'
			fs.write(fs.get_root() .. "/workspace/loaded-ws.json", json_data)

			local state = shell_io.load("loaded-ws", "workspace")

			expect(state).to.exist()
			expect(state.workspace).to.equal("loaded-ws")
		end)

		it("loads window state from file", function()
			fs.mkdir(fs.get_root() .. "/window")
			local json_data = '{"title":"loaded-win","tabs":[]}'
			fs.write(fs.get_root() .. "/window/loaded-win.json", json_data)

			local state = shell_io.load("loaded-win", "window")

			expect(state).to.exist()
			expect(state.title).to.equal("loaded-win")
		end)

		it("loads tab state from file", function()
			fs.mkdir(fs.get_root() .. "/tab")
			local json_data = '{"title":"loaded-tab","pane_tree":{}}'
			fs.write(fs.get_root() .. "/tab/loaded-tab.json", json_data)

			local state = shell_io.load("loaded-tab", "tab")

			expect(state).to.exist()
			expect(state.title).to.equal("loaded-tab")
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

		it("emits error event for invalid JSON", function()
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
		it("deletes existing state file", function()
			fs.mkdir(fs.get_root() .. "/workspace")
			fs.write(fs.get_root() .. "/workspace/to-delete.json", '{"workspace":"to-delete"}')

			expect(fs.exists(fs.get_root() .. "/workspace/to-delete.json")).to.equal(true)

			local success = shell_io.delete("workspace/to-delete.json")

			expect(success).to.equal(true)
			expect(fs.exists(fs.get_root() .. "/workspace/to-delete.json")).to.equal(false)
		end)

		it("emits delete_state events", function()
			fs.mkdir(fs.get_root() .. "/workspace")
			fs.write(fs.get_root() .. "/workspace/delete-events.json", "{}")

			wezterm._test.clear_emitted_events()

			shell_io.delete("workspace/delete-events.json")

			local events = wezterm._test.get_emitted_events()
			expect(has_event(events, "resurrect.state_manager.delete_state.start")).to.equal(true)
			expect(has_event(events, "resurrect.state_manager.delete_state.finished")).to.equal(true)
		end)

		it("emits error event for non-existent file", function()
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

		it("returns nil for non-existent current state", function()
			-- Reset to a fresh directory
			local new_root = fs.reset() .. "/"
			shell_io.change_state_dir(new_root)

			local name, state_type = shell_io.read_current_state()

			expect(name).to.equal(nil)
			expect(state_type).to.equal(nil)
		end)
	end)

	---------------------------------------------------------------------------
	-- Round-Trip Tests
	---------------------------------------------------------------------------

	describe("round-trip", function()
		it("preserves workspace state through capture/save/load", function()
			local workspace = mux.workspace("roundtrip-test")
				:window("main")
				:tab("dev")
				:pane({
					left = 0,
					top = 0,
					width = 160,
					height = 48,
					cwd = "/project",
					is_active = true,
				})
				:build()
			mux.set_active(workspace)

			-- Capture and save
			local original = shell_io.capture_workspace()
			shell_io.save(original)

			-- Load back
			local loaded = shell_io.load("roundtrip-test", "workspace")

			expect(loaded.workspace).to.equal(original.workspace)
			expect(#loaded.window_states).to.equal(#original.window_states)
			expect(loaded.window_states[1].tabs[1].pane_tree.cwd).to.equal("/project")
		end)

		it("preserves complex layout through round-trip", function()
			local workspace = mux.workspace("complex-roundtrip")
				:window("IDE")
				:tab("dev")
				:pane(fixtures.ide_layout.panes[1])
				:hsplit(fixtures.ide_layout.panes[2])
				:vsplit(fixtures.ide_layout.panes[3])
				:build()
			mux.set_active(workspace)

			-- Capture and save
			local original = shell_io.capture_workspace()
			shell_io.save(original)

			-- Load back
			local loaded = shell_io.load("complex-roundtrip", "workspace")

			-- Verify nested structure preserved
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

			-- Capture and save
			local original = shell_io.capture_workspace()
			shell_io.save(original)

			-- Load back
			local loaded = shell_io.load("scrollback-test", "workspace")

			expect(loaded.window_states[1].tabs[1].pane_tree.text).to.exist()
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

			local state = shell_io.capture_workspace()
			shell_io.save(state)

			expect(fs.exists(new_root .. "workspace/dir-test.json")).to.equal(true)
		end)
	end)
end)
