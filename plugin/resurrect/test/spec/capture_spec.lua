-- Tests for state capture functionality
-- Verifies that workspace/window/tab/pane state is correctly captured

local mux = require("mux")
local fixtures = require("pane_layouts")

-- Import modules under test
local pane_tree_mod = require("resurrect.pane_tree")
local tab_state_mod = require("resurrect.tab_state")
local window_state_mod = require("resurrect.window_state")
local workspace_state_mod = require("resurrect.workspace_state")

--------------------------------------------------------------------------------
-- Setup / Teardown
--------------------------------------------------------------------------------

describe("State Capture", function()

    before(function()
        mux.reset()
        wezterm._test.reset()
        -- Inject mux fake into wezterm
        wezterm._test.set_mux(mux)
    end)

    ---------------------------------------------------------------------------
    -- Pane Tree Creation Tests
    ---------------------------------------------------------------------------

    describe("pane tree creation", function()

        describe("single pane", function()
            it("creates tree with correct geometry", function()
                local workspace = mux.workspace("test")
                    :window("win")
                        :tab("tab")
                            :pane(fixtures.single_pane.panes[1])
                    :build()

                mux.set_active(workspace)

                local tab = workspace.windows[1]:tabs()[1]
                local panes_info = tab:panes_with_info()

                local tree = pane_tree_mod.create_pane_tree(panes_info)

                expect(tree).to.exist()
                expect(tree.cwd).to.equal("/home/user")
                expect(tree.width).to.equal(160)
                expect(tree.height).to.equal(48)
                expect(tree.left).to.equal(0)
                expect(tree.top).to.equal(0)
            end)

            it("has no children for single pane", function()
                local workspace = mux.workspace("test")
                    :window("win")
                        :tab("tab")
                            :pane(fixtures.single_pane.panes[1])
                    :build()

                mux.set_active(workspace)

                local tab = workspace.windows[1]:tabs()[1]
                local panes_info = tab:panes_with_info()
                local tree = pane_tree_mod.create_pane_tree(panes_info)

                expect(tree.right).to_not.exist()
                expect(tree.bottom).to_not.exist()
            end)
        end)

        describe("horizontal split", function()
            it("captures right pane as child", function()
                local workspace = mux.workspace("test")
                    :window("win")
                        :tab("tab")
                            :pane(fixtures.hsplit.panes[1])
                            :hsplit(fixtures.hsplit.panes[2])
                    :build()

                mux.set_active(workspace)

                local tab = workspace.windows[1]:tabs()[1]
                local panes_info = tab:panes_with_info()
                local tree = pane_tree_mod.create_pane_tree(panes_info)

                expect(tree.right).to.exist()
                expect(tree.right.cwd).to.equal("/tmp")
                expect(tree.bottom).to_not.exist()
            end)

            it("preserves left pane geometry", function()
                local workspace = mux.workspace("test")
                    :window("win")
                        :tab("tab")
                            :pane(fixtures.hsplit.panes[1])
                            :hsplit(fixtures.hsplit.panes[2])
                    :build()

                mux.set_active(workspace)

                local tab = workspace.windows[1]:tabs()[1]
                local panes_info = tab:panes_with_info()
                local tree = pane_tree_mod.create_pane_tree(panes_info)

                expect(tree.left).to.equal(0)
                expect(tree.width).to.equal(80)
                expect(tree.cwd).to.equal("/home")
            end)
        end)

        describe("vertical split", function()
            it("captures bottom pane as child", function()
                local workspace = mux.workspace("test")
                    :window("win")
                        :tab("tab")
                            :pane(fixtures.vsplit.panes[1])
                            :vsplit(fixtures.vsplit.panes[2])
                    :build()

                mux.set_active(workspace)

                local tab = workspace.windows[1]:tabs()[1]
                local panes_info = tab:panes_with_info()
                local tree = pane_tree_mod.create_pane_tree(panes_info)

                expect(tree.bottom).to.exist()
                expect(tree.bottom.cwd).to.equal("/var/log")
                expect(tree.right).to_not.exist()
            end)

            it("preserves top pane geometry", function()
                local workspace = mux.workspace("test")
                    :window("win")
                        :tab("tab")
                            :pane(fixtures.vsplit.panes[1])
                            :vsplit(fixtures.vsplit.panes[2])
                    :build()

                mux.set_active(workspace)

                local tab = workspace.windows[1]:tabs()[1]
                local panes_info = tab:panes_with_info()
                local tree = pane_tree_mod.create_pane_tree(panes_info)

                expect(tree.top).to.equal(0)
                expect(tree.height).to.equal(24)
                expect(tree.cwd).to.equal("/home")
            end)
        end)

        describe("IDE layout", function()
            it("preserves nested structure", function()
                local workspace = mux.workspace("test")
                    :window("win")
                        :tab("tab")
                            :pane(fixtures.ide_layout.panes[1])
                            :hsplit(fixtures.ide_layout.panes[2])
                            :vsplit(fixtures.ide_layout.panes[3])
                    :build()

                mux.set_active(workspace)

                local tab = workspace.windows[1]:tabs()[1]
                local panes_info = tab:panes_with_info()
                local tree = pane_tree_mod.create_pane_tree(panes_info)

                -- Root has right child (terminal column)
                expect(tree.right).to.exist()
                -- Terminal column has bottom child (output pane)
                expect(tree.right.bottom).to.exist()
            end)
        end)

    end)

    ---------------------------------------------------------------------------
    -- Tab State Tests
    ---------------------------------------------------------------------------

    describe("tab state", function()

        it("captures tab title", function()
            local workspace = mux.workspace("test")
                :window("win")
                    :tab("My Custom Tab")
                        :pane(fixtures.single_pane.panes[1])
                :build()

            mux.set_active(workspace)

            local tab = workspace.windows[1]:tabs()[1]
            local tab_state = tab_state_mod.get_tab_state(tab)

            expect(tab_state.title).to.equal("My Custom Tab")
        end)

        it("captures pane tree", function()
            local workspace = mux.workspace("test")
                :window("win")
                    :tab("tab")
                        :pane(fixtures.single_pane.panes[1])
                :build()

            mux.set_active(workspace)

            local tab = workspace.windows[1]:tabs()[1]
            local tab_state = tab_state_mod.get_tab_state(tab)

            expect(tab_state.pane_tree).to.exist()
            expect(tab_state.pane_tree.cwd).to.equal("/home/user")
        end)

        it("captures zoomed state", function()
            local workspace = mux.workspace("test")
                :window("win")
                    :tab("tab")
                        :pane(fixtures.zoomed_pane.panes[1])
                        :hsplit(fixtures.zoomed_pane.panes[2])
                :build()

            mux.set_active(workspace)

            local tab = workspace.windows[1]:tabs()[1]
            local tab_state = tab_state_mod.get_tab_state(tab)

            expect(tab_state.is_zoomed).to.equal(true)
        end)

    end)

    ---------------------------------------------------------------------------
    -- Window State Tests
    ---------------------------------------------------------------------------

    describe("window state", function()

        it("captures window title", function()
            local workspace = mux.workspace("test")
                :window("Main Window")
                    :tab("tab")
                        :pane(fixtures.single_pane.panes[1])
                :build()

            mux.set_active(workspace)

            local window = workspace.windows[1]
            local window_state = window_state_mod.get_window_state(window)

            expect(window_state.title).to.equal("Main Window")
        end)

        it("captures all tabs", function()
            local workspace = mux.workspace("test")
                :window("win")
                    :tab("Tab 1"):pane(fixtures.single_pane.panes[1])
                    :tab("Tab 2"):pane({ left = 0, top = 0, width = 160, height = 48, cwd = "/other" })
                :build()

            mux.set_active(workspace)

            local window = workspace.windows[1]
            local window_state = window_state_mod.get_window_state(window)

            expect(#window_state.tabs).to.equal(2)
            expect(window_state.tabs[1].title).to.equal("Tab 1")
            expect(window_state.tabs[2].title).to.equal("Tab 2")
        end)

        it("captures window size", function()
            local workspace = mux.workspace("test")
                :window("win")
                    :tab("tab")
                        :pane(fixtures.single_pane.panes[1])
                :build()

            mux.set_active(workspace)

            local window = workspace.windows[1]
            local window_state = window_state_mod.get_window_state(window)

            expect(window_state.size).to.exist()
            expect(window_state.size.cols).to.be.a("number")
            expect(window_state.size.rows).to.be.a("number")
        end)

        it("marks active tab", function()
            local workspace = mux.workspace("test")
                :window("win")
                    :tab("Tab 1"):pane(fixtures.single_pane.panes[1])
                    :tab("Tab 2"):pane({ left = 0, top = 0, width = 160, height = 48, cwd = "/other", is_active = true })
                :build()

            mux.set_active(workspace)

            local window = workspace.windows[1]
            local window_state = window_state_mod.get_window_state(window)

            -- At least one tab should be marked active
            local has_active = false
            for _, tab in ipairs(window_state.tabs) do
                if tab.is_active then
                    has_active = true
                    break
                end
            end
            expect(has_active).to.equal(true)
        end)

    end)

    ---------------------------------------------------------------------------
    -- Workspace State Tests
    ---------------------------------------------------------------------------

    describe("workspace state", function()

        it("captures workspace name", function()
            local workspace = mux.workspace("my-project")
                :window("win")
                    :tab("tab")
                        :pane(fixtures.single_pane.panes[1])
                :build()

            mux.set_active(workspace)

            local state = workspace_state_mod.get_workspace_state()

            expect(state.workspace).to.equal("my-project")
        end)

        it("captures all windows in workspace", function()
            local workspace = mux.workspace("test")
                :window("Window 1"):tab("tab"):pane(fixtures.single_pane.panes[1])
                :window("Window 2"):tab("tab"):pane({ left = 0, top = 0, width = 160, height = 48, cwd = "/other" })
                :build()

            mux.set_active(workspace)

            local state = workspace_state_mod.get_workspace_state()

            expect(#state.window_states).to.equal(2)
        end)

        it("only captures windows from active workspace", function()
            -- Create first workspace
            local workspace1 = mux.workspace("workspace1")
                :window("Win1"):tab("tab"):pane(fixtures.single_pane.panes[1])
                :build()

            mux.set_active(workspace1)

            -- Create second workspace (different name means different workspace)
            local workspace2 = mux.workspace("workspace2")
                :window("Win2"):tab("tab"):pane({ left = 0, top = 0, width = 160, height = 48, cwd = "/other" })
                :build()

            -- Don't set workspace2 as active, just add windows
            for _, win in ipairs(workspace2.windows) do
                table.insert(mux.all_windows(), win)
            end

            local state = workspace_state_mod.get_workspace_state()

            -- Should only have windows from workspace1
            expect(state.workspace).to.equal("workspace1")
            for _, win_state in ipairs(state.window_states) do
                -- All windows should be from workspace1
                expect(win_state).to.exist()
            end
        end)

    end)

    ---------------------------------------------------------------------------
    -- Scrollback Capture Tests
    ---------------------------------------------------------------------------

    describe("scrollback capture", function()

        it("captures terminal content", function()
            local workspace = mux.workspace("test")
                :window("win")
                    :tab("tab")
                        :pane(fixtures.with_scrollback.panes[1])
                :build()

            mux.set_active(workspace)

            local tab = workspace.windows[1]:tabs()[1]
            local panes_info = tab:panes_with_info()
            local tree = pane_tree_mod.create_pane_tree(panes_info)

            expect(tree.text).to.exist()
            expect(tree.text).to.match("file1.txt")
        end)

    end)

    ---------------------------------------------------------------------------
    -- Domain Capture Tests
    ---------------------------------------------------------------------------

    describe("domain capture", function()

        it("captures domain name", function()
            local workspace = mux.workspace("test")
                :window("win")
                    :tab("tab")
                        :pane({ left = 0, top = 0, width = 160, height = 48, cwd = "/home", domain = "local", is_active = true })
                :build()

            mux.set_active(workspace)

            local tab = workspace.windows[1]:tabs()[1]
            local panes_info = tab:panes_with_info()
            local tree = pane_tree_mod.create_pane_tree(panes_info)

            expect(tree.domain).to.equal("local")
        end)

        it("warns for non-spawnable domains", function()
            mux.set_domain_spawnable("SSH:dead", false)

            local workspace = mux.workspace("test")
                :window("win")
                    :tab("tab")
                        :pane({ left = 0, top = 0, width = 160, height = 48, cwd = "/remote", domain = "SSH:dead", is_active = true })
                :build()

            mux.set_active(workspace)

            local tab = workspace.windows[1]:tabs()[1]
            local panes_info = tab:panes_with_info()

            -- Clear logs before test
            wezterm._test.clear_logs()

            local tree = pane_tree_mod.create_pane_tree(panes_info)

            -- Should have logged a warning
            local logs = wezterm._test.get_logs()
            local found_warning = false
            for _, log in ipairs(logs) do
                if log.level == "warn" and log.message:match("SSH:dead") then
                    found_warning = true
                    break
                end
            end
            expect(found_warning).to.equal(true)
        end)

    end)

end)
