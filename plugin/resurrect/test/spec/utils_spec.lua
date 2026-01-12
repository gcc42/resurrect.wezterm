-- Utils Module Test Suite
--
-- Tests for pure functions in utils.lua (path, string, and table utilities).

local utils = require("resurrect.utils")

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

describe("Utils", function()
	---------------------------------------------------------------------------
	-- Path Normalization
	---------------------------------------------------------------------------

	describe("is_windows_path", function()
		it("detects Windows paths", function()
			expect(utils.is_windows_path("C:\\Users\\foo")).to.equal(true)
			expect(utils.is_windows_path("D:/Projects")).to.equal(true)
			expect(utils.is_windows_path("foo\\bar\\baz")).to.equal(true)
		end)

		it("returns false for Unix paths", function()
			expect(utils.is_windows_path("/home/user")).to.equal(false)
			expect(utils.is_windows_path("relative/path")).to.equal(false)
		end)
	end)

	describe("normalize_path_separators", function()
		it("converts between Windows and Unix separators", function()
			expect(utils.normalize_path_separators("/home/user", true)).to.equal("\\home\\user")
			expect(utils.normalize_path_separators("C:\\Users\\foo", false)).to.equal("C:/Users/foo")
		end)
	end)

	describe("path_components", function()
		it("splits Unix absolute paths", function()
			local comps, root = utils.path_components("/home/user/project")
			expect(root).to.equal("/")
			expect(#comps).to.equal(3)
			expect(comps[1]).to.equal("home")
		end)

		it("splits Windows paths with drive letters", function()
			local comps, drive = utils.path_components("C:\\Users\\foo")
			expect(drive).to.equal("C:")
			expect(#comps).to.equal(2)
			expect(comps[1]).to.equal("Users")
		end)
	end)

	describe("join_path_components", function()
		it("joins with platform-appropriate separators", function()
			expect(utils.join_path_components({ "home", "user" }, "/", false)).to.equal("/home/user")
			expect(utils.join_path_components({ "Users", "foo" }, "C:", true)).to.equal("C:\\Users\\foo")
			expect(utils.join_path_components({ "foo", "bar" }, nil, false)).to.equal("foo/bar")
		end)
	end)

	---------------------------------------------------------------------------
	-- String Utilities
	---------------------------------------------------------------------------

	describe("utf8len", function()
		it("counts characters", function()
			expect(utils.utf8len("hello")).to.equal(5)
			expect(utils.utf8len("")).to.equal(0)
		end)
	end)

	describe("strip_format_esc_seq", function()
		it("removes ANSI escape sequences", function()
			expect(utils.strip_format_esc_seq("\27[31mred\27[0m")).to.equal("red")
		end)
	end)

	describe("replace_center", function()
		it("replaces center of string", function()
			expect(utils.replace_center("abcdefgh", 2, "..")).to.equal("abc..fgh")
		end)
	end)

	---------------------------------------------------------------------------
	-- Table Utilities
	---------------------------------------------------------------------------

	describe("deepcopy", function()
		it("creates independent copy of nested tables", function()
			local original = { a = 1, nested = { b = 2 } }
			local copy = utils.deepcopy(original)
			copy.nested.b = 99
			expect(original.nested.b).to.equal(2)
		end)
	end)

	describe("tbl_deep_extend", function()
		it("merges with force behavior (rightmost wins)", function()
			local result = utils.tbl_deep_extend("force", { a = 1 }, { a = 2, b = 3 })
			expect(result.a).to.equal(2)
			expect(result.b).to.equal(3)
		end)

		it("recursively merges nested tables", function()
			local result = utils.tbl_deep_extend("force", { n = { x = 1 } }, { n = { y = 2 } })
			expect(result.n.x).to.equal(1)
			expect(result.n.y).to.equal(2)
		end)
	end)
end)
