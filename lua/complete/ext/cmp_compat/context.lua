local pattern = require('complete.ext.cmp_compat.pattern')
local types = require('complete.ext.cmp_compat.types')
local cache = require('complete.ext.cmp_compat.cache')
local misc = require('complete.ext.cmp_compat.misc')
local api = require('complete.ext.cmp_compat.api')

local context = {}

context.empty = function()
  local ctx = context.new({}) -- dirty hack to prevent recursive call `context.empty`.
  ctx.bufnr = -1
  ctx.input = ''
  ctx.cursor = {}
  ctx.cursor.row = -1
  ctx.cursor.col = -1
  return ctx
end

context.new = function(prev_context, option)
  option = option or {}

  local self = setmetatable({}, { __index = context })
  self.id = tostring(vim.uv.hrtime())
  self.cache = cache.new()
  self.prev_context = prev_context or context.empty()
  self.option = option or { reason = types.cmp.ContextReason.None }
  self.filetype = vim.api.nvim_get_option_value('filetype', { buf = 0 })
  self.time = vim.loop.now()
  self.bufnr = vim.api.nvim_get_current_buf()

  local cursor = api.get_cursor()
  self.cursor_line = api.get_current_line()
  self.cursor = {}
  self.cursor.row = cursor[1]
  self.cursor.col = cursor[2] + 1
  self.cursor.line = self.cursor.row - 1
  self.cursor.character = misc.to_utfindex(self.cursor_line, self.cursor.col)
  self.cursor_before_line = string.sub(self.cursor_line, 1, self.cursor.col - 1)
  self.cursor_after_line = string.sub(self.cursor_line, self.cursor.col)
  self.aborted = false
  return self
end

context.abort = function(self)
  self.aborted = true
end

context.get_reason = function(self)
  return self.option.reason
end

context.get_offset = function(self, keyword_pattern)
  return self.cache:ensure({ 'get_offset', keyword_pattern, self.cursor_before_line }, function()
    return pattern.offset([[\%(]] .. keyword_pattern .. [[\)\m$]], self.cursor_before_line) or self.cursor.col
  end)
end

context.changed = function(self, ctx)
  local curr = self

  if curr.bufnr ~= ctx.bufnr then
    return true
  end
  if curr.cursor.row ~= ctx.cursor.row then
    return true
  end
  if curr.cursor.col ~= ctx.cursor.col then
    return true
  end
  if curr:get_reason() == types.cmp.ContextReason.Manual then
    return true
  end

  return false
end

---Shallow clone
context.clone = function(self)
  local cloned = {}
  for k, v in pairs(self) do
    cloned[k] = v
  end
  return cloned
end

return context
