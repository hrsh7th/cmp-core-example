local Cache = require "cmp-core.kit.App.Cache"

---The Context.
---@class cmp-core.Context
---@field public row number
---@field public col number
---@field public text string
---@field public cache cmp-core.kit.App.Cache
local Context = {}
Context.__index = Context

---Create new Context.
---@param row integer 0-origin
---@param col integer 0-origin
---@param text string
---@return cmp-core.Context
function Context.new(row, col, text)
  local self = setmetatable({}, Context)
  self.row = row
  self.col = col
  self.text = text
  self.cache = Cache.new()
  return self
end

---Create new Context from current state.
---@return cmp-core.Context
function Context.create()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  return Context.new(row - 1, col, vim.api.nvim_get_current_line())
end

return Context
