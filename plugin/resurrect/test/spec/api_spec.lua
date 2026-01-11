-- Tests for shell/api.lua
-- Only tests unique behavior not covered by capture_spec.lua
--
-- Capture-related tests (cwd, domain name, tab title, window title, pane geometry,
-- scrollback, zoomed state, etc.) are covered in capture_spec.lua which tests
-- the same behavior via pane_tree, tab_state, window_state modules that call shell/api.

local mux = require("mux")

-- Import module under test
local shell_api = require("resurrect.shell.api")

--------------------------------------------------------------------------------
-- Setup / Teardown
--------------------------------------------------------------------------------

describe("Shell API", function()
	before(function()
		mux.reset()
		wezterm._test.reset()
		wezterm._test.set_mux(mux)
	end)

	---------------------------------------------------------------------------
	-- is_spawnable Tests (unique to shell/api.lua)
	---------------------------------------------------------------------------

	describe("domain spawnability", function()
		it("marks local domain as spawnable", function()
			local workspace = mux.workspace("test")
				:window("win")
				:tab("tab")
				:pane({ left = 0, top = 0, width = 160, height = 48, cwd = "/home", domain = "local" })
				:build()

			mux.set_active(workspace)

			local tab = workspace.windows[1]:tabs()[1]
			local pane = tab:active_pane()

			local raw = shell_api.extract_pane(pane, 1000)

			expect(raw.is_spawnable).to.equal(true)
			expect(raw.domain).to.equal("local")
		end)

		it("marks non-spawnable SSH domain correctly", function()
			mux.set_domain_spawnable("SSH:broken", false)

			local workspace = mux.workspace("test")
				:window("win")
				:tab("tab")
				:pane({ left = 0, top = 0, width = 160, height = 48, cwd = "/remote", domain = "SSH:broken" })
				:build()

			mux.set_active(workspace)

			local tab = workspace.windows[1]:tabs()[1]
			local pane = tab:active_pane()

			local raw = shell_api.extract_pane(pane, 1000)

			expect(raw.is_spawnable).to.equal(false)
			expect(raw.domain).to.equal("SSH:broken")
		end)
	end)

	---------------------------------------------------------------------------
	-- warn_not_spawnable Tests (unique function in shell/api.lua)
	---------------------------------------------------------------------------

	describe("warn_not_spawnable", function()
		it("emits error event and logs warning", function()
			wezterm._test.clear_emitted_events()
			wezterm._test.clear_logs()

			shell_api.warn_not_spawnable("SSH:dead")

			-- Check error event
			local events = wezterm._test.get_emitted_events()
			local found_event = false
			for _, event in ipairs(events) do
				if event.name == "resurrect.error" and event.args[1]:find("SSH:dead") then
					found_event = true
					break
				end
			end
			expect(found_event).to.equal(true)

			-- Check warning log
			local logs = wezterm._test.get_logs()
			local found_log = false
			for _, log in ipairs(logs) do
				if log.level == "warn" and log.message:find("SSH:dead") then
					found_log = true
					break
				end
			end
			expect(found_log).to.equal(true)
		end)
	end)
end)
