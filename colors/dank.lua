-- "dank" — follows DankMaterialShell/matugen when present, otherwise a quiet
-- no-op. Reads the Material You palette matugen generates for DMS
-- (~/.local/state/quickshell/user/generated/colors.json) and maps its color
-- ROLES onto the same structure as colors/teal.lua — distinct accents for
-- functions / types / keywords / strings — instead of the old base16 route
-- that painted everything in shades of primary. Re-applies live when matugen
-- regenerates the palette (wallpaper or light/dark change). On a machine
-- without DMS the file is absent → silently falls back to "teal", so the
-- config stays fully agnostic and never errors.

local palette_json = (vim.env.XDG_STATE_HOME or (vim.env.HOME .. "/.local/state"))
  .. "/quickshell/user/generated/colors.json"

-- Fall back to teal cleanly. Deferred because invoking :colorscheme from inside
-- a colorscheme file is re-entrant — doing it inline leaves teal half-applied
-- and unsets colors_name. Scheduling runs it as a clean top-level switch.
local function use_teal()
  vim.schedule(function() vim.cmd.colorscheme("teal") end)
end

local function load_palette()
  local f = io.open(palette_json, "r")
  if not f then return nil end
  local raw = f:read("*a")
  f:close()
  local ok, p = pcall(vim.json.decode, raw)
  if ok and type(p) == "table" and p.primary and p.surface then return p end
end

-- Auto-discover: no DankMaterialShell palette on this machine → quietly use teal.
local p = load_palette()
if not p then
  use_teal()
  return
end

-- (Re)arm a watcher so wallpaper / light-dark changes restyle nvim instantly.
-- Re-armed on every apply because matugen replaces the file (stale inode
-- otherwise). Debounced: one regeneration can fire several fs events.
if _G.__dank_watch then
  pcall(function() _G.__dank_watch:stop() end)
end
_G.__dank_watch = vim.uv.new_fs_event()
if _G.__dank_watch then
  _G.__dank_watch:start(palette_json, {}, vim.schedule_wrap(function(err)
    if err then return end
    local now = vim.uv.now()
    if _G.__dank_last and now - _G.__dank_last < 300 then return end
    _G.__dank_last = now
    -- only re-apply while dank is the active scheme, so switching away isn't
    -- yanked back when DMS changes colors
    if vim.g.colors_name == "dank" then vim.cmd.colorscheme("dank") end
  end))
end

-- --------------------------------------------------------------------------
-- Tiny color math: blend two hex colors (t = weight of `fg` over `bg`) for
-- the derived tints (diff backgrounds, dim line numbers), and a luminance
-- check so light-mode palettes flip &background correctly.
-- --------------------------------------------------------------------------
local function rgb(hex)
  return tonumber(hex:sub(2, 3), 16), tonumber(hex:sub(4, 5), 16), tonumber(hex:sub(6, 7), 16)
end
local function blend(fg, bg, t)
  local fr, fg_, fb = rgb(fg)
  local br, bg_, bb = rgb(bg)
  return string.format("#%02x%02x%02x",
    math.floor(fr * t + br * (1 - t) + 0.5),
    math.floor(fg_ * t + bg_ * (1 - t) + 0.5),
    math.floor(fb * t + bb * (1 - t) + 0.5))
end
local function luminance(hex)
  local r, g, b = rgb(hex)
  return (0.299 * r + 0.587 * g + 0.114 * b) / 255
end

-- Start from a clean slate (see colors/teal.lua for why), inherit structure
-- from the built-in scheme, then layer the Material roles on top.
vim.cmd("highlight clear")
if vim.fn.exists("syntax_on") == 1 then vim.cmd("syntax reset") end
vim.o.background = luminance(p.surface) < 0.5 and "dark" or "light"
vim.cmd.colorscheme("default")
vim.g.colors_name = "dank"

local set = vim.api.nvim_set_hl
-- Git "added" green: Material palettes have no green role, and add/delete
-- must stay semantically green/red whatever the wallpaper. Fixed per mode.
local git_green = vim.o.background == "dark" and "#9ece6a" or "#2e7d32"

-- UI accents (backgrounds on UI chrome are stripped by the transparent()
-- autocmd in init.lua; only non-stripped groups get a bg here).
set(0, "CursorLineNr", { fg = p.primary, bold = true })
set(0, "CursorLine", { bg = p.surface_container })
set(0, "Visual", { bg = p.secondary_container })
set(0, "PmenuSel", { fg = p.on_primary, bg = p.primary, bold = true })
set(0, "MatchParen", { fg = p.primary, bold = true })
set(0, "Comment", { fg = p.outline, italic = true })
set(0, "LineNr", { fg = blend(p.outline, p.surface, 0.55) })
set(0, "WinSeparator", { fg = p.outline_variant })
set(0, "FloatBorder", { fg = p.outline_variant })
set(0, "FloatTitle", { fg = p.primary, bold = true })
set(0, "Title", { fg = p.primary, bold = true })
set(0, "Directory", { fg = p.tertiary })
set(0, "Search", { fg = p.on_primary_container, bg = p.primary_container })
set(0, "CurSearch", { fg = p.on_primary, bg = p.primary })
set(0, "IncSearch", { fg = p.on_primary, bg = p.primary })
set(0, "DiagnosticError", { fg = p.error })

-- Git sign colors.
set(0, "GitSignsAdd", { fg = git_green })
set(0, "GitSignsChange", { fg = p.tertiary })
set(0, "GitSignsDelete", { fg = p.error })

-- Diff (diffview / vimdiff): tint the line BACKGROUND only, never the
-- foreground — so syntax highlighting stays readable on changed lines.
-- Blended from the palette, so the tints adapt to light mode too.
set(0, "DiffAdd", { bg = blend(git_green, p.surface, 0.16) })
set(0, "DiffDelete", { bg = blend(p.error, p.surface, 0.16) })
set(0, "DiffChange", { bg = blend(p.tertiary, p.surface, 0.10) })
set(0, "DiffText", { bg = blend(p.tertiary, p.surface, 0.30) })

-- Syntax: the three Material accents + error, spread across roles the way
-- teal.lua spreads its six. primary (the wallpaper accent) goes to functions —
-- the tokens you scan for. on_*_container are the mode-adaptive pale tints
-- (light text on dark, dark text on light), used where teal uses green/amber.
local roles = {
  { p.primary, { "Function", "@function", "@function.call", "@function.method", "@function.builtin" } },
  { p.tertiary, { "Type", "@type", "@type.builtin", "@constructor", "@module" } },
  { p.secondary, { "Keyword", "Statement", "Conditional", "Repeat", "@keyword", "@keyword.function", "@keyword.return" } },
  { p.on_tertiary_container or p.tertiary, { "String", "@string", "Character" } },
  { p.on_primary_container or p.primary, { "Number", "Boolean", "@number", "@boolean", "@constant.builtin" } },
  { p.error, { "@variable.member", "@property", "@field" } },
  { p.on_surface_variant, { "Operator", "Delimiter", "@punctuation.bracket", "@punctuation.delimiter" } },
}
for _, role in ipairs(roles) do
  local color, groups = role[1], role[2]
  if color then
    for _, g in ipairs(groups) do
      set(0, g, { fg = color })
    end
  end
end
