local spec = require('complete.misc.spec')
local CompletionService = require('complete.core.CompletionService')

describe('complete.core', function()
  describe('CompletionService', function()
    it('should work on basic case', function()
      local trigger_context, provider = spec.setup({
        input = 'w',
        buffer_text = {
          'key|',
        },
        items = {
          { label = 'keyword' },
          { label = 'dummy' }
        },
      })
      local state = {}
      do
        local service = CompletionService.new({
          provider_groups = {
            {
              {
                provider = provider
              }
            }
          }
        })
        service:on_update(function(payload_)
          state.payload = payload_
        end)
        service:complete(trigger_context)
      end
      assert.equals(#state.payload.matches, 1)
      assert.equals(state.payload.matches[1].item:get_insert_text(), 'keyword')
    end)
  end)
end)
