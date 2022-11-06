local Context = require('cmp-core.Context')

local spec = {}

---@class cmp-core.spec.setup.config
---@field public text string[]

---@param config cmp-core.spec.setup.config
function spec.setup(config)
  vim.cmd.enew { bang = true, args = {} }
  vim.o.virtualedit = 'onemore'

  --Setup buffer text and cursor position.
  vim.api.nvim_buf_set_lines(0, 0, -1, false, config.text)
  for i = 1, #config.text do
    local s = config.text[i]:find('|', 1, true)
    if s then
      vim.api.nvim_win_set_cursor(0, { i, s - 1 })
      vim.cmd.normal { bang = true, args = { 'x' } }
    end
  end

  return Context.create()
end

return spec
