local tailwindcss_fixture = require('complete.misc.spec.fixtures.tailwindcss')

local spec = require('complete.misc.spec')
local CompletionService = require('complete.core.CompletionService')
local TriggerContext = require('complete.core.TriggerContext')

local function run(name, fn)
  collectgarbage('collect')
  collectgarbage('stop')
  local s = os.clock()
  fn()
  local e = os.clock()
  print(('[%s]: elapsed time: %.2fsec, memory: %skb'):format(name, e - s, collectgarbage('count')))
  print('\n')
  collectgarbage('restart')
end

describe('complete.misc.spec.benchmark', function()
  it('tailwindcss', function()
    spec.start_profile()
    local _, provider = spec.setup({
      input = 'g:',
      buffer_text = {
        '|',
      },
      item_defaults = tailwindcss_fixture.itemDefaults,
      is_incomplete = tailwindcss_fixture.isIncomplete,
      items = tailwindcss_fixture.items,
    })
    local service = CompletionService.new({
      provider_groups = {
        {
          {
            provider = provider
          }
        }
      }
    })

    for i = 0, 3 do
      run(('tailwindcss: %s'):format(i), function()
        for _ = 0, 20 do
          service:complete(TriggerContext.create({ force = true }))
        end
      end)
    end
    spec.print_profile()
  end)
end)
