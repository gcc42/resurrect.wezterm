-- Utils Module Test Suite
--
-- Tests for pure functions in utils.lua (path, string, and table utilities).

local utils = require("resurrect.utils")

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

describe("Utils", function()
	---------------------------------------------------------------------------
	-- Path Utilities
	---------------------------------------------------------------------------

	describe("path utilities", function()
		it("detects Windows vs Unix paths", function()
			expect(utils.is_windows_path("C:\\Users\\foo")).to.equal(true)
			expect(utils.is_windows_path("D:/Projects")).to.equal(true)
			expect(utils.is_windows_path("/home/user")).to.equal(false)
		end)

		it("normalizes path separators", function()
			expect(utils.normalize_path_separators("/home/user", true)).to.equal("\\home\\user")
			expect(utils.normalize_path_separators("C:\\Users\\foo", false)).to.equal("C:/Users/foo")
		end)

		it("splits and joins path components", function()
			local comps, root = utils.path_components("/home/user/project")
			expect(root).to.equal("/")
			expect(comps[1]).to.equal("home")

			local wcomps, drive = utils.path_components("C:\\Users\\foo")
			expect(drive).to.equal("C:")
			expect(wcomps[1]).to.equal("Users")

			expect(utils.join_path_components({ "home", "user" }, "/", false)).to.equal("/home/user")
			expect(utils.join_path_components({ "Users", "foo" }, "C:", true)).to.equal("C:\\Users\\foo")
		end)
	end)

	---------------------------------------------------------------------------
	-- String Utilities
	---------------------------------------------------------------------------

	describe("string utilities", function()
		it("counts UTF-8 characters", function()
			expect(utils.utf8len("hello")).to.equal(5)
		end)

		it("strips ANSI escape sequences", function()
			expect(utils.strip_format_esc_seq("\27[31mred\27[0m")).to.equal("red")
		end)

		it("replaces center of string", function()
			expect(utils.replace_center("abcdefgh", 2, "..")).to.equal("abc..fgh")
		end)
	end)

	---------------------------------------------------------------------------
	-- Table Utilities
	---------------------------------------------------------------------------

	describe("table utilities", function()
		it("creates independent deep copies", function()
			local original = { a = 1, nested = { b = 2 } }
			local copy = utils.deepcopy(original)
			copy.nested.b = 99
			expect(original.nested.b).to.equal(2)
		end)

		it("deep extends tables with force merge", function()
			local result = utils.tbl_deep_extend("force", { a = 1, n = { x = 1 } }, { a = 2, b = 3, n = { y = 2 } })
			expect(result.a).to.equal(2)
			expect(result.b).to.equal(3)
			expect(result.n.x).to.equal(1)
			expect(result.n.y).to.equal(2)
		end)
	end)
end)
