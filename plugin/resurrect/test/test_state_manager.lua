-- Tests for state_manager.lua sanitize_filename()
-- Verifies fix for GitHub issue #107 (Windows paths with colons)

local state_manager = require("resurrect.state_manager")

describe("sanitize_filename()", function()
	it("passes through normal names unchanged", function()
		expect(state_manager.sanitize_filename("myworkspace")).to.equal("myworkspace")
		expect(state_manager.sanitize_filename("file.name")).to.equal("file.name")
	end)

	it("handles Windows drive letter paths (issue #107)", function()
		expect(state_manager.sanitize_filename("C:\\Users\\foo")).to.equal("C_+Users+foo")
		expect(state_manager.sanitize_filename("/home/user/project")).to.equal("+home+user+project")
	end)

	it("sanitizes path traversal sequences", function()
		expect(state_manager.sanitize_filename("../../../etc")).to.equal("_+_+_+etc")
		expect(state_manager.sanitize_filename("foo/../bar")).to.equal("foo+_+bar")
	end)

	it("sanitizes control characters", function()
		expect(state_manager.sanitize_filename("name\x00null")).to.equal("name_null")
		expect(state_manager.sanitize_filename("tab\ttab")).to.equal("tab_tab")
	end)

	it("returns _unnamed_ for empty/nil input", function()
		expect(state_manager.sanitize_filename(nil)).to.equal("_unnamed_")
		expect(state_manager.sanitize_filename("")).to.equal("_unnamed_")
		expect(state_manager.sanitize_filename("   ")).to.equal("_unnamed_") -- whitespace only
	end)
end)
