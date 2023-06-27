local Async = require('cmp-core.kit.Async')
local Keymap = require('cmp-core.kit.Vim.Keymap')
local LineContext = require('cmp-core.core.LineContext')
local CompletionProvider = require('cmp-core.core.CompletionProvider')

---@class cmp-core.core.CompletionProvider.spec.Option
---@field public keyword_pattern? string

---@param option? cmp-core.core.CompletionProvider.spec.Option
---@return cmp-core.core.CompletionProvider, fun(response: cmp-core.kit.LSP.CompletionList)
local function create_provider(option)
  option = option or {}

  local response ---@type cmp-core.kit.LSP.CompletionList
  local provider = CompletionProvider.new({
    get_keyword_pattern = function(_)
      return option.keyword_pattern or [[\%(-\?\d\+\%(\.\d\+\)\?\|\h\w*\%(-\w*\)*\)]]
    end,
    complete = function(_)
      return Async.resolve(response)
    end,
  })
  ---@param response_ cmp-core.kit.LSP.CompletionList
  return provider, function(response_)
    response = response_
  end
end

describe('cmp-core.core', function()
  describe('CompletionProvider', function()
    it('should determine completion timing', function()
      local provider, response = create_provider()
      Keymap.spec(function()
        Keymap.send('i'):await()
        -- should not complete.
        assert.is_nil(provider:complete(LineContext.create(), false):await())
        Keymap.send(' '):await()
        assert.is_nil(provider:complete(LineContext.create(), false):await())

        -- keyword_pattern -> keyword_pattern.
        Keymap.send('f'):await()
        response({ isIncomplete = true, items = {} })
        assert.are_not.is_nil(provider:complete(LineContext.create(), false):await())

        -- isIncomplete=true
        Keymap.send('o'):await()
        response({ isIncomplete = false, items = {} })
        assert.are_not.is_nil(provider:complete(LineContext.create(), false):await())

        -- isIncomplete=false -> force=true
        Keymap.send('o'):await()
        assert.are_not.is_nil(provider:complete(LineContext.create(), true):await())

        -- isIncomplete=false -> force=false
        Keymap.send('o'):await()
        assert.is_nil(provider:complete(LineContext.create(), false):await())
      end)
    end)
  end)
end)
