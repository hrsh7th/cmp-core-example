local Cache = require('cmp-core.kit.App.Cache')

---The LineContext.
---@class cmp-core.LineContext
---@field public character number 0-origin utf8 byte index
---@field public text string
---@field public cache cmp-core.kit.App.Cache
local LineContext = {}
LineContext.__index = LineContext

---Create new LineContext.
---@param character integer 0-origin
---@param text string
---@return cmp-core.LineContext
function LineContext.new(character, text)
  local self = setmetatable({}, LineContext)
  self.character = character
  self.text = text
  self.cache = Cache.new()
  return self
end

---Create new LineContext from current state.
---TODO: This isn't support cmdline.
---@return cmp-core.LineContext
function LineContext.create()
  local mode = vim.api.nvim_get_mode().mode
  if mode == 'c' then
    return LineContext.new(vim.fn.getcmdpos() - 1, vim.fn.getcmdline())
  end
  local _, character = unpack(vim.api.nvim_win_get_cursor(0))
  return LineContext.new(character, vim.api.nvim_get_current_line())
end

return LineContext
