-- "teal" — the house colorscheme: the built-in dark "default" scheme with
-- teal-leaning syntax accents. Transparency is applied separately by the
-- ColorScheme autocmd in init.lua, so this file only sets colors. Pick it (and
-- any installed theme) via <leader>uc.
-- Start from a clean slate: switching FROM another theme leaves its highlight
-- groups set, and re-loading "default" alone does not fully reset them (Comment
-- keeps its italic, Normal/LineNr keep their fg, etc.). Clear first.
vim.cmd("highlight clear")
if vim.fn.exists("syntax_on") == 1 then vim.cmd("syntax reset") end
vim.cmd.colorscheme("default") -- inherit structure from the built-in scheme
vim.g.colors_name = "teal"

local accent = {
  teal = "#2dd4bf",
  cyan = "#22d3ee",
  green = "#9ece6a",
  purple = "#c4b5fd",
  amber = "#e0af68",
  rose = "#f7768e",
}
local set = vim.api.nvim_set_hl

-- UI accents.
set(0, "CursorLineNr", { fg = accent.teal, bold = true })
set(0, "CursorLine", { bg = "#11201f" })
set(0, "Visual", { bg = "#1f3b3b" })
set(0, "PmenuSel", { fg = "#0b1416", bg = accent.teal, bold = true })
set(0, "MatchParen", { fg = accent.amber, bold = true })

-- Git sign colors to match the palette.
set(0, "GitSignsAdd", { fg = accent.green })
set(0, "GitSignsChange", { fg = accent.teal })
set(0, "GitSignsDelete", { fg = accent.rose })

-- Diff (diffview / vimdiff): tint the line BACKGROUND only, never the
-- foreground — so syntax highlighting stays readable on changed lines.
set(0, "DiffAdd", { bg = "#16331f" }) -- added line  -> green tint
set(0, "DiffDelete", { bg = "#3a191e" }) -- removed line -> red tint
set(0, "DiffChange", { bg = "#1b2433" }) -- changed line -> subtle slate
set(0, "DiffText", { bg = "#2b5066" }) -- changed words within a line

-- Syntax: applies to both classic groups and Treesitter @captures.
local colors = {
  [accent.cyan] = { "Function", "@function", "@function.call", "@function.method", "@function.builtin" },
  [accent.teal] = { "Type", "@type", "@type.builtin", "@constructor", "@module" },
  [accent.purple] = { "Keyword", "Statement", "Conditional", "Repeat", "@keyword", "@keyword.function", "@keyword.return" },
  [accent.green] = { "String", "@string", "Character" },
  [accent.amber] = { "Number", "Boolean", "@number", "@boolean", "@constant.builtin" },
  [accent.rose] = { "@variable.member", "@property", "@field" },
}
for color, groups in pairs(colors) do
  for _, g in ipairs(groups) do
    set(0, g, { fg = color })
  end
end
