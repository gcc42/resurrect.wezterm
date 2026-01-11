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
		describe("save events", function()
			it("emits start and finished events with file path", function()
				local workspace = mux.workspace("save-event-test")
					:window("main")
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

				wezterm._test.clear_emitted_events()
				local state = workspace_state_mod.get_workspace_state()
				state_manager.save_state(state)

				local events = wezterm._test.get_emitted_events()
				expect(has_event(events, "resurrect.file_io.write_state.start")).to.equal(true)
				expect(has_event(events, "resurrect.file_io.write_state.finished")).to.equal(true)

				local start_event = find_event(events, "resurrect.file_io.write_state.start")
				expect(start_event).to.exist()
				expect(start_event.args[1]).to.match("save%-event%-test")
			end)
		end)

		describe("load events", function()
			it("emits start and finished events with name and type", function()
				fs.mkdir(fs.get_root() .. "/workspace")
				local json_data = '{"workspace":"load-event-test","window_states":[]}'
				fs.write(fs.get_root() .. "/workspace/load-event-test.json", json_data)

				wezterm._test.clear_emitted_events()
				state_manager.load_state("load-event-test", "workspace")

				local events = wezterm._test.get_emitted_events()
				expect(has_event(events, "resurrect.state_manager.load_state.start")).to.equal(true)
				expect(has_event(events, "resurrect.state_manager.load_state.finished")).to.equal(true)

				local start_event = find_event(events, "resurrect.state_manager.load_state.start")
				expect(start_event).to.exist()
				expect(start_event.args[1]).to.equal("load-event-test")
				expect(start_event.args[2]).to.equal("workspace")
			end)
		end)

		describe("restore events", function()
			it("emits workspace, window, and tab restore events", function()
				wezterm._test.clear_emitted_events()
				local state = fixtures.to_workspace_state(fixtures.single_pane)
				workspace_state_mod.restore_workspace(state, {})

				local events = wezterm._test.get_emitted_events()
				expect(has_event(events, "resurrect.workspace_state.restore_workspace.start")).to.equal(true)
				expect(has_event(events, "resurrect.workspace_state.restore_workspace.finished")).to.equal(true)
				expect(has_event(events, "resurrect.window_state.restore_window.start")).to.equal(true)
				expect(has_event(events, "resurrect.tab_state.restore_tab.start")).to.equal(true)
			end)
		end)

		describe("error events", function()
			it("emits resurrect.error for invalid JSON", function()
				fs.mkdir(fs.get_root() .. "/workspace")
				fs.write(fs.get_root() .. "/workspace/bad-json.json", "not valid json {{{")

				wezterm._test.clear_emitted_events()
				state_manager.load_state("bad-json", "workspace")

				local events = wezterm._test.get_emitted_events()
				expect(has_event(events, "resurrect.error")).to.equal(true)
			end)

			it("emits resurrect.error with descriptive message for nil workspace state", function()
				wezterm._test.clear_emitted_events()
				workspace_state_mod.restore_workspace(nil, {})

				local events = wezterm._test.get_emitted_events()
				expect(has_event(events, "resurrect.error")).to.equal(true)

				local error_event = find_event(events, "resurrect.error")
				expect(error_event).to.exist()
				expect(error_event.args[1]).to.match("empty")
			end)

			it("emits resurrect.error for empty window_states", function()
				wezterm._test.clear_emitted_events()
				workspace_state_mod.restore_workspace({ workspace = "empty", window_states = {} }, {})

				local events = wezterm._test.get_emitted_events()
				expect(has_event(events, "resurrect.error")).to.equal(true)
			end)
		end)
	end)

	---------------------------------------------------------------------------
	-- CUJ-Level Integration Tests
	---------------------------------------------------------------------------

	describe("integration", function()
		describe("save and restore single window", function()
			it("round-trips workspace state through file system", function()
				local workspace = mux.workspace("cuj-single")
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
				local original = workspace_state_mod.get_workspace_state()
				state_manager.save_state(original)

				-- Verify file exists
				local file_path = fs.get_root() .. "/workspace/cuj-single.json"
				expect(fs.exists(file_path)).to.equal(true)

				-- Load back
				local loaded = state_manager.load_state("cuj-single", "workspace")

				expect(loaded.workspace).to.equal("cuj-single")
				expect(#loaded.window_states).to.equal(1)
				expect(loaded.window_states[1].tabs[1].pane_tree.cwd).to.equal("/project")
			end)

			it("restores loaded state to mux", function()
				-- Create and save
				local workspace = mux.workspace("cuj-restore")
					:window("win")
					:tab("tab")
					:pane({
						left = 0,
						top = 0,
						width = 160,
						height = 48,
						cwd = "/src",
						is_active = true,
					})
					:build()
				mux.set_active(workspace)

				local original = workspace_state_mod.get_workspace_state()
				state_manager.save_state(original)

				-- Reset mux to simulate fresh start
				mux.reset()
				wezterm._test.set_mux(mux)

				-- Load and restore
				local loaded = state_manager.load_state("cuj-restore", "workspace")
				workspace_state_mod.restore_workspace(loaded, { spawn_in_workspace = true })

				-- Verify restoration
				local windows = mux.all_windows()
				expect(#windows >= 1).to.equal(true)
			end)
		end)

		describe("preserve terminal content", function()
			it("saves and restores scrollback text", function()
				local workspace = mux.workspace("cuj-scrollback")
					:window("win")
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
				local original = workspace_state_mod.get_workspace_state()
				state_manager.save_state(original)

				-- Load back
				local loaded = state_manager.load_state("cuj-scrollback", "workspace")

				expect(loaded.window_states[1].tabs[1].pane_tree.text).to.exist()
				expect(loaded.window_states[1].tabs[1].pane_tree.text).to.match("file1.txt")
			end)

			it("injects text on restore via on_pane_restore", function()
				local fake_pane = {
					injected_text = nil,
					inject_output = function(self, text)
						self.injected_text = text
					end,
					send_text = function() end,
				}
				local pane_tree = { pane = fake_pane, text = "$ whoami\nuser\n$ ", alt_screen_active = false }

				tab_state_mod.default_on_pane_restore(pane_tree)

				expect(fake_pane.injected_text).to.exist()
				expect(fake_pane.injected_text).to.match("whoami")
			end)
		end)

		describe("handle multiple tabs", function()
			it("saves workspace with multiple tabs", function()
				local workspace = mux.workspace("cuj-multi-tabs")
					:window("win")
					:tab("Tab 1")
					:pane({
						left = 0,
						top = 0,
						width = 160,
						height = 48,
						cwd = "/a",
						is_active = true,
					})
					:tab("Tab 2")
					:pane({
						left = 0,
						top = 0,
						width = 160,
						height = 48,
						cwd = "/b",
						is_active = true,
					})
					:tab("Tab 3")
					:pane({
						left = 0,
						top = 0,
						width = 160,
						height = 48,
						cwd = "/c",
						is_active = true,
					})
					:build()
				mux.set_active(workspace)

				local original = workspace_state_mod.get_workspace_state()
				state_manager.save_state(original)

				local loaded = state_manager.load_state("cuj-multi-tabs", "workspace")

				expect(#loaded.window_states[1].tabs).to.equal(3)
				expect(loaded.window_states[1].tabs[1].title).to.equal("Tab 1")
				expect(loaded.window_states[1].tabs[2].title).to.equal("Tab 2")
				expect(loaded.window_states[1].tabs[3].title).to.equal("Tab 3")
			end)

			it("preserves tab cwds through round-trip", function()
				local workspace = mux.workspace("cuj-tabs-cwd")
					:window("win")
					:tab("src")
					:pane({
						left = 0,
						top = 0,
						width = 160,
						height = 48,
						cwd = "/project/src",
						is_active = true,
					})
					:tab("test")
					:pane({
						left = 0,
						top = 0,
						width = 160,
						height = 48,
						cwd = "/project/test",
						is_active = true,
					})
					:build()
				mux.set_active(workspace)

				local original = workspace_state_mod.get_workspace_state()
				state_manager.save_state(original)
				local loaded = state_manager.load_state("cuj-tabs-cwd", "workspace")

				expect(loaded.window_states[1].tabs[1].pane_tree.cwd).to.equal("/project/src")
				expect(loaded.window_states[1].tabs[2].pane_tree.cwd).to.equal("/project/test")
			end)

			it("restores multiple tabs to mux", function()
				local state = {
					workspace = "multi-tab-restore",
					window_states = {
						{
							title = "win",
							tabs = {
								{
									title = "Tab A",
									is_active = true,
									pane_tree = {
										cwd = "/a",
										width = 160,
										height = 48,
										left = 0,
										top = 0,
										is_active = true,
									},
								},
								{
									title = "Tab B",
									pane_tree = {
										cwd = "/b",
										width = 160,
										height = 48,
										left = 0,
										top = 0,
										is_active = true,
									},
								},
								{
									title = "Tab C",
									pane_tree = {
										cwd = "/c",
										width = 160,
										height = 48,
										left = 0,
										top = 0,
										is_active = true,
									},
								},
							},
							size = { cols = 160, rows = 48, pixel_width = 1600, pixel_height = 960 },
						},
					},
				}

				workspace_state_mod.restore_workspace(state, {})

				local windows = mux.all_windows()
				expect(#windows >= 1).to.equal(true)
			end)
		end)

		describe("complex layout round-trip", function()
			it("preserves IDE layout structure", function()
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

				-- Verify nested structure
				local tree = loaded.window_states[1].tabs[1].pane_tree
				expect(tree).to.exist()
				expect(tree.right).to.exist()
				expect(tree.right.bottom).to.exist()
			end)

			it("preserves three-way horizontal split", function()
				local workspace = mux.workspace("cuj-3way")
					:window("win")
					:tab("tab")
					:pane(fixtures.three_way_hsplit.panes[1])
					:hsplit(fixtures.three_way_hsplit.panes[2])
					:hsplit(fixtures.three_way_hsplit.panes[3])
					:build()
				mux.set_active(workspace)

				local original = workspace_state_mod.get_workspace_state()
				state_manager.save_state(original)

				local loaded = state_manager.load_state("cuj-3way", "workspace")

				local tree = loaded.window_states[1].tabs[1].pane_tree
				expect(tree.cwd).to.equal("/a")
				expect(tree.right).to.exist()
				expect(tree.right.cwd).to.equal("/b")
				expect(tree.right.right).to.exist()
				expect(tree.right.right.cwd).to.equal("/c")
			end)

			it("preserves 2x2 grid layout", function()
				local workspace = mux.workspace("cuj-grid")
					:window("win")
					:tab("tab")
					:pane(fixtures.grid_2x2.panes[1])
					:hsplit(fixtures.grid_2x2.panes[2])
					:vsplit(fixtures.grid_2x2.panes[3])
					:vsplit(fixtures.grid_2x2.panes[4])
					:build()
				mux.set_active(workspace)

				local original = workspace_state_mod.get_workspace_state()
				state_manager.save_state(original)

				local loaded = state_manager.load_state("cuj-grid", "workspace")

				local tree = loaded.window_states[1].tabs[1].pane_tree
				expect(tree.cwd).to.equal("/tl")
			end)

			it("restores complex layout to mux", function()
				local state = {
					workspace = "complex-restore",
					window_states = {
						{
							title = "win",
							tabs = {
								{
									title = "tab",
									is_active = true,
									pane_tree = {
										cwd = "/editor",
										width = 100,
										height = 48,
										left = 0,
										top = 0,
										is_active = true,
										right = {
											cwd = "/term",
											width = 60,
											height = 24,
											left = 101,
											top = 0,
											bottom = { cwd = "/output", width = 60, height = 24, left = 101, top = 25 },
										},
									},
								},
							},
							size = { cols = 160, rows = 48, pixel_width = 1600, pixel_height = 960 },
						},
					},
				}

				workspace_state_mod.restore_workspace(state, {})

				local windows = mux.all_windows()
				expect(#windows >= 1).to.equal(true)
			end)
		end)

		describe("multiple windows", function()
			it("saves and restores multiple windows", function()
				local workspace = mux.workspace("cuj-multi-win")
					:window("Window 1")
					:tab("tab")
					:pane({
						left = 0,
						top = 0,
						width = 160,
						height = 48,
						cwd = "/win1",
						is_active = true,
					})
					:window("Window 2")
					:tab("tab")
					:pane({
						left = 0,
						top = 0,
						width = 160,
						height = 48,
						cwd = "/win2",
						is_active = true,
					})
					:build()
				mux.set_active(workspace)

				local original = workspace_state_mod.get_workspace_state()
				state_manager.save_state(original)

				local loaded = state_manager.load_state("cuj-multi-win", "workspace")

				expect(#loaded.window_states).to.equal(2)
			end)
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
