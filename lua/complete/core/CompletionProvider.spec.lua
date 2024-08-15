local spec = require('complete.misc.spec')
local Async = require('complete.kit.Async')
local Keymap = require('complete.kit.Vim.Keymap')
local TriggerContext = require('complete.core.TriggerContext')
local CompletionProvider = require('complete.core.CompletionProvider')

---@class complete.core.CompletionProvider.spec.Option
---@field public keyword_pattern? string

---@param option? complete.core.CompletionProvider.spec.Option
---@return complete.core.CompletionProvider, { set_response: fun(response: complete.kit.LSP.CompletionList) }
local function create_provider(option)
  option = option or {}

  local response ---@type complete.kit.LSP.CompletionList
  local provider = CompletionProvider.new({
    configure = function(_, configure)
      configure({
        keyword_pattern = option.keyword_pattern or [[\%(-\?\d\+\%(\.\d\+\)\?\|\h\w*\%(-\w*\)*\)]],
        completion_options = {
          triggerCharacters = { '.' }
        }
      })
    end,
    complete = function(_)
      return Async.resolve(response)
    end,
  })
  return provider, {
    ---@param response_ complete.kit.LSP.CompletionList
    set_response = function(response_)
      response = response_
    end,
  }
end

describe('complete.core', function()
  describe('CompletionProvider', function()
    it('should determine completion timing', function()
      spec.reset()

      local provider, ctx = create_provider()
      Keymap.spec(function()
        Keymap.send('i'):await()
        assert.is_nil(provider:complete(TriggerContext.create()):await())

        -- should not complete.
        Keymap.send(' '):await()
        assert.is_nil(provider:complete(TriggerContext.create()):await())

        -- keyword_pattern -> keyword_pattern.
        Keymap.send('f'):await()
        ctx.set_response({ isIncomplete = true, items = {} })
        assert.are_not.is_nil(provider:complete(TriggerContext.create()):await())

        -- isIncomplete=true
        Keymap.send('o'):await()
        ctx.set_response({ isIncomplete = false, items = {} })
        assert.are_not.is_nil(provider:complete(TriggerContext.create()):await())

        -- isIncomplete=false -> force=true
        Keymap.send('o'):await()
        assert.are_not.is_nil(provider:complete(TriggerContext.create({ force = true })):await())

        -- isIncomplete=false -> force=false
        Keymap.send('o'):await()
        assert.is_nil(provider:complete(TriggerContext.create()):await())

        -- isIncomplete=false -> trigger_character
        Keymap.send('o'):await()
        assert.are_not.is_nil(provider:complete(TriggerContext.create({ trigger_character = '.' })):await())
      end)
    end)
  end)
end)
