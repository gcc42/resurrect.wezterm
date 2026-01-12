-- Tests for events and integration (Critical User Journeys)
-- Verifies event emission and end-to-end save/restore flows

local mux = require("mux")
local fixtures = require("pane_layouts")
local fs = require("fs")

-- Import modules under test
local state_manager = require("resurrect.state_manager")
local workspace_state_mod = require("resurrect.workspace_state")
local tab_state_mod = require("resurrect.tab_state")

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

describe("Events & Integration", function()
	before(function()
		mux.reset()
		wezterm._test.reset()
		wezterm._test.set_mux(mux)
		local test_root = fs.setup() .. "/"
		state_manager.change_state_save_dir(test_root)
	end)

	after(function()
		fs.teardown()
	end)

	---------------------------------------------------------------------------
	-- Event Emission Tests
	---------------------------------------------------------------------------

	describe("event emission", function()
		it("emits save events with file path", function()
			local workspace = mux.workspace("save-event-test")
				:window("main")
				:tab("tab")
				:pane({ left = 0, top = 0, width = 160, height = 48, cwd = "/home", is_active = true })
				:build()
			mux.set_active(workspace)

			wezterm._test.clear_emitted_events()
			local state = workspace_state_mod.get_workspace_state()
			state_manager.save_state(state)

			local events = wezterm._test.get_emitted_events()
			expect(has_event(events, "resurrect.file_io.write_state.start")).to.equal(true)
			expect(has_event(events, "resurrect.file_io.write_state.finished")).to.equal(true)

			local start_event = find_event(events, "resurrect.file_io.write_state.start")
			expect(start_event.args[1]).to.match("save%-event%-test")
		end)

		it("emits load events with name and type", function()
			fs.mkdir(fs.get_root() .. "/workspace")
			fs.write(fs.get_root() .. "/workspace/load-event-test.json", '{"workspace":"load-event-test","window_states":[]}')

			wezterm._test.clear_emitted_events()
			state_manager.load_state("load-event-test", "workspace")

			local events = wezterm._test.get_emitted_events()
			expect(has_event(events, "resurrect.state_manager.load_state.start")).to.equal(true)
			expect(has_event(events, "resurrect.state_manager.load_state.finished")).to.equal(true)

			local start_event = find_event(events, "resurrect.state_manager.load_state.start")
			expect(start_event.args[1]).to.equal("load-event-test")
			expect(start_event.args[2]).to.equal("workspace")
		end)

		it("emits restore events at workspace, window, and tab level", function()
			wezterm._test.clear_emitted_events()
			local state = fixtures.to_workspace_state(fixtures.single_pane)
			workspace_state_mod.restore_workspace(state, {})

			local events = wezterm._test.get_emitted_events()
			expect(has_event(events, "resurrect.workspace_state.restore_workspace.start")).to.equal(true)
			expect(has_event(events, "resurrect.workspace_state.restore_workspace.finished")).to.equal(true)
			expect(has_event(events, "resurrect.window_state.restore_window.start")).to.equal(true)
			expect(has_event(events, "resurrect.tab_state.restore_tab.start")).to.equal(true)
		end)

		it("emits error events for invalid states", function()
			-- Invalid JSON
			fs.mkdir(fs.get_root() .. "/workspace")
			fs.write(fs.get_root() .. "/workspace/bad-json.json", "not valid json {{{")

			wezterm._test.clear_emitted_events()
			state_manager.load_state("bad-json", "workspace")
			expect(has_event(wezterm._test.get_emitted_events(), "resurrect.error")).to.equal(true)

			-- Nil workspace state
			wezterm._test.clear_emitted_events()
			workspace_state_mod.restore_workspace(nil, {})
			local events = wezterm._test.get_emitted_events()
			expect(has_event(events, "resurrect.error")).to.equal(true)
			local error_event = find_event(events, "resurrect.error")
			expect(error_event.args[1]).to.match("empty")

			-- Empty window_states
			wezterm._test.clear_emitted_events()
			workspace_state_mod.restore_workspace({ workspace = "empty", window_states = {} }, {})
			expect(has_event(wezterm._test.get_emitted_events(), "resurrect.error")).to.equal(true)
		end)
	end)

	---------------------------------------------------------------------------
	-- CUJ-Level Integration Tests (Critical User Journeys)
	-- Note: Basic round-trip tests are in persistence_spec.lua
	---------------------------------------------------------------------------

	describe("integration", function()
		it("full save and restore workflow", function()
			-- Create workspace with complex layout
			local workspace = mux.workspace("cuj-full")
				:window("main")
				:tab("dev")
				:pane({ left = 0, top = 0, width = 160, height = 48, cwd = "/project", is_active = true })
				:build()
			mux.set_active(workspace)

			-- Capture and save
			local original = workspace_state_mod.get_workspace_state()
			state_manager.save_state(original)

			-- Verify file exists
			expect(fs.exists(fs.get_root() .. "/workspace/cuj-full.json")).to.equal(true)

			-- Reset mux to simulate fresh start
			mux.reset()
			wezterm._test.set_mux(mux)

			-- Load and restore
			local loaded = state_manager.load_state("cuj-full", "workspace")
			workspace_state_mod.restore_workspace(loaded, { spawn_in_workspace = true })

			-- Verify restoration
			local windows = mux.all_windows()
			expect(#windows >= 1).to.equal(true)
		end)

		it("saves and restores scrollback text with injection", function()
			local workspace = mux.workspace("cuj-scrollback")
				:window("win")
				:tab("tab")
				:pane({ left = 0, top = 0, width = 160, height = 48, cwd = "/home", text = "$ ls\nfile1.txt\n$ ", is_active = true })
				:build()
			mux.set_active(workspace)

			local original = workspace_state_mod.get_workspace_state()
			state_manager.save_state(original)

			local loaded = state_manager.load_state("cuj-scrollback", "workspace")

			expect(loaded.window_states[1].tabs[1].pane_tree.text).to.match("file1.txt")

			-- Test text injection
			local fake_pane = {
				inject_output = function(self, text)
					self.injected_text = text
				end,
				send_text = function() end,
			}
			tab_state_mod.default_on_pane_restore({ pane = fake_pane, text = "$ whoami\nuser\n$ ", alt_screen_active = false })
			expect(fake_pane.injected_text).to.match("whoami")
		end)

		it("preserves multiple tabs with cwds through round-trip", function()
			local workspace = mux.workspace("cuj-tabs")
				:window("win")
				:tab("src")
				:pane({ left = 0, top = 0, width = 160, height = 48, cwd = "/project/src", is_active = true })
				:tab("test")
				:pane({ left = 0, top = 0, width = 160, height = 48, cwd = "/project/test", is_active = true })
				:build()
			mux.set_active(workspace)

			local original = workspace_state_mod.get_workspace_state()
			state_manager.save_state(original)
			local loaded = state_manager.load_state("cuj-tabs", "workspace")

			expect(#loaded.window_states[1].tabs).to.equal(2)
			expect(loaded.window_states[1].tabs[1].pane_tree.cwd).to.equal("/project/src")
			expect(loaded.window_states[1].tabs[2].pane_tree.cwd).to.equal("/project/test")
		end)

		it("preserves complex nested layouts (IDE, 3-way, grid)", function()
			-- IDE layout
			local workspace = mux.workspace("cuj-ide")
				:window("IDE")
				:tab("dev")
				:pane(fixtures.ide_layout.panes[1])
				:hsplit(fixtures.ide_layout.panes[2])
				:vsplit(fixtures.ide_layout.panes[3])
				:build()
			mux.set_active(workspace)

			local original = workspace_state_mod.get_workspace_state()
			state_manager.save_state(original)
			local loaded = state_manager.load_state("cuj-ide", "workspace")

			local tree = loaded.window_states[1].tabs[1].pane_tree
			expect(tree.right).to.exist()
			expect(tree.right.bottom).to.exist()
		end)

		it("saves and restores multiple windows", function()
			local workspace = mux.workspace("cuj-multi-win")
				:window("Window 1")
				:tab("tab")
				:pane({ left = 0, top = 0, width = 160, height = 48, cwd = "/win1", is_active = true })
				:window("Window 2")
				:tab("tab")
				:pane({ left = 0, top = 0, width = 160, height = 48, cwd = "/win2", is_active = true })
				:build()
			mux.set_active(workspace)

			local original = workspace_state_mod.get_workspace_state()
			state_manager.save_state(original)

			local loaded = state_manager.load_state("cuj-multi-win", "workspace")

			expect(#loaded.window_states).to.equal(2)
		end)
	end)

	---------------------------------------------------------------------------
	-- Periodic Save Behavior
	---------------------------------------------------------------------------

	describe("periodic save", function()
		it("schedules timer with call_after", function()
			wezterm._test.reset()
			wezterm._test.set_mux(mux)

			state_manager.periodic_save({ interval_seconds = 60, save_workspaces = true })

			local timers = wezterm._test._pending_timers
			expect(#timers >= 1).to.equal(true)
			expect(timers[1].seconds).to.equal(60)
		end)

		it("uses default interval when not specified", function()
			wezterm._test.reset()
			wezterm._test.set_mux(mux)

			state_manager.periodic_save({ save_workspaces = true })

			local timers = wezterm._test._pending_timers
			expect(#timers >= 1).to.equal(true)
			expect(timers[1].seconds).to.equal(60 * 15)
		end)

		it("emits start and finished events when timer fires", function()
			wezterm._test.reset()
			wezterm._test.set_mux(mux)

			-- Create workspace so save has something to do
			local workspace = mux.workspace("periodic-test")
				:window("win")
				:tab("tab")
				:pane({
					left = 0,
					top = 0,
					width = 160,
					height = 48,
					cwd = "/home",
					is_active = true,
				})
				:build()
			mux.set_active(workspace)

			state_manager.periodic_save({ interval_seconds = 1, save_workspaces = true })

			wezterm._test.clear_emitted_events()
			wezterm._test.tick_timers()

			local events = wezterm._test.get_emitted_events()
			expect(has_event(events, "resurrect.state_manager.periodic_save.start")).to.equal(true)
			expect(has_event(events, "resurrect.state_manager.periodic_save.finished")).to.equal(true)
		end)

		it("reschedules after firing", function()
			wezterm._test.reset()
			wezterm._test.set_mux(mux)

			local workspace = mux.workspace("periodic-resched-test")
				:window("win")
				:tab("tab")
				:pane({
					left = 0,
					top = 0,
					width = 160,
					height = 48,
					cwd = "/home",
					is_active = true,
				})
				:build()
			mux.set_active(workspace)

			state_manager.periodic_save({ interval_seconds = 5, save_workspaces = true })

			-- Fire first timer
			wezterm._test.tick_timers()

			-- Should have rescheduled
			local timers = wezterm._test._pending_timers
			expect(#timers >= 1).to.equal(true)
		end)
	end)
end)
