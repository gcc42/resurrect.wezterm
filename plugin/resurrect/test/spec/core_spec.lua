-- Tests for pure core/pane_tree functions
-- These tests run without WezTerm mocks since core functions are pure

local core = require("resurrect.core.pane_tree")

--------------------------------------------------------------------------------
-- Test Fixtures: RawPaneData with is_spawnable field
--------------------------------------------------------------------------------

---@param overrides table?
---@return RawPaneData
local function make_pane(overrides)
	local pane = {
		left = 0,
		top = 0,
		width = 160,
		height = 48,
		cwd = "/home",
		domain = "local",
		is_spawnable = true,
		text = "",
		is_active = false,
		is_zoomed = false,
		alt_screen_active = false,
	}
	if overrides then
		for k, v in pairs(overrides) do
			pane[k] = v
		end
	end
	return pane
end

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

describe("Core Pane Tree", function()
	---------------------------------------------------------------------------
	-- build() Tests
	---------------------------------------------------------------------------

	describe("build", function()
		it("returns nil for empty pane list", function()
			local tree, warnings = core.build({})
			expect(tree).to_not.exist()
			expect(#warnings).to.equal(0)
		end)

		it("returns nil for nil input", function()
			local tree, warnings = core.build(nil)
			expect(tree).to_not.exist()
			expect(#warnings).to.equal(0)
		end)

		it("builds single pane tree", function()
			local panes = { make_pane({ cwd = "/project", is_active = true }) }
			local tree, warnings = core.build(panes)

			expect(tree).to.exist()
			expect(tree.cwd).to.equal("/project")
			expect(tree.is_active).to.equal(true)
			expect(tree.right).to_not.exist()
			expect(tree.bottom).to_not.exist()
			expect(#warnings).to.equal(0)
		end)

		it("builds horizontal split tree", function()
			local panes = {
				make_pane({ left = 0, width = 80, cwd = "/left", is_active = true }),
				make_pane({ left = 81, width = 80, cwd = "/right" }),
			}
			local tree, warnings = core.build(panes)

			expect(tree).to.exist()
			expect(tree.cwd).to.equal("/left")
			expect(tree.right).to.exist()
			expect(tree.right.cwd).to.equal("/right")
			expect(tree.bottom).to_not.exist()
			expect(#warnings).to.equal(0)
		end)

		it("builds vertical split tree", function()
			local panes = {
				make_pane({ top = 0, height = 24, cwd = "/top", is_active = true }),
				make_pane({ top = 25, height = 24, cwd = "/bottom" }),
			}
			local tree, warnings = core.build(panes)

			expect(tree).to.exist()
			expect(tree.cwd).to.equal("/top")
			expect(tree.bottom).to.exist()
			expect(tree.bottom.cwd).to.equal("/bottom")
			expect(tree.right).to_not.exist()
			expect(#warnings).to.equal(0)
		end)

		it("builds IDE layout (nested splits)", function()
			local panes = {
				make_pane({ left = 0, top = 0, width = 100, height = 48, cwd = "/editor", is_active = true }),
				make_pane({ left = 101, top = 0, width = 60, height = 24, cwd = "/terminal" }),
				make_pane({ left = 101, top = 25, width = 60, height = 24, cwd = "/output" }),
			}
			local tree, warnings = core.build(panes)

			expect(tree).to.exist()
			expect(tree.cwd).to.equal("/editor")
			expect(tree.right).to.exist()
			expect(tree.right.cwd).to.equal("/terminal")
			expect(tree.right.bottom).to.exist()
			expect(tree.right.bottom.cwd).to.equal("/output")
			expect(#warnings).to.equal(0)
		end)

		it("warns for non-spawnable domains", function()
			local panes = {
				make_pane({ domain = "SSH:dead", is_spawnable = false, is_active = true }),
			}
			local tree, warnings = core.build(panes)

			expect(tree).to.exist()
			expect(#warnings).to.equal(1)
			expect(warnings[1]).to.match("SSH:dead")
			expect(warnings[1]).to.match("not spawnable")
		end)
	end)

	---------------------------------------------------------------------------
	-- plan_splits() Tests
	---------------------------------------------------------------------------

	describe("plan_splits", function()
		it("returns empty list for single pane", function()
			local tree = {
				left = 0,
				top = 0,
				width = 160,
				height = 48,
				cwd = "/home",
				is_active = true,
				is_zoomed = false,
				alt_screen_active = false,
			}
			local commands = core.plan_splits(tree, {})

			expect(#commands).to.equal(0)
		end)

		it("plans horizontal split", function()
			local tree = {
				left = 0,
				top = 0,
				width = 80,
				height = 48,
				cwd = "/left",
				is_active = true,
				is_zoomed = false,
				alt_screen_active = false,
				right = {
					left = 81,
					top = 0,
					width = 80,
					height = 48,
					cwd = "/right",
					is_active = false,
					is_zoomed = false,
					alt_screen_active = false,
				},
			}
			local commands = core.plan_splits(tree, {})

			expect(#commands).to.equal(1)
			expect(commands[1].direction).to.equal("Right")
			expect(commands[1].cwd).to.equal("/right")
			expect(commands[1].size).to_not.exist()
		end)

		it("plans vertical split", function()
			local tree = {
				left = 0,
				top = 0,
				width = 160,
				height = 24,
				cwd = "/top",
				is_active = true,
				is_zoomed = false,
				alt_screen_active = false,
				bottom = {
					left = 0,
					top = 25,
					width = 160,
					height = 24,
					cwd = "/bottom",
					is_active = false,
					is_zoomed = false,
					alt_screen_active = false,
				},
			}
			local commands = core.plan_splits(tree, {})

			expect(#commands).to.equal(1)
			expect(commands[1].direction).to.equal("Bottom")
			expect(commands[1].cwd).to.equal("/bottom")
		end)

		it("calculates relative sizes", function()
			local tree = {
				left = 0,
				top = 0,
				width = 80,
				height = 48,
				cwd = "/left",
				is_active = true,
				is_zoomed = false,
				alt_screen_active = false,
				right = {
					left = 81,
					top = 0,
					width = 80,
					height = 48,
					cwd = "/right",
					is_active = false,
					is_zoomed = false,
					alt_screen_active = false,
				},
			}
			local commands = core.plan_splits(tree, { relative = true })

			expect(#commands).to.equal(1)
			expect(commands[1].size).to.exist()
			expect(commands[1].size).to.equal(0.5) -- 80 / (80 + 80)
		end)

		it("uses absolute sizes when specified", function()
			local tree = {
				left = 0,
				top = 0,
				width = 100,
				height = 48,
				cwd = "/left",
				is_active = true,
				is_zoomed = false,
				alt_screen_active = false,
				right = {
					left = 101,
					top = 0,
					width = 60,
					height = 48,
					cwd = "/right",
					is_active = false,
					is_zoomed = false,
					alt_screen_active = false,
				},
			}
			local commands = core.plan_splits(tree, { absolute = true })

			expect(#commands).to.equal(1)
			expect(commands[1].size).to.equal(60)
		end)

		it("plans multiple splits for complex layout", function()
			local tree = {
				left = 0,
				top = 0,
				width = 100,
				height = 48,
				cwd = "/editor",
				is_active = true,
				is_zoomed = false,
				alt_screen_active = false,
				right = {
					left = 101,
					top = 0,
					width = 60,
					height = 24,
					cwd = "/terminal",
					is_active = false,
					is_zoomed = false,
					alt_screen_active = false,
					bottom = {
						left = 101,
						top = 25,
						width = 60,
						height = 24,
						cwd = "/output",
						is_active = false,
						is_zoomed = false,
						alt_screen_active = false,
					},
				},
			}
			local commands = core.plan_splits(tree, {})

			expect(#commands).to.equal(2)
			expect(commands[1].direction).to.equal("Right")
			expect(commands[1].cwd).to.equal("/terminal")
			expect(commands[2].direction).to.equal("Bottom")
			expect(commands[2].cwd).to.equal("/output")
		end)

		it("includes domain in split commands", function()
			local tree = {
				left = 0,
				top = 0,
				width = 80,
				height = 48,
				cwd = "/local",
				domain = "local",
				is_active = true,
				is_zoomed = false,
				alt_screen_active = false,
				right = {
					left = 81,
					top = 0,
					width = 80,
					height = 48,
					cwd = "/remote",
					domain = "SSH:server",
					is_active = false,
					is_zoomed = false,
					alt_screen_active = false,
				},
			}
			local commands = core.plan_splits(tree, {})

			expect(commands[1].domain).to.equal("SSH:server")
		end)
	end)

	---------------------------------------------------------------------------
	-- map() and fold() Tests
	---------------------------------------------------------------------------

	describe("map", function()
		it("returns nil for nil tree", function()
			local result = core.map(nil, function(n)
				return n
			end)
			expect(result).to_not.exist()
		end)

		it("applies function to all nodes", function()
			local tree = {
				left = 0,
				top = 0,
				width = 80,
				height = 48,
				cwd = "/a",
				is_active = true,
				is_zoomed = false,
				alt_screen_active = false,
				right = {
					left = 81,
					top = 0,
					width = 80,
					height = 48,
					cwd = "/b",
					is_active = false,
					is_zoomed = false,
					alt_screen_active = false,
				},
			}

			local visited = {}
			core.map(tree, function(n)
				visited[#visited + 1] = n.cwd
				return n
			end)

			expect(#visited).to.equal(2)
			expect(visited[1]).to.equal("/a")
			expect(visited[2]).to.equal("/b")
		end)
	end)

	describe("fold", function()
		it("returns accumulator for nil tree", function()
			local result = core.fold(nil, 42, function(acc, _)
				return acc + 1
			end)
			expect(result).to.equal(42)
		end)

		it("accumulates over all nodes", function()
			local tree = {
				left = 0,
				top = 0,
				width = 80,
				height = 48,
				cwd = "/a",
				is_active = true,
				is_zoomed = false,
				alt_screen_active = false,
				right = {
					left = 81,
					top = 0,
					width = 80,
					height = 48,
					cwd = "/b",
					is_active = false,
					is_zoomed = false,
					alt_screen_active = false,
					bottom = {
						left = 81,
						top = 25,
						width = 80,
						height = 24,
						cwd = "/c",
						is_active = false,
						is_zoomed = false,
						alt_screen_active = false,
					},
				},
			}

			local count = core.fold(tree, 0, function(acc, _)
				return acc + 1
			end)
			expect(count).to.equal(3)
		end)

		it("collects values correctly", function()
			local tree = {
				left = 0,
				top = 0,
				width = 80,
				height = 48,
				cwd = "/a",
				is_active = true,
				is_zoomed = false,
				alt_screen_active = false,
				bottom = {
					left = 0,
					top = 25,
					width = 80,
					height = 24,
					cwd = "/b",
					is_active = false,
					is_zoomed = false,
					alt_screen_active = false,
				},
			}

			local cwds = core.fold(tree, {}, function(acc, node)
				acc[#acc + 1] = node.cwd
				return acc
			end)

			expect(#cwds).to.equal(2)
			expect(cwds[1]).to.equal("/a")
			expect(cwds[2]).to.equal("/b")
		end)
	end)

	---------------------------------------------------------------------------
	-- Helper function tests
	---------------------------------------------------------------------------

	describe("compare_by_coord", function()
		it("sorts left-to-right first", function()
			local a = make_pane({ left = 0, top = 0 })
			local b = make_pane({ left = 100, top = 0 })
			expect(core.compare_by_coord(a, b)).to.equal(true)
			expect(core.compare_by_coord(b, a)).to.equal(false)
		end)

		it("sorts top-to-bottom when left is equal", function()
			local a = make_pane({ left = 0, top = 0 })
			local b = make_pane({ left = 0, top = 25 })
			expect(core.compare_by_coord(a, b)).to.equal(true)
			expect(core.compare_by_coord(b, a)).to.equal(false)
		end)
	end)

	describe("is_right", function()
		it("returns true when pane is to the right", function()
			local root = make_pane({ left = 0, width = 80 })
			local pane = make_pane({ left = 81 })
			expect(core.is_right(root, pane)).to.equal(true)
		end)

		it("returns false when pane is not to the right", function()
			local root = make_pane({ left = 0, width = 80 })
			local pane = make_pane({ left = 40 })
			expect(core.is_right(root, pane)).to.equal(false)
		end)
	end)

	describe("is_bottom", function()
		it("returns true when pane is below", function()
			local root = make_pane({ top = 0, height = 24 })
			local pane = make_pane({ top = 25 })
			expect(core.is_bottom(root, pane)).to.equal(true)
		end)

		it("returns false when pane is not below", function()
			local root = make_pane({ top = 0, height = 24 })
			local pane = make_pane({ top = 10 })
			expect(core.is_bottom(root, pane)).to.equal(false)
		end)
	end)
end)
