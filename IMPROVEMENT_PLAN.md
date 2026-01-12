# Critical Code Review & Improvement Plan

## Executive Summary

Reviewed the four files that weren't substantially refactored in recent commits:
- `fuzzy_loader.lua` - UI for selecting saved states
- `encryption.lua` - Encryption/decryption utilities
- `file_io.lua` - Low-level file operations
- `utils.lua` - Cross-platform utilities

Current test suite: **149 passed, 30 failed** (179 total)

---

## Critical Review by File

### 1. `fuzzy_loader.lua` (357 lines)

#### Issues

**A. Platform-Specific Code Smell (Lines 58-159)**
- Windows uses VBScript with temp files (70+ lines of embedded VBS)
- Mac uses `find | xargs stat`
- Linux uses `find -printf | awk`

Problems:
- VBS temp file cleanup isn't atomic (lines 129-132) - if process crashes, temp files remain
- No error handling if temp directory isn't writable
- The VBScript approach spawns multiple processes (launcher VBS -> main VBS)
- Shell injection risk on Mac/Linux - `base_path` is interpolated into shell commands without proper escaping

**B. Non-Deterministic Behavior**
- `os.date()` behavior varies by platform (line 187 comment mentions Mac epoch differs)
- `utils.get_current_window_width()` depends on GUI state

**C. Mixed Responsibilities**
- File discovery, parsing, formatting, and UI presentation all in one module
- The `insert_choices` function (lines 166-313) is 150 lines doing too many things:
  - Parsing stdout
  - Calculating formatting costs
  - Truncating filenames
  - Building UI choices

**D. Hardcoded Magic Numbers**
- Line 264: `min_filename_size = 10`
- Line 258: `6` (InputSelector margin)
- Line 33: `32000` and `150000` character limits (actually in encryption.lua)

**E. No Test Coverage**
- Zero tests for fuzzy_loader.lua
- Cannot be tested without mocking WezTerm's InputSelector

---

### 2. `encryption.lua` (108 lines)

#### Issues

**A. Error Handling Inconsistency**
- `encrypt()` calls `error()` on failure (line 87)
- `decrypt()` calls `error()` on failure (line 101)
- But callers use `pcall()` - this works but error messages lose context

**B. Platform Detection Logic is Fragile (Lines 23-67)**
- Windows branch checks `#input < 32000` - magic number
- Unix branch checks `#input < 150000` - magic number
- No documentation on why these limits exist
- The fallback branch (lines 43-67) uses `io.popen` twice - once to check stderr, once to write

**C. Command Construction Vulnerabilities**
- Line 73: `file_path:gsub(" ", "\\ ")` - naive space escaping
- Doesn't handle other special characters (`$`, `` ` ``, `"`, `'`, etc.)
- If `pub.method` contains special characters, command injection is possible

**D. State Mutation**
- `pub.public_key` and `pub.private_key` are module-level mutable state
- No validation that keys exist before encrypt/decrypt is called

**E. No Test Coverage**
- Zero tests for encryption.lua
- Would need to mock `wezterm.run_child_process` and `wezterm.shell_join_args`

---

### 3. `file_io.lua` (130 lines)

#### Issues

**A. Inconsistent Error Return Patterns**
- `write_file()` returns `(bool, error_string)` - good
- `read_file()` returns `(bool, stdout_or_error)` - overloaded second return value
- `load_json()` returns `table|nil` - no error information

**B. Missing Error Propagation**
- `write_state()` (line 73): On encryption failure, emits event but doesn't return failure status
- `load_json()`: If `io.lines()` fails (file doesn't exist), it throws instead of returning nil
- Line 116-119: Uses `io.lines()` without pcall protection

**C. Redundant Sanitization**
- `sanitize_json()` is called both on write (line 76) AND on read (line 124)
- If we sanitize on write, why sanitize again on read?

**D. Event Emission Side Effects**
- `sanitize_json()` emits events (lines 61, 66) - surprising for a pure transformation
- Events are named `resurrect.file_io.sanitize_json.*` but function is local

**E. Encryption State Management**
- `pub.encryption = { enable = false }` initialized at module load
- `set_encryption()` mutates it by requiring and modifying another module (line 49)
- This creates tight coupling between file_io and encryption modules

**F. Limited Test Coverage**
- `file_io.write_state` and `file_io.load_json` are tested indirectly via shell/io
- Direct tests would be more robust

---

### 4. `utils.lua` (330 lines)

#### Issues

**A. Platform Detection at Module Load (Lines 6-8)**
```lua
utils.is_windows = wezterm.target_triple == "x86_64-pc-windows-msvc"
utils.is_mac = (wezterm.target_triple == "x86_64-apple-darwin" or ...)
```
- Doesn't account for ARM Windows (`aarch64-pc-windows-msvc`)
- Good for Mac (handles both x86 and ARM)

**B. `execute()` Function Uses `io.popen` (Lines 145-160)**
- `io.popen()` doesn't capture stderr - silent failures
- No timeout mechanism
- Return value doesn't distinguish "command failed" from "command succeeded but returned empty"

**C. `path_exists()` Implementation (Lines 170-195)**
- Uses `os.rename(path, path)` as primary check - clever but fragile
- Fallback spawns `cmd.exe` or `test` - expensive for hot paths
- On Windows, constructs command string that could fail with special characters

**D. `create_single_directory()` Uses Shell Commands (Lines 204-220)**
- Could use `lfs.mkdir()` if LuaFileSystem is available
- Windows: `cmd.exe /c mkdir` is slower than direct API
- No handling for race conditions (two processes creating same directory)

**E. `utf8len()` Implementation is Correct but Unclear (Lines 136-139)**
```lua
local _, len = str:gsub("[%z\1-\127\194-\244][\128-\191]*", "")
```
- Works correctly (verified via testing)
- But the implementation is non-obvious - gsub replacement count equals character count
- Could benefit from a comment explaining the technique

**F. `tbl_deep_extend()` Complexity (Lines 276-327)**
- 50 lines for table merge - could be simpler
- The "error" behavior creates a closure on every call
- Recursive call to `tbl_deep_extend` in loop (line 311) creates deep stack

**G. Limited Test Coverage**
- No dedicated utils_spec.lua
- Only tested indirectly through other modules

---

## Test Coverage Gaps

| File | Direct Tests | Indirect Tests | Risk |
|------|--------------|----------------|------|
| `fuzzy_loader.lua` | None | None | **HIGH** - UI code untested |
| `encryption.lua` | None | None | **HIGH** - Security code untested |
| `file_io.lua` | Partial | Via io_spec | Medium |
| `utils.lua` | None | Via other specs | Medium |

### Failing Tests (30 failures)

1. **Missing Fake Implementation** (5 failures)
   - `mux.rename_workspace` not implemented in fake
   - `mux.set_active_workspace` not implemented in fake

2. **Malformed Data Handling** (5 failures)
   - Tests expect restore to succeed with malformed data
   - Code currently fails - unclear if tests or code is wrong

---

## Recommended Improvements

### Phase 1: Critical Fixes (Safety/Correctness)

1. **Fix command injection in encryption.lua**
   - Use `wezterm.shell_join_args()` consistently
   - Or use array-based command execution

2. **Fix shell injection in fuzzy_loader.lua**
   - Properly escape `base_path` before shell interpolation
   - Or use wezterm APIs instead of shell commands

3. **Add pcall protection to file_io.load_json()**
   - Wrap `io.lines()` to handle missing files gracefully

### Phase 2: Test Coverage

1. **Add utils_spec.lua**
   - Test path normalization functions (already pure)
   - Test `utf8len`, `deepcopy`, `tbl_deep_extend`
   - Test `strip_format_esc_seq`, `replace_center`

2. **Add encryption_spec.lua**
   - Mock `wezterm.run_child_process`
   - Test encrypt/decrypt command construction
   - Test error handling paths

3. **Fix existing test failures**
   - Implement missing mux fake methods
   - Clarify expected behavior for malformed data

4. **Add file_io_spec.lua**
   - Direct tests for `write_file`, `read_file`
   - Test `sanitize_json` edge cases
   - Test encryption integration

### Phase 3: Refactoring

1. **Extract file discovery from fuzzy_loader.lua**
   - Create `shell/file_discovery.lua`
   - Pure function to parse output into structured data
   - Separate module for platform-specific file listing

2. **Simplify insert_choices() in fuzzy_loader.lua**
   - Split into smaller functions:
     - `parse_file_list(stdout)` -> list of file records
     - `calculate_formatting(files, opts)` -> formatting metadata
     - `format_choices(files, metadata, opts)` -> UI choices

3. **Unify error handling patterns**
   - All I/O functions return `(result, error)` tuple
   - Never use `error()` for expected failures
   - Use result types consistently

4. **Make encryption.lua stateless**
   - Pass config as parameter instead of module state
   - Makes testing easier, prevents global state bugs

### Phase 4: Robustness

1. **Add input validation**
   - Validate state structures before save/restore
   - Fail fast with clear error messages

2. **Add retry logic for transient failures**
   - File operations can fail due to locks
   - Directory creation race conditions

3. **Improve platform detection**
   - Handle ARM Windows
   - Consider using feature detection over platform detection

---

## Priority Matrix

| Improvement | Impact | Effort | Priority |
|-------------|--------|--------|----------|
| Fix command injection (encryption) | High | Low | **P0** |
| Fix shell injection (fuzzy_loader) | High | Low | **P0** |
| Add pcall to load_json | Medium | Low | **P0** |
| Fix failing tests | Medium | Medium | **P1** |
| Add utils_spec.lua | High | Medium | **P1** |
| Add encryption_spec.lua | High | Medium | **P1** |
| Extract file discovery | Medium | High | **P2** |
| Simplify insert_choices | Medium | High | **P2** |
| Stateless encryption | Low | Medium | **P3** |
| Retry logic | Low | Medium | **P3** |

---

## Conclusion

The codebase has a good architectural foundation (functional core / imperative shell), but the files that weren't refactored have accumulated technical debt:

1. **Security issues** - Shell command injection vulnerabilities in encryption.lua and fuzzy_loader.lua
2. **Zero test coverage** for critical modules (encryption, fuzzy_loader)
3. **Mixed responsibilities** in fuzzy_loader.lua (150-line function doing 4+ things)
4. **Inconsistent error handling** across file I/O functions
5. **30 failing tests** that need fixing (missing fake implementations + unclear expectations)

The recommended approach is to first fix the P0 security issues, then improve test coverage (P1), before undertaking larger refactoring (P2/P3).
