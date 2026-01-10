-- Pre-built pane layout fixtures for testing
-- These fixtures define common pane layouts with expected pane tree structures

local fixtures = {}

--------------------------------------------------------------------------------
-- Single Pane (simplest case)
--------------------------------------------------------------------------------

fixtures.single_pane = {
    panes = {
        {
            left = 0,
            top = 0,
            width = 160,
            height = 48,
            cwd = "/home/user",
            is_active = true,
        },
    },
    expected_tree = {
        left = 0,
        top = 0,
        width = 160,
        height = 48,
        cwd = "/home/user",
        is_active = true,
        right = nil,
        bottom = nil,
    },
}

--------------------------------------------------------------------------------
-- Horizontal Split (two panes side by side)
--  ┌─────────┬─────────┐
--  │  left   │  right  │
--  │         │         │
--  └─────────┴─────────┘
--------------------------------------------------------------------------------

fixtures.hsplit = {
    panes = {
        {
            left = 0,
            top = 0,
            width = 80,
            height = 48,
            cwd = "/home",
            is_active = true,
        },
        {
            left = 81,
            top = 0,
            width = 80,
            height = 48,
            cwd = "/tmp",
        },
    },
    expected_tree = {
        left = 0,
        top = 0,
        width = 80,
        height = 48,
        cwd = "/home",
        is_active = true,
        right = {
            left = 81,
            top = 0,
            width = 80,
            height = 48,
            cwd = "/tmp",
        },
        bottom = nil,
    },
}

--------------------------------------------------------------------------------
-- Vertical Split (two panes stacked)
--  ┌─────────────────────┐
--  │        top          │
--  ├─────────────────────┤
--  │       bottom        │
--  └─────────────────────┘
--------------------------------------------------------------------------------

fixtures.vsplit = {
    panes = {
        {
            left = 0,
            top = 0,
            width = 160,
            height = 24,
            cwd = "/home",
            is_active = true,
        },
        {
            left = 0,
            top = 25,
            width = 160,
            height = 24,
            cwd = "/var/log",
        },
    },
    expected_tree = {
        left = 0,
        top = 0,
        width = 160,
        height = 24,
        cwd = "/home",
        right = nil,
        bottom = {
            left = 0,
            top = 25,
            width = 160,
            height = 24,
            cwd = "/var/log",
        },
    },
}

--------------------------------------------------------------------------------
-- IDE Layout (editor + terminal column)
--  ┌─────────┬─────────┐
--  │         │ terminal│
--  │ editor  ├─────────┤
--  │         │ output  │
--  └─────────┴─────────┘
--------------------------------------------------------------------------------

fixtures.ide_layout = {
    panes = {
        {
            left = 0,
            top = 0,
            width = 100,
            height = 48,
            cwd = "/project",
            is_active = true,
        },
        {
            left = 101,
            top = 0,
            width = 60,
            height = 24,
            cwd = "/project",
        },
        {
            left = 101,
            top = 25,
            width = 60,
            height = 24,
            cwd = "/project",
        },
    },
    expected_tree = {
        left = 0,
        top = 0,
        width = 100,
        height = 48,
        cwd = "/project",
        right = {
            left = 101,
            top = 0,
            width = 60,
            height = 24,
            cwd = "/project",
            bottom = {
                left = 101,
                top = 25,
                width = 60,
                height = 24,
                cwd = "/project",
            },
        },
    },
}

--------------------------------------------------------------------------------
-- Three-way Horizontal Split
--  ┌───────┬───────┬───────┐
--  │ left  │ middle│ right │
--  └───────┴───────┴───────┘
--------------------------------------------------------------------------------

fixtures.three_way_hsplit = {
    panes = {
        {
            left = 0,
            top = 0,
            width = 53,
            height = 48,
            cwd = "/a",
            is_active = true,
        },
        {
            left = 54,
            top = 0,
            width = 53,
            height = 48,
            cwd = "/b",
        },
        {
            left = 108,
            top = 0,
            width = 53,
            height = 48,
            cwd = "/c",
        },
    },
    expected_tree = {
        left = 0,
        top = 0,
        width = 53,
        height = 48,
        cwd = "/a",
        right = {
            left = 54,
            top = 0,
            width = 53,
            height = 48,
            cwd = "/b",
            right = {
                left = 108,
                top = 0,
                width = 53,
                height = 48,
                cwd = "/c",
            },
        },
    },
}

--------------------------------------------------------------------------------
-- With Scrollback Content
--------------------------------------------------------------------------------

fixtures.with_scrollback = {
    panes = {
        {
            left = 0,
            top = 0,
            width = 160,
            height = 48,
            cwd = "/home",
            text = "$ ls\nfile1.txt\nfile2.txt\n$ ",
            is_active = true,
        },
    },
}

--------------------------------------------------------------------------------
-- Multi-Domain (local + SSH pane)
--------------------------------------------------------------------------------

fixtures.multi_domain = {
    panes = {
        {
            left = 0,
            top = 0,
            width = 80,
            height = 48,
            cwd = "/home",
            domain = "local",
            is_active = true,
        },
        {
            left = 81,
            top = 0,
            width = 80,
            height = 48,
            cwd = "/remote",
            domain = "SSH:server",
        },
    },
}

--------------------------------------------------------------------------------
-- With Alt Screen Active (running vim, etc.)
--------------------------------------------------------------------------------

fixtures.with_alt_screen = {
    panes = {
        {
            left = 0,
            top = 0,
            width = 160,
            height = 48,
            cwd = "/project",
            alt_screen = true,
            process = {
                name = "vim",
                argv = { "vim", "file.txt" },
                cwd = "/project",
                executable = "/usr/bin/vim",
            },
            is_active = true,
        },
    },
}

--------------------------------------------------------------------------------
-- Zoomed Pane
--------------------------------------------------------------------------------

fixtures.zoomed_pane = {
    panes = {
        {
            left = 0,
            top = 0,
            width = 80,
            height = 48,
            cwd = "/home",
            is_zoomed = true,
            is_active = true,
        },
        {
            left = 81,
            top = 0,
            width = 80,
            height = 48,
            cwd = "/tmp",
        },
    },
}

--------------------------------------------------------------------------------
-- Empty CWD (edge case)
--------------------------------------------------------------------------------

fixtures.empty_cwd = {
    panes = {
        {
            left = 0,
            top = 0,
            width = 160,
            height = 48,
            cwd = "",
            is_active = true,
        },
    },
}

--------------------------------------------------------------------------------
-- Complex Grid (2x2)
--  ┌─────────┬─────────┐
--  │   TL    │   TR    │
--  ├─────────┼─────────┤
--  │   BL    │   BR    │
--  └─────────┴─────────┘
--------------------------------------------------------------------------------

fixtures.grid_2x2 = {
    panes = {
        {
            left = 0,
            top = 0,
            width = 80,
            height = 24,
            cwd = "/tl",
            is_active = true,
        },
        {
            left = 81,
            top = 0,
            width = 80,
            height = 24,
            cwd = "/tr",
        },
        {
            left = 0,
            top = 25,
            width = 80,
            height = 24,
            cwd = "/bl",
        },
        {
            left = 81,
            top = 25,
            width = 80,
            height = 24,
            cwd = "/br",
        },
    },
}

--------------------------------------------------------------------------------
-- Helper: Create state object from fixture
--------------------------------------------------------------------------------

function fixtures.to_workspace_state(fixture, workspace_name, window_title, tab_title)
    -- Ensure the expected_tree has is_active set
    local pane_tree = fixture.expected_tree
    if pane_tree and not pane_tree.is_active then
        -- Make a shallow copy and set is_active
        pane_tree = {}
        for k, v in pairs(fixture.expected_tree) do
            pane_tree[k] = v
        end
        pane_tree.is_active = true
    end

    return {
        workspace = workspace_name or "test",
        window_states = {
            {
                title = window_title or "main",
                tabs = {
                    {
                        title = tab_title or "tab",
                        is_active = true,
                        pane_tree = pane_tree,
                    },
                },
                size = {
                    cols = 160,
                    rows = 48,
                    pixel_width = 1600,
                    pixel_height = 960,
                },
            },
        },
    }
end

return fixtures
