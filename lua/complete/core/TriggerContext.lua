local Cache = require('complete.kit.App.Cache')
local RegExp = require('complete.kit.Vim.RegExp')

---The TriggerContext.
---@class complete.core.TriggerContext
---@field public mode string
---@field public line number 0-origin
---@field public character number 0-origin utf8 byte index
---@field public text string
---@field public force? boolean
---@field public trigger_character? string
---@field public cache complete.kit.App.Cache
local TriggerContext = {}
TriggerContext.__index = TriggerContext

---Create new TriggerContext from current state.
---@param reason? { force?: boolean, trigger_character?: string }
---@return complete.core.TriggerContext
function TriggerContext.create(reason)
  local mode = vim.api.nvim_get_mode().mode
  if mode == 'c' then
    return TriggerContext.new(mode, 0, vim.fn.getcmdpos() - 1, vim.fn.getcmdline(), reason)
  end
  local row1, col0 = unpack(vim.api.nvim_win_get_cursor(0))
  return TriggerContext.new(mode, row1 - 1, col0, vim.api.nvim_get_current_line(), reason)
end

---Create new TriggerContext.
---@param mode string
---@param line integer 0-origin
---@param character integer 0-origin
---@param text string
---@param reason? { force?: boolean, trigger_character?: string }
---@return complete.core.TriggerContext
function TriggerContext.new(mode, line, character, text, reason)
  local self = setmetatable({}, TriggerContext)
  self.mode = mode
  self.line = line
  self.character = character
  self.text = text
  self.force = not not (reason and reason.force)
  self.trigger_character = reason and reason.trigger_character
  self.cache = Cache.new()
  return self
end

---Get keyword offset.
---@param pattern string
---@return integer? 1-origin utf8 byte index
function TriggerContext:get_keyword_offset(pattern)
  return self.cache:ensure('get_keyword_offset:' .. pattern, function()
    local _, s = RegExp.extract_at(self.text, pattern, self.character + 1)
    if s then
      return s
    end
  end)
end

return TriggerContext
