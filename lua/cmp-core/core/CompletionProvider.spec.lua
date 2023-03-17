local kit = require('cmp-core.kit')
local Async = require('cmp-core.kit.Async')
local Keymap = require('cmp-core.kit.Vim.Keymap')
local LineContext = require('cmp-core.core.LineContext')
local CompletionProvider = require('cmp-core.core.CompletionProvider')

---@class cmp-core.core.CompletionProvider.spec.Option
---@field public keyword_pattern? string
---@field public incomplete? boolean

---@param option? cmp-core.core.CompletionProvider.spec.Option
---@return cmp-core.core.CompletionProvider, fun(response: cmp-core.kit.LSP.CompletionList)
local function create_provider(option)
  option = option or {}
  local provider = CompletionProvider.new({
    get_keyword_pattern = function(_)
      return option.keyword_pattern or [[\%(-\?\d\+\%(\.\d\+\)\?\|\h\w*\%(-\w*\)*\)]]
    end,
    complete = function(_)
      return Async.resolve({
        items = {},
        isIncomplete = option.incomplete,
      })
    end,
  })
  return provider, function(response)
    ---@diagnostic disable-next-line: invisible
    provider._list = response
  end
end

describe('cmp-core.core', function()
  describe('CompletionProvider', function()
    it('should determine completion timing', function()
      local provider, response = create_provider()
      Keymap.spec(function()
        Keymap.send('i'):await()
        -- should not complete.
        assert.is_nil(provider:_create_completion_context(LineContext.create(), false))
        Keymap.send(' '):await()
        assert.is_nil(provider:_create_completion_context(LineContext.create(), false))

        -- keyword_pattern -> keyword_pattern.
        Keymap.send('f'):await()
        assert.are_not.is_nil(provider:_create_completion_context(LineContext.create(), false))
        assert.is_nil(provider:_create_completion_context(LineContext.create(), false))

        -- isIncomplete=true
        response({ isIncomplete = true })
        Keymap.send('o'):await()
        assert.are_not.is_nil(provider:_create_completion_context(LineContext.create(), false))

        -- isIncomplete=false -> force=true
        response({ isIncomplete = false })
        Keymap.send('o'):await()
        assert.is_nil(provider:_create_completion_context(LineContext.create(), false))
        assert.are_not.is_nil(provider:_create_completion_context(LineContext.create(), true))
      end)
    end)
  end)
end)
