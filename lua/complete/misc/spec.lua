local LSP = require('complete.kit.LSP')
local CompletionProvider = require('complete.core.CompletionProvider')
local TriggerContext = require('complete.core.TriggerContext')
local Async = require('complete.kit.Async')
local assert = require('luassert')
local LinePatch = require('complete.core.LinePatch')

local spec = {}

---@class complete.core.spec.setup.Option
---@field public buffer_text string[]
---@field public mode? 'i' | 'c'
---@field public input? string
---@field public keyword_pattern? string
---@field public position_encoding_kind? complete.kit.LSP.PositionEncodingKind
---@field public resolve? fun(item: complete.kit.LSP.CompletionItem): complete.kit.Async.AsyncTask complete.kit.LSP.CompletionItem
---@field public item_defaults? complete.kit.LSP.CompletionList.itemDefaults
---@field public item? complete.kit.LSP.CompletionItem

---Reset test environment.
function spec.reset()
  --Create buffer.
  vim.cmd.enew({ bang = true, args = {} })
  vim.o.virtualedit = 'onemore'
  vim.o.swapfile = false
end

---@param option complete.core.spec.setup.Option
---@return complete.core.TriggerContext, complete.core.CompletionProvider
function spec.setup(option)
  option.mode = option.mode or 'i'

  --Reset test environment.
  spec.reset()

  --Setup context and buffer text and cursor position.
  if option.mode == 'i' then
    vim.api.nvim_buf_set_lines(0, 0, -1, false, option.buffer_text)
    for i = 1, #option.buffer_text do
      local s = option.buffer_text[i]:find('|', 1, true)
      if s then
        vim.api.nvim_win_set_cursor(0, { i, s - 1 })
        vim.api.nvim_set_current_line((option.buffer_text[i]:gsub('|', '')))
        break
      end
    end
  elseif option.mode == 'c' then
    local pos = option.buffer_text[1]:find('|', 1, true)
    local text = option.buffer_text[1]:gsub('|', '')
    vim.fn.setcmdline(text, pos)
  end

  local target_item = option.item or { label = 'dummy' }

  -- Create completion provider with specified item.
  local provider = CompletionProvider.new({
    initialize = function(_, params)
      params.configure({
        keyword_pattern = option.keyword_pattern or [[\%(-\?\d\+\%(\.\d\+\)\?\|\h\w*\%(-\w*\)*\)]],
        completion_options = {
          triggerCharacters = { '.' }
        }
      })
    end,
    get_position_encoding_kind = function(_)
      return option.position_encoding_kind or LSP.PositionEncodingKind.UTF8
    end,
    resolve = function(_, item)
      if not option.resolve then
        return Async.resolve(item)
      end
      return option.resolve(item)
    end,
    complete = function(_)
      return Async.resolve({
        items = { target_item },
        itemDefaults = option.item_defaults,
        isIncomplete = false,
      })
    end,
  })
  provider:complete(TriggerContext.create()):sync()

  -- Insert filtering query after request.
  if option.input then
    LinePatch.apply_by_func(vim.api.nvim_get_current_buf(), 0, 0, option.input):sync()
  end

  ---@diagnostic disable-next-line: invisible
  return TriggerContext.create(), provider
end

---@param buffer_text string[]
function spec.assert(buffer_text)
  ---@type { [1]: integer, [2]: integer }
  local cursor = vim.api.nvim_win_get_cursor(0)
  for i = 1, #buffer_text do
    local s = buffer_text[i]:find('|', 1, true)
    if s then
      cursor[1] = i
      cursor[2] = s - 1
      buffer_text[i] = buffer_text[i]:gsub('|', '')
      break
    end
  end

  local ok1, err1 = pcall(function()
    assert.are.same(buffer_text, vim.api.nvim_buf_get_lines(0, 0, -1, false))
  end)
  local ok2, err2 = pcall(function()
    assert.are.same(cursor, vim.api.nvim_win_get_cursor(0))
  end)
  if not ok1 or not ok2 then
    local err = ''
    if err1 then
      if type(err1) == 'string' then
        err = err .. '\n' .. err1
      else
        ---@diagnostic disable-next-line: need-check-nil
        err = err .. err1.message
      end
    end
    if err2 then
      if type(err2) == 'string' then
        err = err .. '\n' .. err2
      else
        ---@diagnostic disable-next-line: need-check-nil
        err = err .. err2.message
      end
    end
    error(err, 2)
  end
end

return spec
