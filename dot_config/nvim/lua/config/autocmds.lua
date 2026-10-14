vim.api.nvim_clear_autocmds({ group = "lazyvim_wrap_spell" })
vim.api.nvim_create_autocmd("FileType", {
  group = "lazyvim_wrap_spell",
  pattern = { "text", "plaintex", "typst", "gitcommit", "markdown" },
  callback = function()
    vim.opt_local.wrap = true
    vim.opt_local.spell = false
  end,
})
