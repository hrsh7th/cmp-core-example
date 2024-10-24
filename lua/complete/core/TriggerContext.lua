local RegExp           = require('complete.kit.Vim.RegExp')

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
local TriggerContext   = {}
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
  return setmetatable({
    mode = mode,
    line = line,
    character = character,
    text = text,
    bufnr = bufnr,
    time = vim.loop.now(),
    force = not not (reason and reason.force),
    trigger_character = reason and reason.trigger_character,
    cache = {},
  }, TriggerContext)
end

---Get query text.
---@param offset integer
---@return string
function TriggerContext:get_query(offset)
  return self.text:sub(offset, self.character)
end

---Check if trigger context is changed.
---@param new_trigger_context complete.core.TriggerContext
---@return boolean
function TriggerContext:changed(new_trigger_context)
  if new_trigger_context.force then
    return true
  end

  if self.trigger_character ~= new_trigger_context.trigger_character then
    return true
  end

  if self.mode ~= new_trigger_context.mode then
    return true
  end

  if self.line ~= new_trigger_context.line then
    return true
  end

  if self.character ~= new_trigger_context.character then
    return true
  end

  if self.text ~= new_trigger_context.text then
    return true
  end

  if self.bufnr ~= new_trigger_context.bufnr then
    return true
  end

  return false
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
