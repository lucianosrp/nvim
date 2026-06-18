-- "dank" — follows DankMaterialShell when present, otherwise a quiet no-op.
-- DMS (matugenTemplateNeovim) regenerates lua/plugins/dankcolors.lua on every
-- theme change; this scheme auto-discovers that file, applies it (reusing DMS's
-- own base16 mapping + overrides) and live re-applies when it changes. On a
-- machine without DMS the file is absent, so this silently falls back to "teal"
-- — the config stays fully agnostic and never errors. Nothing DMS owns is touched.

local dms_theme = vim.fn.stdpath("config") .. "/lua/plugins/dankcolors.lua"

-- Fall back to teal cleanly. Deferred because invoking :colorscheme from inside
-- a colorscheme file is re-entrant — doing it inline leaves teal half-applied
-- and unsets colors_name. Scheduling runs it as a clean top-level switch.
local function use_teal()
  vim.schedule(function() vim.cmd.colorscheme("teal") end)
end

-- Auto-discover: no DankMaterialShell theme on this machine → quietly use teal.
if not vim.uv.fs_stat(dms_theme) then
  use_teal()
  return
end

vim.cmd("highlight clear")
if vim.fn.exists("syntax_on") == 1 then
  vim.cmd("syntax reset")
end

-- (Re)arm a watcher on the DMS file so theme changes apply live. Re-armed on
-- every apply because DMS replaces the file atomically (stale inode otherwise).
-- Assigning it to _G._matugen_theme_watcher also suppresses the duplicate
-- watcher dankcolors.lua arms internally, so they never fight.
if _G.__dank_watch then
  pcall(function() _G.__dank_watch:stop() end)
end
_G.__dank_watch = vim.uv.new_fs_event()
_G._matugen_theme_watcher = _G.__dank_watch
if _G.__dank_watch then
  _G.__dank_watch:start(dms_theme, {}, vim.schedule_wrap(function(err)
    if err then return end
    local now = vim.uv.now()
    if _G.__dank_last and now - _G.__dank_last < 300 then return end
    _G.__dank_last = now
    -- only re-apply while dank is the active scheme, so switching away isn't
    -- yanked back when DMS changes colors
    if vim.g.colors_name == "dank" then vim.cmd.colorscheme("dank") end
  end))
end

-- Apply DMS's generated palette (base16 setup + overrides). Every failure path
-- falls back to teal SILENTLY, so a missing engine or malformed file never
-- throws on :colorscheme.
pcall(vim.cmd, "packadd base16-nvim")
local ok, spec = pcall(dofile, dms_theme)
if not (ok and type(spec) == "table" and spec[1] and type(spec[1].config) == "function") then
  use_teal()
  return
end
if not pcall(spec[1].config) then
  use_teal()
  return
end
vim.g.colors_name = "dank"
