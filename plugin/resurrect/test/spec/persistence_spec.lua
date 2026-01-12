-- Tests for state persistence (save/load round-trip)
-- Verifies that state can be saved to disk and loaded back correctly
--
-- Note: Event emission tests are in events_spec.lua
-- Note: Round-trip tests for complex layouts are in io_spec.lua

local mux = require("mux")
local fixtures = require("pane_layouts")
local fs = require("fs")

-- Import modules under test
local state_manager = require("resurrect.state_manager")
local workspace_state_mod = require("resurrect.workspace_state")

--------------------------------------------------------------------------------
-- Setup / Teardown
--------------------------------------------------------------------------------

describe("Persistence", function()
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
	-- Save Tests
	---------------------------------------------------------------------------

	describe("save", function()
		it("writes valid JSON file for workspace state", function()
			local workspace = mux.workspace("jsontest")
				:window("main")
				:tab("tab")
				:pane({ left = 0, top = 0, width = 160, height = 48, cwd = "/home", is_active = true })
				:build()

			mux.set_active(workspace)

			local state = workspace_state_mod.get_workspace_state()
			state_manager.save_state(state)

			local file_path = fs.get_root() .. "/workspace/jsontest.json"
			expect(fs.exists(file_path)).to.equal(true)

			local content = fs.read(file_path)
			local parsed = wezterm.json_parse(content)
			expect(parsed.workspace).to.equal("jsontest")
		end)
	end)

	---------------------------------------------------------------------------
	-- Load Tests
	---------------------------------------------------------------------------

	describe("load", function()
		it("parses saved JSON correctly", function()
			fs.mkdir(fs.get_root() .. "/workspace")
			fs.write(fs.get_root() .. "/workspace/loadtest.json", '{"workspace":"loadtest","window_states":[]}')

			local state = state_manager.load_state("loadtest", "workspace")

			expect(state).to.exist()
			expect(state.workspace).to.equal("loadtest")
		end)
	end)

	---------------------------------------------------------------------------
	-- Round-Trip Tests
	---------------------------------------------------------------------------

	describe("round-trip", function()
		it("preserves workspace state through save/load cycle", function()
			local workspace = mux.workspace("roundtrip-single")
				:window("main")
				:tab("tab")
				:pane({ left = 0, top = 0, width = 160, height = 48, cwd = "/project", is_active = true })
				:build()

			mux.set_active(workspace)

			local original = workspace_state_mod.get_workspace_state()
			state_manager.save_state(original)

			local loaded = state_manager.load_state("roundtrip-single", "workspace")

			expect(loaded.workspace).to.equal(original.workspace)
			expect(#loaded.window_states).to.equal(#original.window_states)
		end)

		it("preserves split layout with nested structure", function()
			local workspace = mux.workspace("roundtrip-split")
				:window("main")
				:tab("editor")
				:pane(fixtures.hsplit.panes[1])
				:hsplit(fixtures.hsplit.panes[2])
				:build()

			mux.set_active(workspace)

			local original = workspace_state_mod.get_workspace_state()
			state_manager.save_state(original)

			local loaded = state_manager.load_state("roundtrip-split", "workspace")

			local original_tree = original.window_states[1].tabs[1].pane_tree
			local loaded_tree = loaded.window_states[1].tabs[1].pane_tree

			expect(loaded_tree.cwd).to.equal(original_tree.cwd)
			expect(loaded_tree.right).to.exist()
			expect(loaded_tree.right.cwd).to.equal(original_tree.right.cwd)
		end)
	end)

	---------------------------------------------------------------------------
	-- Error Handling Tests
	---------------------------------------------------------------------------

	describe("error handling", function()
		it("emits error and returns empty table for invalid JSON", function()
			fs.mkdir(fs.get_root() .. "/workspace")
			fs.write(fs.get_root() .. "/workspace/invalid.json", "not valid json {{{")

			wezterm._test.clear_emitted_events()

			local result = state_manager.load_state("invalid", "workspace")

			expect(next(result)).to.equal(nil)

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

		it("loads state with unexpected structure gracefully", function()
			fs.mkdir(fs.get_root() .. "/workspace")
			fs.write(fs.get_root() .. "/workspace/wrong.json", '{"foo": "bar", "baz": 123}')

			local result = state_manager.load_state("wrong", "workspace")

			expect(result.foo).to.equal("bar")
			expect(result.workspace).to.equal(nil)
		end)
	end)
end)
