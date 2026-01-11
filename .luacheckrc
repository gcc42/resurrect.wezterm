-- Luacheck configuration
globals = {
    "describe",
    "it",
    "before",
    "after",
    "expect",
    "wezterm",
    "mux",
    "_",  -- Lua convention for unused loop variable
}

-- Ignore certain warnings globally
ignore = {
    "212",  -- unused argument
}

max_line_length = 120

-- Type definition files are stubs that define types for LuaLS
-- The variables are used as type annotations, not accessed at runtime
files["**/types/*.lua"] = {
    ignore = {
        "311",  -- value assigned is overwritten
        "211",  -- unused variable (type stubs)
    },
}

-- Test spec files can have unused variables for setup
files["**/spec/*.lua"] = {
    ignore = { "211" },  -- unused variable
}

-- Test fakes may have variables used for state tracking
files["**/fakes/*.lua"] = {
    ignore = {
        "311",  -- value assigned is overwritten
        "211",  -- unused variable
    },
}

-- Test utility files
files["**/test_*.lua"] = {
    ignore = { "211" },  -- unused variable
}
