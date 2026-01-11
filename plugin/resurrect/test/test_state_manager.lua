-- Tests for state_manager.lua re-exports
-- Verifies backward compatibility after moving functions to core

local state_manager = require("resurrect.state_manager")
local core = require("resurrect.core.pane_tree")

describe("state_manager re-exports", function()
	it("re-exports sanitize_filename from core", function()
		-- Verify re-export works and matches core implementation
		expect(state_manager.sanitize_filename("test")).to.equal(core.sanitize_filename("test"))
		expect(state_manager.sanitize_filename("/path/to/file")).to.equal(core.sanitize_filename("/path/to/file"))
	end)
end)
