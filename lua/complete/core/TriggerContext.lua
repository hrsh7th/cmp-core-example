local RegExp = require('complete.kit.Vim.RegExp')

---The TriggerContext.
---@class complete.core.TriggerContext
---@field public mode string
---@field public line integer 0-origin
---@field public character integer 0-origin utf8 byte index
---@field public text string
---@field public bufnr integer
---@field public time integer
---@field public force? boolean
---@field public trigger_character? string
---@field public cache table<string, any>
local TriggerContext = {}
TriggerContext.__index = TriggerContext

---Create new TriggerContext from current state.
---@param reason? { force?: boolean, trigger_character?: string }
---@return complete.core.TriggerContext
function TriggerContext.create(reason)
  local mode = vim.api.nvim_get_mode().mode --[[@as string]]
  local bufnr = vim.api.nvim_get_current_buf()
  if mode == 'c' then
    return TriggerContext.new(mode, 0, vim.fn.getcmdpos() - 1, vim.fn.getcmdline(), bufnr, reason)
  end
  local row1, col0 = unpack(vim.api.nvim_win_get_cursor(0))
  return TriggerContext.new(mode, row1 - 1, col0, vim.api.nvim_get_current_line(), bufnr, reason)
end

---Create new TriggerContext.
---@param mode string
---@param line integer 0-origin
---@param character integer 0-origin
---@param text string
---@param bufnr integer
---@param reason? { force?: boolean, trigger_character?: string }
---@return complete.core.TriggerContext
function TriggerContext.new(mode, line, character, text, bufnr, reason)
  local self = setmetatable({}, TriggerContext)
  self.mode = mode
  self.line = line
  self.character = character
  self.text = text
  self.bufnr = bufnr
  self.time = vim.loop.now()
  self.force = not not (reason and reason.force)
  self.trigger_character = reason and reason.trigger_character
  self.cache = {}
  return self
end

---Get keyword offset.
---@param pattern string
---@return integer? 1-origin utf8 byte index
function TriggerContext:get_keyword_offset(pattern)
  local cache_key = string.format('%s:%s', 'get_keyword_offset', pattern)
  if not self.cache[cache_key] then
    local _, s = RegExp.extract_at(self.text, pattern, self.character + 1)
    if s then
      self.cache[cache_key] = s
    end
  end
  return self.cache[cache_key]
end

return TriggerContext
