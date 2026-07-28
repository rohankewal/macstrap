-- Static — installed once by install.sh, not regenerated per theme switch.
-- Applies whatever palette is currently linked at macstrap/theme.lua to a
-- baseline set of highlight groups. Re-run `:luafile` on this file (or
-- restart Neovim) after switching themes to pick up new colors.
local ok, theme = pcall(require, "macstrap.theme")
if not ok then
  return
end

local c = theme.colors
local hl = vim.api.nvim_set_hl

vim.o.termguicolors = true

hl(0, "Normal", { fg = c.fg, bg = c.bg })
hl(0, "NormalFloat", { fg = c.fg, bg = c.bg_alt })
hl(0, "Comment", { fg = c.fg_muted, italic = true })
hl(0, "Constant", { fg = c.magenta })
hl(0, "String", { fg = c.green })
hl(0, "Identifier", { fg = c.blue })
hl(0, "Function", { fg = c.blue, bold = true })
hl(0, "Statement", { fg = c.red })
hl(0, "Keyword", { fg = c.red })
hl(0, "PreProc", { fg = c.cyan })
hl(0, "Type", { fg = c.yellow })
hl(0, "Special", { fg = c.accent })
hl(0, "Underlined", { fg = c.accent, underline = true })
hl(0, "Todo", { fg = c.bg, bg = c.yellow, bold = true })
hl(0, "Error", { fg = c.fg, bg = c.red })
hl(0, "CursorLine", { bg = c.bg_alt })
hl(0, "CursorLineNr", { fg = c.accent, bold = true })
hl(0, "LineNr", { fg = c.fg_muted })
hl(0, "Visual", { bg = c.black })
hl(0, "StatusLine", { fg = c.fg, bg = c.bg_alt })
hl(0, "StatusLineNC", { fg = c.fg_muted, bg = c.bg_alt })
hl(0, "VertSplit", { fg = c.bg_alt })
hl(0, "WinSeparator", { fg = c.bg_alt })
hl(0, "Pmenu", { fg = c.fg, bg = c.bg_alt })
hl(0, "PmenuSel", { fg = c.bg, bg = c.accent })
hl(0, "SignColumn", { bg = c.bg })
hl(0, "DiffAdd", { fg = c.green })
hl(0, "DiffDelete", { fg = c.red })
hl(0, "DiffChange", { fg = c.yellow })
