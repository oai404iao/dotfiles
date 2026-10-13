local specs = dofile(arg[1])
if arg[2] == "disabled" then
  assert(#specs == 0)
  return
end
assert(#specs == 2)
assert(specs[1][1] == "AvengeMedia/base46")
assert(specs[1].lazy == true)
assert(type(specs[1].opts) == "table")
assert(specs[2][1] == "LazyVim/LazyVim")

local original_readable = vim.fn.filereadable
local original_colorscheme = vim.cmd.colorscheme
local selected
vim.cmd.colorscheme = function(theme)
  selected = theme
end
for readable, theme in pairs({ [0] = "tokyonight", [1] = "dms" }) do
  vim.fn.filereadable = function(path)
    assert(path == vim.fn.stdpath("config") .. "/colors/dms.lua")
    return readable
  end
  specs[2].opts.colorscheme()
  assert(selected == theme)
end
vim.fn.filereadable = original_readable
vim.cmd.colorscheme = original_colorscheme
print("DMS Neovim selection and fresh-machine fallback passed")
