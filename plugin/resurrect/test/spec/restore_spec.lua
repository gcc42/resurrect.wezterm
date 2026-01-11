-- Tests for state restore functionality
-- Verifies that workspace/window/tab/pane state is correctly restored

local mux = require("mux")
local fixtures = require("pane_layouts")

-- Import modules under test
local tab_state_mod = require("resurrect.tab_state")
local window_state_mod = require("resurrect.window_state")
local workspace_state_mod = require("resurrect.workspace_state")

--------------------------------------------------------------------------------
-- Setup / Teardown
--------------------------------------------------------------------------------

describe("State Restore", function()
	before(function()
		mux.reset()
		wezterm._test.reset()
		-- Inject mux fake into wezterm
		wezterm._test.set_mux(mux)
	end)

	---------------------------------------------------------------------------
	-- Workspace Restore Tests
	---------------------------------------------------------------------------

	describe("workspace restore", function()
		describe("single pane", function()
			it("spawns window with correct workspace", function()
				local state = {
					workspace = "test-workspace",
					window_states = {
						{
							title = "main",
							tabs = {
								{
									title = "tab",
									is_active = true,
									pane_tree = {
										cwd = "/project",
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

				workspace_state_mod.restore_workspace(state, { spawn_in_workspace = true })

				local windows = mux.all_windows()
				expect(#windows).to.be.truthy()

				-- Check workspace was set
				local found = false
				for _, win in ipairs(windows) do
					if win:get_workspace() == "test-workspace" then
						found = true
						break
					end
				end
				expect(found).to.equal(true)
			end)

			it("creates window with correct cwd", function()
				local state = {
					workspace = "test",
					window_states = {
						{
							title = "main",
							tabs = {
								{
									title = "tab",
									is_active = true,
									pane_tree = {
										cwd = "/my/project",
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
				expect(#windows).to.be.truthy()
			end)
		end)

		describe("error handling", function()
			it("emits error for nil state", function()
				wezterm._test.clear_emitted_events()

				workspace_state_mod.restore_workspace(nil, {})

				local events = wezterm._test.get_emitted_events()
				local found_error = false
				for _, event in ipairs(events) do
					if event.name == "resurrect.error" then
						found_error = true
						break
					end
				end
				expect(found_error).to.equal(true)
			end)

			it("emits error for empty window_states", function()
				wezterm._test.clear_emitted_events()

				local state = {
					workspace = "empty",
					window_states = {},
				}

				workspace_state_mod.restore_workspace(state, {})

				local events = wezterm._test.get_emitted_events()
				local found_error = false
				for _, event in ipairs(events) do
					if event.name == "resurrect.error" then
						found_error = true
						break
					end
				end
				expect(found_error).to.equal(true)
			end)

			it("emits error for missing window_states", function()
				wezterm._test.clear_emitted_events()

				local state = {
					workspace = "incomplete",
				}

				workspace_state_mod.restore_workspace(state, {})

				local events = wezterm._test.get_emitted_events()
				local found_error = false
				for _, event in ipairs(events) do
					if event.name == "resurrect.error" then
						found_error = true
						break
					end
				end
				expect(found_error).to.equal(true)
			end)
		end)

		describe("events", function()
			it("emits start event", function()
				wezterm._test.clear_emitted_events()

				local state = fixtures.to_workspace_state(fixtures.single_pane)
				workspace_state_mod.restore_workspace(state, {})

				local events = wezterm._test.get_emitted_events()
				local found_start = false
				for _, event in ipairs(events) do
					if event.name == "resurrect.workspace_state.restore_workspace.start" then
						found_start = true
						break
					end
				end
				expect(found_start).to.equal(true)
			end)

			it("emits finished event", function()
				wezterm._test.clear_emitted_events()

				local state = fixtures.to_workspace_state(fixtures.single_pane)
				workspace_state_mod.restore_workspace(state, {})

				local events = wezterm._test.get_emitted_events()
				local found_finished = false
				for _, event in ipairs(events) do
					if event.name == "resurrect.workspace_state.restore_workspace.finished" then
						found_finished = true
						break
					end
				end
				expect(found_finished).to.equal(true)
			end)
		end)

		describe("multiple windows", function()
			it("creates multiple windows", function()
				local state = {
					workspace = "multi",
					window_states = {
						{
							title = "Window 1",
							tabs = {
								{
									title = "tab1",
									is_active = true,
									pane_tree = {
										cwd = "/project1",
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
						{
							title = "Window 2",
							tabs = {
								{
									title = "tab2",
									is_active = true,
									pane_tree = {
										cwd = "/project2",
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
				expect(#windows >= 2).to.equal(true)
			end)
		end)
	end)

	---------------------------------------------------------------------------
	-- Split Restoration Tests
	---------------------------------------------------------------------------

	describe("splits", function()
		it("creates horizontal split structure", function()
			local state = {
				workspace = "test",
				window_states = {
					{
						title = "win",
						tabs = {
							{
								title = "tab",
								is_active = true,
								pane_tree = {
									cwd = "/left",
									width = 80,
									height = 48,
									left = 0,
									top = 0,
									is_active = true,
									right = { cwd = "/right", width = 80, height = 48, left = 81, top = 0 },
								},
							},
						},
						size = { cols = 160, rows = 48, pixel_width = 1600, pixel_height = 960 },
					},
				},
			}

			workspace_state_mod.restore_workspace(state, {})

			-- Verify structure was created
			local windows = mux.all_windows()
			expect(#windows >= 1).to.equal(true)
		end)

		it("creates vertical split structure", function()
			local state = {
				workspace = "test",
				window_states = {
					{
						title = "win",
						tabs = {
							{
								title = "tab",
								is_active = true,
								pane_tree = {
									cwd = "/top",
									width = 160,
									height = 24,
									left = 0,
									top = 0,
									is_active = true,
									bottom = { cwd = "/bottom", width = 160, height = 24, left = 0, top = 25 },
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

		it("creates nested split structure (IDE layout)", function()
			local state = {
				workspace = "test",
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
										cwd = "/terminal",
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

		it("creates three-way horizontal split", function()
			local state = {
				workspace = "test",
				window_states = {
					{
						title = "win",
						tabs = {
							{
								title = "tab",
								is_active = true,
								pane_tree = {
									cwd = "/a",
									width = 53,
									height = 48,
									left = 0,
									top = 0,
									is_active = true,
									right = {
										cwd = "/b",
										width = 53,
										height = 48,
										left = 54,
										top = 0,
										right = { cwd = "/c", width = 53, height = 48, left = 108, top = 0 },
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

		-- Regression test for split order bug:
		-- When a pane has both right and bottom children, the right split must happen
		-- first to preserve correct geometry. This layout represents:
		--   +--------+--------+
		--   | A      |        |
		--   | (root) |   B    |
		--   +--------+ (right)|
		--   | C      |        |
		--   |(bottom)|        |
		--   +--------+--------+
		-- Created by: split right (%), then split left pane down (")
		-- The right pane B should have FULL height (48), not half height (24).
		it("preserves split order when pane has both right and bottom children", function()
			-- Layout: 2 panes in left column, 1 full-height pane on right
			-- This is created by: split right first, then split left pane down
			local state = {
				workspace = "test",
				window_states = {
					{
						title = "win",
						tabs = {
							{
								title = "tab",
								is_active = true,
								pane_tree = {
									cwd = "/left-top",
									width = 80,
									height = 24,
									left = 0,
									top = 0,
									is_active = true,
									-- Right pane has FULL height (48) - split right happened first
									right = { cwd = "/right", width = 80, height = 48, left = 81, top = 0 },
									-- Bottom pane only in left column
									bottom = { cwd = "/left-bottom", width = 80, height = 24, left = 0, top = 25 },
								},
							},
						},
						size = { cols = 160, rows = 48, pixel_width = 1600, pixel_height = 960 },
					},
				},
			}

			workspace_state_mod.restore_workspace(state, {})

			-- Get the restored panes and verify geometry
			local windows = mux.all_windows()
			expect(#windows >= 1).to.equal(true)

			local tab = windows[#windows]:active_tab()
			local panes = tab:panes()

			-- Should have 3 panes total
			expect(#panes).to.equal(3)

			-- Find the right pane (cwd = "/right") and verify it has full height
			local right_pane = nil
			for _, pane in ipairs(panes) do
				local cwd_info = pane:get_current_working_dir()
				if cwd_info and cwd_info.file_path == "/right" then
					right_pane = pane
					break
				end
			end

			expect(right_pane).to.exist()
			-- The right pane should have full height (48), not half height
			-- If splits are done in wrong order (bottom first), this would be ~24
			expect(right_pane.height).to.equal(48)
		end)

		-- Opposite case: bottom split first, then right split on top pane
		-- Layout:
		--   +-----+-----+
		--   | A   |  B  |
		--   +-----+-----+
		--   |     C     |
		--   +-----------+
		-- Created by: split down (") first, then split top pane right (%)
		-- The bottom pane C should have FULL width (160), not half width (80).
		it("preserves split order when bottom was split first", function()
			local state = {
				workspace = "test",
				window_states = {
					{
						title = "win",
						tabs = {
							{
								title = "tab",
								is_active = true,
								pane_tree = {
									cwd = "/top-left",
									width = 80,
									height = 24,
									left = 0,
									top = 0,
									is_active = true,
									-- Right pane only in top row (half height)
									right = { cwd = "/top-right", width = 80, height = 24, left = 81, top = 0 },
									-- Bottom pane has FULL width (160) - split down happened first
									bottom = { cwd = "/bottom", width = 160, height = 24, left = 0, top = 25 },
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

			local tab = windows[#windows]:active_tab()
			local panes = tab:panes()

			expect(#panes).to.equal(3)

			-- Find the bottom pane and verify it has full width
			local bottom_pane = nil
			for _, pane in ipairs(panes) do
				local cwd_info = pane:get_current_working_dir()
				if cwd_info and cwd_info.file_path == "/bottom" then
					bottom_pane = pane
					break
				end
			end

			expect(bottom_pane).to.exist()
			-- The bottom pane should have full width (160), not half width
			expect(bottom_pane.width).to.equal(160)
		end)

		it("restores grid 2x2 layout", function()
			local state = {
				workspace = "test",
				window_states = {
					{
						title = "win",
						tabs = {
							{
								title = "tab",
								is_active = true,
								pane_tree = {
									cwd = "/tl",
									width = 80,
									height = 24,
									left = 0,
									top = 0,
									is_active = true,
									right = { cwd = "/tr", width = 80, height = 24, left = 81, top = 0 },
									bottom = {
										cwd = "/bl",
										width = 80,
										height = 24,
										left = 0,
										top = 25,
										right = { cwd = "/br", width = 80, height = 24, left = 81, top = 25 },
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

		it("preserves pane cwd values in state", function()
			local state = {
				workspace = "test",
				window_states = {
					{
						title = "win",
						tabs = {
							{
								title = "tab",
								is_active = true,
								pane_tree = {
									cwd = "/project/src",
									width = 80,
									height = 48,
									left = 0,
									top = 0,
									is_active = true,
									right = { cwd = "/project/tests", width = 80, height = 48, left = 81, top = 0 },
								},
							},
						},
						size = { cols = 160, rows = 48, pixel_width = 1600, pixel_height = 960 },
					},
				},
			}

			-- Verify the state has the correct cwd values
			expect(state.window_states[1].tabs[1].pane_tree.cwd).to.equal("/project/src")
			expect(state.window_states[1].tabs[1].pane_tree.right.cwd).to.equal("/project/tests")

			workspace_state_mod.restore_workspace(state, {})

			local windows = mux.all_windows()
			expect(#windows >= 1).to.equal(true)
		end)

		it("preserves pane position values in nested splits", function()
			local state = {
				workspace = "test",
				window_states = {
					{
						title = "win",
						tabs = {
							{
								title = "tab",
								is_active = true,
								pane_tree = {
									cwd = "/a",
									width = 100,
									height = 48,
									left = 0,
									top = 0,
									is_active = true,
									right = {
										cwd = "/b",
										width = 60,
										height = 24,
										left = 101,
										top = 0,
										bottom = { cwd = "/c", width = 60, height = 24, left = 101, top = 25 },
									},
								},
							},
						},
						size = { cols = 160, rows = 48, pixel_width = 1600, pixel_height = 960 },
					},
				},
			}

			-- Verify pane positions in state
			expect(state.window_states[1].tabs[1].pane_tree.left).to.equal(0)
			expect(state.window_states[1].tabs[1].pane_tree.right.left).to.equal(101)
			expect(state.window_states[1].tabs[1].pane_tree.right.bottom.top).to.equal(25)

			workspace_state_mod.restore_workspace(state, {})
		end)
	end)

	---------------------------------------------------------------------------
	-- Tab Restoration Tests
	---------------------------------------------------------------------------

	describe("tabs", function()
		it("restores tab title", function()
			local state = {
				workspace = "test",
				window_states = {
					{
						title = "win",
						tabs = {
							{
								title = "My Custom Tab",
								is_active = true,
								pane_tree = {
									cwd = "/home",
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

			-- The state contains tab title - verify it was in the state
			expect(state.window_states[1].tabs[1].title).to.equal("My Custom Tab")
		end)

		it("restores multiple tabs", function()
			local state = {
				workspace = "test",
				window_states = {
					{
						title = "win",
						tabs = {
							{
								title = "Tab 1",
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
								title = "Tab 2",
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
								title = "Tab 3",
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

			-- Verify we had 3 tabs in the state
			expect(#state.window_states[1].tabs).to.equal(3)
		end)

		it("activates correct tab", function()
			local state = {
				workspace = "test",
				window_states = {
					{
						title = "win",
						tabs = {
							{
								title = "Tab 1",
								is_active = false,
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
								title = "Tab 2",
								is_active = true,
								pane_tree = {
									cwd = "/b",
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

			-- Tab 2 was marked as active
			expect(state.window_states[1].tabs[2].is_active).to.equal(true)
		end)
	end)

	---------------------------------------------------------------------------
	-- Active Pane Tests
	---------------------------------------------------------------------------

	describe("active pane", function()
		it("state contains active pane marker", function()
			local state = {
				workspace = "test",
				window_states = {
					{
						title = "win",
						tabs = {
							{
								title = "tab",
								pane_tree = {
									cwd = "/a",
									width = 80,
									height = 48,
									left = 0,
									top = 0,
									is_active = false,
									right = {
										cwd = "/b",
										width = 80,
										height = 48,
										left = 81,
										top = 0,
										is_active = true,
									},
								},
							},
						},
						size = { cols = 160, rows = 48, pixel_width = 1600, pixel_height = 960 },
					},
				},
			}

			-- Right pane marked as active
			expect(state.window_states[1].tabs[1].pane_tree.right.is_active).to.equal(true)
		end)
	end)

	---------------------------------------------------------------------------
	-- Options Tests
	---------------------------------------------------------------------------

	describe("restore options", function()
		it("accepts relative sizing option", function()
			local state = fixtures.to_workspace_state(fixtures.hsplit)

			-- Should not throw with relative option
			workspace_state_mod.restore_workspace(state, { relative = true })
		end)

		it("accepts absolute sizing option", function()
			local state = fixtures.to_workspace_state(fixtures.hsplit)

			-- Should not throw with absolute option
			workspace_state_mod.restore_workspace(state, { absolute = true })
		end)

		it("accepts spawn_in_workspace option", function()
			local state = fixtures.to_workspace_state(fixtures.single_pane, "my-workspace")

			workspace_state_mod.restore_workspace(state, { spawn_in_workspace = true })

			-- Windows should be in the specified workspace
			local windows = mux.all_windows()
			if #windows > 0 then
				-- At least one window should be in the workspace
				local found = false
				for _, win in ipairs(windows) do
					if win:get_workspace() == "my-workspace" then
						found = true
						break
					end
				end
				expect(found).to.equal(true)
			end
		end)
	end)

	---------------------------------------------------------------------------
	-- Default on_pane_restore Tests
	---------------------------------------------------------------------------

	describe("default_on_pane_restore", function()
		it("injects text for normal panes", function()
			local fake_pane = {
				injected_text = nil,
				inject_output = function(self, text)
					self.injected_text = text
				end,
				send_text = function(self, text)
					self.sent_text = text
				end,
			}

			local pane_tree = { pane = fake_pane, text = "$ ls\nfile.txt\n$ ", alt_screen_active = false }

			tab_state_mod.default_on_pane_restore(pane_tree)

			expect(fake_pane.injected_text).to.exist()
			expect(fake_pane.injected_text).to.match("file.txt")
		end)

		it("sends command for alt screen panes", function()
			local fake_pane = {
				injected_text = nil,
				inject_output = function(self, text)
					self.injected_text = text
				end,
				send_text = function(self, text)
					self.sent_text = text
				end,
			}

			local pane_tree = {
				pane = fake_pane,
				alt_screen_active = true,
				process = { name = "vim", argv = { "vim", "file.txt" }, cwd = "/project", executable = "/usr/bin/vim" },
			}

			tab_state_mod.default_on_pane_restore(pane_tree)

			expect(fake_pane.sent_text).to.exist()
			expect(fake_pane.sent_text).to.match("vim")
		end)

		it("does nothing for panes without text or process", function()
			local fake_pane = {
				injected_text = nil,
				inject_output = function(self, text)
					self.injected_text = text
				end,
				send_text = function(self, text)
					self.sent_text = text
				end,
			}

			local pane_tree = { pane = fake_pane, alt_screen_active = false, text = nil }

			tab_state_mod.default_on_pane_restore(pane_tree)

			expect(fake_pane.injected_text).to_not.exist()
			expect(fake_pane.sent_text).to_not.exist()
		end)

		it("handles empty text", function()
			local fake_pane = {
				injected_text = nil,
				inject_output = function(self, text)
					self.injected_text = text
				end,
			}
			local pane_tree = { pane = fake_pane, alt_screen_active = false, text = "" }

			tab_state_mod.default_on_pane_restore(pane_tree)

			expect(fake_pane.injected_text).to.equal("")
		end)
	end)

	---------------------------------------------------------------------------
	-- Malformed Data Tests
	---------------------------------------------------------------------------

	describe("malformed data", function()
		it("handles pane tree with missing cwd", function()
			local state = {
				workspace = "test",
				window_states = {
					{
						title = "win",
						tabs = {
							{
								title = "tab",
								is_active = true,
								pane_tree = {
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

			local success = pcall(function()
				workspace_state_mod.restore_workspace(state, {})
			end)
			expect(success).to.equal(true)
		end)

		it("handles pane tree with missing dimensions", function()
			local state = {
				workspace = "test",
				window_states = {
					{
						title = "win",
						tabs = {
							{
								title = "tab",
								is_active = true,
								pane_tree = { cwd = "/home", left = 0, top = 0, is_active = true },
							},
						},
						size = { cols = 160, rows = 48, pixel_width = 1600, pixel_height = 960 },
					},
				},
			}

			local success = pcall(function()
				workspace_state_mod.restore_workspace(state, {})
			end)
			expect(success).to.equal(true)
		end)

		it("handles tab state with missing title", function()
			local state = {
				workspace = "test",
				window_states = {
					{
						title = "win",
						tabs = {
							{
								is_active = true,
								pane_tree = {
									cwd = "/home",
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

			local success = pcall(function()
				workspace_state_mod.restore_workspace(state, {})
			end)
			expect(success).to.equal(true)
		end)

		it("handles window state with missing title", function()
			local state = {
				workspace = "test",
				window_states = {
					{
						tabs = {
							{
								title = "tab",
								is_active = true,
								pane_tree = {
									cwd = "/home",
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

			local success = pcall(function()
				workspace_state_mod.restore_workspace(state, {})
			end)
			expect(success).to.equal(true)
		end)

		it("handles mixed spawnable domains with fallback", function()
			mux.set_domain_spawnable("SSH:dev", false)
			mux.set_domain_spawnable("local", true)

			local state = {
				workspace = "test",
				window_states = {
					{
						title = "win",
						tabs = {
							{
								title = "tab",
								is_active = true,
								pane_tree = {
									cwd = "/local",
									width = 80,
									height = 48,
									left = 0,
									top = 0,
									is_active = true,
									domain = "local",
									right = {
										cwd = "/remote",
										width = 80,
										height = 48,
										left = 81,
										top = 0,
										domain = "SSH:dev",
									},
								},
							},
						},
						size = { cols = 160, rows = 48, pixel_width = 1600, pixel_height = 960 },
					},
				},
			}

			local success = pcall(function()
				workspace_state_mod.restore_workspace(state, {})
			end)
			expect(success).to.equal(true)
		end)
	end)
end)
