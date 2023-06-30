local Cache = require('cmp-core.kit.App.Cache')
local RegExp = require('cmp-core.kit.Vim.RegExp')

---The LineContext.
---@class cmp-core.core.LineContext
---@field public line number 0-origin
---@field public character number 0-origin utf8 byte index
---@field public text string
---@field public char string
---@field public cache cmp-core.kit.App.Cache
local LineContext = {}
LineContext.__index = LineContext

---Create new LineContext.
---@param line integer 0-origin
---@param character integer 0-origin
---@param text string
---@return cmp-core.core.LineContext
function LineContext.new(line, character, text)
  local self = setmetatable({}, LineContext)
  self.line = line
  self.character = character
  self.text = text
  self.char = text:sub(character, character)
  self.cache = Cache.new()
  return self
end

---Get keyword offset.
---@param pattern string
---@return integer? 1-origin utf8 byte index
function LineContext:get_keyword_offset(pattern)
  return self.cache:ensure('get_keyword_offset:' .. pattern, function()
    local _, s = RegExp.extract_at(self.text, pattern, self.character + 1)
    if s then
      return s
    end
  end)
end

---Create new LineContext from current state.
---TODO: This isn't support cmdline.
---@return cmp-core.core.LineContext
function LineContext.create()
  local mode = vim.api.nvim_get_mode().mode
  if mode == 'c' then
    return LineContext.new(0, vim.fn.getcmdpos() - 1, vim.fn.getcmdline())
  end
  local line1, character = unpack(vim.api.nvim_win_get_cursor(0))
  return LineContext.new(line1 - 1, character, vim.api.nvim_get_current_line())
end

return LineContext
