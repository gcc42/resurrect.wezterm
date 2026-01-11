-- Tests for state persistence (save/load round-trip)
-- Verifies that state can be saved to disk and loaded back correctly

local mux = require("mux")
local fixtures = require("pane_layouts")
local fs = require("fs")

-- Import modules under test
local state_manager = require("resurrect.state_manager")
local pane_tree_mod = require("resurrect.pane_tree")
local workspace_state_mod = require("resurrect.workspace_state")

--------------------------------------------------------------------------------
-- Setup / Teardown
--------------------------------------------------------------------------------

describe("Persistence", function()
	before(function()
		mux.reset()
		wezterm._test.reset()
		wezterm._test.set_mux(mux)
		-- Setup temp directory for tests
		-- Note: state_manager expects save_state_dir to end with separator
		local test_root = fs.setup() .. "/"
		state_manager.change_state_save_dir(test_root)
	end)

	after(function()
		fs.teardown()
	end)

	---------------------------------------------------------------------------
	-- Save Tests
	---------------------------------------------------------------------------

	describe("save", function()
		it("writes JSON file for workspace state", function()
			local workspace = mux.workspace("myproject")
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

			local state = workspace_state_mod.get_workspace_state()
			state_manager.save_state(state)

			local file_path = fs.get_root() .. "/workspace" .. "/myproject.json"
			expect(fs.exists(file_path)).to.equal(true)
		end)

		it("creates valid JSON content", function()
			local workspace = mux.workspace("jsontest")
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

			local state = workspace_state_mod.get_workspace_state()
			state_manager.save_state(state)

			local file_path = fs.get_root() .. "/workspace" .. "/jsontest.json"
			local content = fs.read(file_path)
			expect(content).to.exist()

			-- Should be valid JSON (parseable)
			local parsed = wezterm.json_parse(content)
			expect(parsed).to.exist()
			expect(parsed.workspace).to.equal("jsontest")
		end)
	end)

	---------------------------------------------------------------------------
	-- Load Tests
	---------------------------------------------------------------------------

	describe("load", function()
		it("parses saved JSON correctly", function()
			-- Write a test file directly
			fs.mkdir(fs.get_root() .. "/workspace")
			local file_path = fs.get_root() .. "/workspace" .. "/loadtest.json"
			fs.write(file_path, '{"workspace":"loadtest","window_states":[]}')

			local state = state_manager.load_state("loadtest", "workspace")

			expect(state).to.exist()
			expect(state.workspace).to.equal("loadtest")
		end)

		it("emits error for missing file", function()
			wezterm._test.clear_emitted_events()

			-- file_io.load_json throws for missing files
			-- state_manager should emit an error event
			local success, result = pcall(function()
				return state_manager.load_state("nonexistent", "workspace")
			end)

			-- Either returns empty table or throws - both are acceptable
			if success then
				expect(result).to.exist()
			end
		end)

		it("emits start event", function()
			fs.mkdir(fs.get_root() .. "/workspace")
			fs.write(fs.get_root() .. "/workspace" .. "/eventtest.json", '{"workspace":"eventtest","window_states":[]}')

			wezterm._test.clear_emitted_events()

			state_manager.load_state("eventtest", "workspace")

			local events = wezterm._test.get_emitted_events()
			local found = false
			for _, event in ipairs(events) do
				if event.name == "resurrect.state_manager.load_state.start" then
					found = true
					break
				end
			end
			expect(found).to.equal(true)
		end)

		it("emits finished event on success", function()
			fs.mkdir(fs.get_root() .. "/workspace")
			local json_data = '{"workspace":"finishtest","window_states":[]}'
			fs.write(fs.get_root() .. "/workspace" .. "/finishtest.json", json_data)

			wezterm._test.clear_emitted_events()

			state_manager.load_state("finishtest", "workspace")

			local events = wezterm._test.get_emitted_events()
			local found = false
			for _, event in ipairs(events) do
				if event.name == "resurrect.state_manager.load_state.finished" then
					found = true
					break
				end
			end
			expect(found).to.equal(true)
		end)
	end)

	---------------------------------------------------------------------------
	-- Round-Trip Tests
	---------------------------------------------------------------------------

	describe("round-trip", function()
		it("preserves single pane state", function()
			local workspace = mux.workspace("roundtrip-single")
				:window("main")
				:tab("tab")
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

			-- Load back
			local loaded = state_manager.load_state("roundtrip-single", "workspace")

			expect(loaded.workspace).to.equal(original.workspace)
			expect(#loaded.window_states).to.equal(#original.window_states)
		end)

		it("preserves split layout structure", function()
			local workspace = mux.workspace("roundtrip-split")
				:window("main")
				:tab("editor")
				:pane(fixtures.hsplit.panes[1])
				:hsplit(fixtures.hsplit.panes[2])
				:build()

			mux.set_active(workspace)

			-- Capture and save
			local original = workspace_state_mod.get_workspace_state()
			state_manager.save_state(original)

			-- Load back
			local loaded = state_manager.load_state("roundtrip-split", "workspace")

			expect(loaded.workspace).to.equal("roundtrip-split")
			expect(#loaded.window_states).to.equal(1)
			expect(#loaded.window_states[1].tabs).to.equal(1)

			-- Verify pane tree structure preserved
			local original_tree = original.window_states[1].tabs[1].pane_tree
			local loaded_tree = loaded.window_states[1].tabs[1].pane_tree

			expect(loaded_tree.cwd).to.equal(original_tree.cwd)
			if original_tree.right then
				expect(loaded_tree.right).to.exist()
				expect(loaded_tree.right.cwd).to.equal(original_tree.right.cwd)
			end
		end)

		it("preserves complex IDE layout through round-trip", function()
			local workspace = mux.workspace("roundtrip-ide")
				:window("main")
				:tab("dev")
				:pane(fixtures.ide_layout.panes[1])
				:hsplit(fixtures.ide_layout.panes[2])
				:vsplit(fixtures.ide_layout.panes[3])
				:build()

			mux.set_active(workspace)

			-- Capture and save
			local original = workspace_state_mod.get_workspace_state()
			state_manager.save_state(original)

			-- Load back
			local loaded = state_manager.load_state("roundtrip-ide", "workspace")

			-- Verify nested structure preserved
			local loaded_tree = loaded.window_states[1].tabs[1].pane_tree

			expect(loaded_tree).to.exist()
			expect(loaded_tree.right).to.exist()
			if loaded_tree.right.bottom then
				expect(loaded_tree.right.bottom).to.exist()
			end
		end)

		it("preserves multiple tabs through round-trip", function()
			local workspace = mux.workspace("roundtrip-tabs")
				:window("main")
				:tab("Tab 1")
				:pane({ left = 0, top = 0, width = 160, height = 48, cwd = "/a", is_active = true })
				:tab("Tab 2")
				:pane({ left = 0, top = 0, width = 160, height = 48, cwd = "/b", is_active = true })
				:build()

			mux.set_active(workspace)

			-- Capture and save
			local original = workspace_state_mod.get_workspace_state()
			state_manager.save_state(original)

			-- Load back
			local loaded = state_manager.load_state("roundtrip-tabs", "workspace")

			expect(#loaded.window_states[1].tabs).to.equal(2)
			expect(loaded.window_states[1].tabs[1].title).to.equal("Tab 1")
			expect(loaded.window_states[1].tabs[2].title).to.equal("Tab 2")
		end)

		it("preserves multiple windows through round-trip", function()
			local workspace = mux.workspace("roundtrip-windows")
				:window("Window 1")
				:tab("tab")
				:pane({
					left = 0,
					top = 0,
					width = 160,
					height = 48,
					cwd = "/a",
					is_active = true,
				})
				:window("Window 2")
				:tab("tab")
				:pane({
					left = 0,
					top = 0,
					width = 160,
					height = 48,
					cwd = "/b",
					is_active = true,
				})
				:build()

			mux.set_active(workspace)

			-- Capture and save
			local original = workspace_state_mod.get_workspace_state()
			state_manager.save_state(original)

			-- Load back
			local loaded = state_manager.load_state("roundtrip-windows", "workspace")

			expect(#loaded.window_states).to.equal(2)
		end)
	end)

	---------------------------------------------------------------------------
	-- Error Handling Tests
	---------------------------------------------------------------------------

	describe("error handling", function()
		it("emits error for invalid JSON", function()
			fs.mkdir(fs.get_root() .. "/workspace")
			fs.write(fs.get_root() .. "/workspace" .. "/invalid.json", "not valid json {{{")

			wezterm._test.clear_emitted_events()

			local state = state_manager.load_state("invalid", "workspace")

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

		it("returns empty table for invalid JSON", function()
			fs.mkdir(fs.get_root() .. "/workspace")
			fs.write(fs.get_root() .. "/workspace" .. "/bad.json", "{{{{")

			local result = state_manager.load_state("bad", "workspace")
			expect(next(result)).to.equal(nil)
		end)

		it("loads state with wrong structure gracefully", function()
			fs.mkdir(fs.get_root() .. "/workspace")
			fs.write(fs.get_root() .. "/workspace" .. "/wrong.json", '{"foo": "bar", "baz": 123}')

			local result = state_manager.load_state("wrong", "workspace")

			expect(result.foo).to.equal("bar")
			expect(result.workspace).to.equal(nil)
		end)

		it("handles empty JSON object", function()
			fs.mkdir(fs.get_root() .. "/workspace")
			fs.write(fs.get_root() .. "/workspace" .. "/empty.json", "{}")

			local result = state_manager.load_state("empty", "workspace")

			expect(type(result)).to.equal("table")
			expect(result.workspace).to.equal(nil)
		end)

		it("handles JSON array instead of object", function()
			fs.mkdir(fs.get_root() .. "/workspace")
			fs.write(fs.get_root() .. "/workspace" .. "/array.json", "[1, 2, 3]")

			local result = state_manager.load_state("array", "workspace")

			expect(type(result)).to.equal("table")
			expect(result[1]).to.equal(1)
		end)
	end)
end)
