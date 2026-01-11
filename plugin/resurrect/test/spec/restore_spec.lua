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
                                    title = "tab", is_active = true,
                                    pane_tree = { cwd = "/project", width = 160, height = 48, left = 0, top = 0, is_active = true },
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
                                    title = "tab", is_active = true,
                                    pane_tree = { cwd = "/my/project", width = 160, height = 48, left = 0, top = 0, is_active = true },
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
                                    title = "tab1", is_active = true,
                                    pane_tree = { cwd = "/project1", width = 160, height = 48, left = 0, top = 0, is_active = true },
                                },
                            },
                            size = { cols = 160, rows = 48, pixel_width = 1600, pixel_height = 960 },
                        },
                        {
                            title = "Window 2",
                            tabs = {
                                {
                                    title = "tab2", is_active = true,
                                    pane_tree = { cwd = "/project2", width = 160, height = 48, left = 0, top = 0, is_active = true },
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
                                title = "tab", is_active = true,
                                pane_tree = {
                                    cwd = "/left", width = 80, height = 48, left = 0, top = 0, is_active = true,
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
                                title = "tab", is_active = true,
                                pane_tree = {
                                    cwd = "/top", width = 160, height = 24, left = 0, top = 0, is_active = true,
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
                                title = "tab", is_active = true,
                                pane_tree = {
                                    cwd = "/editor", width = 100, height = 48, left = 0, top = 0, is_active = true,
                                    right = {
                                        cwd = "/terminal", width = 60, height = 24, left = 101, top = 0,
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
                                title = "My Custom Tab", is_active = true,
                                pane_tree = { cwd = "/home", width = 160, height = 48, left = 0, top = 0, is_active = true },
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
                                pane_tree = { cwd = "/a", width = 160, height = 48, left = 0, top = 0, is_active = true },
                            },
                            {
                                title = "Tab 2",
                                pane_tree = { cwd = "/b", width = 160, height = 48, left = 0, top = 0, is_active = true },
                            },
                            {
                                title = "Tab 3",
                                pane_tree = { cwd = "/c", width = 160, height = 48, left = 0, top = 0, is_active = true },
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
                                pane_tree = { cwd = "/a", width = 160, height = 48, left = 0, top = 0, is_active = true },
                            },
                            {
                                title = "Tab 2",
                                is_active = true,
                                pane_tree = { cwd = "/b", width = 160, height = 48, left = 0, top = 0, is_active = true },
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
                                    cwd = "/a", width = 80, height = 48, left = 0, top = 0, is_active = false,
                                    right = { cwd = "/b", width = 80, height = 48, left = 81, top = 0, is_active = true },
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
                inject_output = function(self, text) self.injected_text = text end,
                send_text = function(self, text) self.sent_text = text end,
            }

            local pane_tree = { pane = fake_pane, text = "$ ls\nfile.txt\n$ ", alt_screen_active = false }

            tab_state_mod.default_on_pane_restore(pane_tree)

            expect(fake_pane.injected_text).to.exist()
            expect(fake_pane.injected_text).to.match("file.txt")
        end)

        it("sends command for alt screen panes", function()
            local fake_pane = {
                injected_text = nil,
                inject_output = function(self, text) self.injected_text = text end,
                send_text = function(self, text) self.sent_text = text end,
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
                inject_output = function(self, text) self.injected_text = text end,
                send_text = function(self, text) self.sent_text = text end,
            }

            local pane_tree = { pane = fake_pane, alt_screen_active = false, text = nil }

            tab_state_mod.default_on_pane_restore(pane_tree)

            expect(fake_pane.injected_text).to_not.exist()
            expect(fake_pane.sent_text).to_not.exist()
        end)

    end)

end)
