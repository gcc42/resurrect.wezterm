-- Tests for utils.lua path normalization and directory creation functions
-- Run with: lua plugin/resurrect/test/init.lua plugin/resurrect/test/test_utils.lua

--------------------------------------------------------------------------------
-- Test: is_windows_path
--------------------------------------------------------------------------------

describe("is_windows_path", function()
	-- Load utils fresh to get the functions
	local utils = require("resurrect.utils")

	it("should detect Windows drive letter paths", function()
		expect(utils.is_windows_path("C:\\Users\\test")).to.equal(true)
		expect(utils.is_windows_path("D:\\")).to.equal(true)
		expect(utils.is_windows_path("C:")).to.equal(true)
		expect(utils.is_windows_path("c:\\lowercase")).to.equal(true)
	end)

	it("should detect paths with backslashes", function()
		expect(utils.is_windows_path("foo\\bar\\baz")).to.equal(true)
		expect(utils.is_windows_path("\\\\network\\share")).to.equal(true)
	end)

	it("should return false for Unix paths", function()
		expect(utils.is_windows_path("/home/user")).to.equal(false)
		expect(utils.is_windows_path("/")).to.equal(false)
		expect(utils.is_windows_path("./relative/path")).to.equal(false)
		expect(utils.is_windows_path("relative/path")).to.equal(false)
	end)

	it("should handle empty and nil inputs", function()
		expect(utils.is_windows_path("")).to.equal(false)
		expect(utils.is_windows_path(nil)).to.equal(false)
	end)
end)

--------------------------------------------------------------------------------
-- Test: normalize_path_separators
--------------------------------------------------------------------------------

describe("normalize_path_separators", function()
	local utils = require("resurrect.utils")

	it("should convert forward slashes to backslashes when to_windows is true", function()
		expect(utils.normalize_path_separators("C:/Users/test", true)).to.equal("C:\\Users\\test")
		expect(utils.normalize_path_separators("foo/bar/baz", true)).to.equal("foo\\bar\\baz")
	end)

	it("should convert backslashes to forward slashes when to_windows is false", function()
		expect(utils.normalize_path_separators("C:\\Users\\test", false)).to.equal("C:/Users/test")
		expect(utils.normalize_path_separators("foo\\bar\\baz", false)).to.equal("foo/bar/baz")
	end)

	it("should handle mixed separators", function()
		expect(utils.normalize_path_separators("C:/Users\\test/data", true)).to.equal("C:\\Users\\test\\data")
		expect(utils.normalize_path_separators("C:/Users\\test/data", false)).to.equal("C:/Users/test/data")
	end)

	it("should handle empty and nil inputs", function()
		expect(utils.normalize_path_separators("", true)).to.equal("")
		expect(utils.normalize_path_separators("", false)).to.equal("")
		expect(utils.normalize_path_separators(nil, true)).to_not.exist()
		expect(utils.normalize_path_separators(nil, false)).to_not.exist()
	end)

	it("should leave paths unchanged if already in correct format", function()
		expect(utils.normalize_path_separators("C:\\Users\\test", true)).to.equal("C:\\Users\\test")
		expect(utils.normalize_path_separators("/home/user", false)).to.equal("/home/user")
	end)
end)

--------------------------------------------------------------------------------
-- Test: path_components
--------------------------------------------------------------------------------

describe("path_components", function()
	local utils = require("resurrect.utils")

	it("should parse Unix absolute paths", function()
		local components, root = utils.path_components("/home/user/docs")
		expect(root).to.equal("/")
		expect(#components).to.equal(3)
		expect(components[1]).to.equal("home")
		expect(components[2]).to.equal("user")
		expect(components[3]).to.equal("docs")
	end)

	it("should parse Unix root path", function()
		local components, root = utils.path_components("/")
		expect(root).to.equal("/")
		expect(#components).to.equal(0)
	end)

	it("should parse Unix relative paths", function()
		local components, root = utils.path_components("relative/path/to/file")
		expect(root).to_not.exist()
		expect(#components).to.equal(4)
		expect(components[1]).to.equal("relative")
		expect(components[4]).to.equal("file")
	end)

	it("should parse Windows paths with drive letters", function()
		local components, root = utils.path_components("C:\\Users\\test\\Documents")
		expect(root).to.equal("C:")
		expect(#components).to.equal(3)
		expect(components[1]).to.equal("Users")
		expect(components[2]).to.equal("test")
		expect(components[3]).to.equal("Documents")
	end)

	it("should parse Windows paths with forward slashes", function()
		local components, root = utils.path_components("C:/Users/test")
		expect(root).to.equal("C:")
		expect(#components).to.equal(2)
		expect(components[1]).to.equal("Users")
		expect(components[2]).to.equal("test")
	end)

	it("should handle Windows drive letter only", function()
		local components, root = utils.path_components("C:")
		expect(root).to.equal("C:")
		expect(#components).to.equal(0)
	end)

	it("should handle Windows drive letter with trailing slash", function()
		local components, root = utils.path_components("C:\\")
		expect(root).to.equal("C:")
		expect(#components).to.equal(0)
	end)

	it("should handle lowercase drive letters", function()
		local components, root = utils.path_components("d:\\data")
		expect(root).to.equal("d:")
		expect(#components).to.equal(1)
		expect(components[1]).to.equal("data")
	end)

	it("should handle empty and nil inputs", function()
		local components, root = utils.path_components("")
		expect(#components).to.equal(0)
		expect(root).to_not.exist()

		components, root = utils.path_components(nil)
		expect(#components).to.equal(0)
		expect(root).to_not.exist()
	end)

	it("should skip empty components from multiple consecutive separators", function()
		local components, root = utils.path_components("/home//user///docs")
		expect(root).to.equal("/")
		expect(#components).to.equal(3)
		expect(components[1]).to.equal("home")
		expect(components[2]).to.equal("user")
		expect(components[3]).to.equal("docs")
	end)
end)

--------------------------------------------------------------------------------
-- Test: join_path_components
--------------------------------------------------------------------------------

describe("join_path_components", function()
	local utils = require("resurrect.utils")

	it("should join Unix path components", function()
		local path = utils.join_path_components({ "home", "user", "docs" }, "/", false)
		expect(path).to.equal("/home/user/docs")
	end)

	it("should join Windows path components", function()
		local path = utils.join_path_components({ "Users", "test" }, "C:", true)
		expect(path).to.equal("C:\\Users\\test")
	end)

	it("should handle empty components", function()
		local path = utils.join_path_components({}, "/", false)
		expect(path).to.equal("/")
	end)

	it("should handle nil root for relative paths", function()
		local path = utils.join_path_components({ "relative", "path" }, nil, false)
		expect(path).to.equal("relative/path")
	end)

	it("should handle root slash on Windows style", function()
		local path = utils.join_path_components({ "home", "user" }, "/", true)
		expect(path).to.equal("\\home\\user")
	end)
end)

--------------------------------------------------------------------------------
-- Test: build_partial_path
--------------------------------------------------------------------------------

describe("build_partial_path", function()
	local utils = require("resurrect.utils")

	it("should build partial Unix paths", function()
		local components = { "home", "user", "docs", "file" }

		expect(utils.build_partial_path(components, 1, "/", false)).to.equal("/home")
		expect(utils.build_partial_path(components, 2, "/", false)).to.equal("/home/user")
		expect(utils.build_partial_path(components, 3, "/", false)).to.equal("/home/user/docs")
		expect(utils.build_partial_path(components, 4, "/", false)).to.equal("/home/user/docs/file")
	end)

	it("should build partial Windows paths", function()
		local components = { "Users", "test", "Documents" }

		expect(utils.build_partial_path(components, 1, "C:", true)).to.equal("C:\\Users")
		expect(utils.build_partial_path(components, 2, "C:", true)).to.equal("C:\\Users\\test")
		expect(utils.build_partial_path(components, 3, "C:", true)).to.equal("C:\\Users\\test\\Documents")
	end)

	it("should handle count greater than components length", function()
		local components = { "a", "b" }
		expect(utils.build_partial_path(components, 10, "/", false)).to.equal("/a/b")
	end)

	it("should handle zero count", function()
		local components = { "a", "b" }
		expect(utils.build_partial_path(components, 0, "/", false)).to.equal("/")
	end)

	it("should handle relative paths", function()
		local components = { "relative", "path" }
		expect(utils.build_partial_path(components, 1, nil, false)).to.equal("relative")
		expect(utils.build_partial_path(components, 2, nil, false)).to.equal("relative/path")
	end)
end)

--------------------------------------------------------------------------------
-- Test: normalize_path with different target_triple values
--------------------------------------------------------------------------------

describe("normalize_path with different platforms", function()
	it("should normalize to forward slashes on macOS", function()
		wezterm._test.set_target_triple("x86_64-apple-darwin")
		-- Reload utils to pick up new target_triple
		package.loaded["resurrect.utils"] = nil
		local utils = require("resurrect.utils")

		expect(utils.normalize_path("/home/user/docs")).to.equal("/home/user/docs")
		expect(utils.normalize_path("C:\\Users\\test")).to.equal("C:/Users/test")
	end)

	it("should normalize to forward slashes on Linux", function()
		wezterm._test.set_target_triple("x86_64-unknown-linux-gnu")
		package.loaded["resurrect.utils"] = nil
		local utils = require("resurrect.utils")

		expect(utils.normalize_path("/home/user/docs")).to.equal("/home/user/docs")
		expect(utils.normalize_path("relative\\path")).to.equal("relative/path")
	end)

	it("should normalize to backslashes on Windows", function()
		wezterm._test.set_target_triple("x86_64-pc-windows-msvc")
		package.loaded["resurrect.utils"] = nil
		local utils = require("resurrect.utils")

		expect(utils.normalize_path("C:/Users/test")).to.equal("C:\\Users\\test")
		expect(utils.normalize_path("/home/user")).to.equal("\\home\\user")
	end)

	it("should handle ARM macOS", function()
		wezterm._test.set_target_triple("aarch64-apple-darwin")
		package.loaded["resurrect.utils"] = nil
		local utils = require("resurrect.utils")

		expect(utils.is_mac).to.equal(true)
		expect(utils.is_windows).to.equal(false)
		expect(utils.separator).to.equal("/")
	end)

	-- Reset to default after platform tests
	it("cleanup: reset to default platform", function()
		wezterm._test.set_target_triple("x86_64-apple-darwin")
		package.loaded["resurrect.utils"] = nil
	end)
end)

--------------------------------------------------------------------------------
-- Test: directory_exists (limited testing without filesystem mocking)
--------------------------------------------------------------------------------

describe("directory_exists", function()
	local utils = require("resurrect.utils")

	it("should return true for existing directories", function()
		-- Test with known existing directories
		local home = os.getenv("HOME") or "/tmp"
		expect(utils.directory_exists(home)).to.equal(true)
	end)

	it("should return false for non-existent directories", function()
		expect(utils.directory_exists("/nonexistent/path/that/should/not/exist/12345")).to.equal(false)
	end)

	it("should handle root directory", function()
		-- Root directory should always exist on Unix systems
		if not utils.is_windows then
			expect(utils.directory_exists("/")).to.equal(true)
		end
	end)
end)

--------------------------------------------------------------------------------
-- Test: ensure_folder_exists (integration test)
--------------------------------------------------------------------------------

describe("ensure_folder_exists", function()
	local utils = require("resurrect.utils")
	local test_base = os.getenv("TMPDIR") or os.getenv("TEMP") or "/tmp"

	it("should return false for empty path", function()
		local success, err = utils.ensure_folder_exists("")
		expect(success).to.equal(false)
		expect(err).to.exist()
	end)

	it("should return false for nil path", function()
		local success, err = utils.ensure_folder_exists(nil)
		expect(success).to.equal(false)
		expect(err).to.exist()
	end)

	it("should succeed for existing directory", function()
		local success, err = utils.ensure_folder_exists(test_base)
		expect(success).to.equal(true)
		expect(err).to_not.exist()
	end)

	it("should create nested directories", function()
		-- Use a unique test directory to avoid conflicts
		local unique_id = tostring(os.time()) .. "_" .. tostring(math.random(10000))
		local test_path = test_base .. "/resurrect_test_" .. unique_id .. "/nested/path"

		local success, err = utils.ensure_folder_exists(test_path)
		expect(success).to.equal(true)

		-- Verify the directory exists
		expect(utils.directory_exists(test_path)).to.equal(true)

		-- Cleanup: remove test directories
		os.execute('rm -rf "' .. test_base .. "/resurrect_test_" .. unique_id .. '" 2>/dev/null')
	end)
end)

--------------------------------------------------------------------------------
-- Test: path_exists
--------------------------------------------------------------------------------

describe("path_exists", function()
	local utils = require("resurrect.utils")

	it("should return true for existing files", function()
		-- Test with a file we know exists (this test file itself)
		local this_file = debug.getinfo(1, "S").source:match("@?(.*)")
		if this_file then
			expect(utils.path_exists(this_file)).to.equal(true)
		end
	end)

	it("should return false for non-existent paths", function()
		expect(utils.path_exists("/nonexistent/file/that/should/not/exist.txt")).to.equal(false)
	end)
end)
