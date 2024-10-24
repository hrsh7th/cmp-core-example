local tailwindcss_fixture = require('complete.spec.fixtures.tailwindcss')

local spec = require('complete.spec')
local CompletionService = require('complete.core.CompletionService')
local TriggerContext = require('complete.core.TriggerContext')
local DefaultSorter = require('complete.ext.DefaultSorter')
local DefaultMatcher = require('complete.ext.DefaultMatcher')

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
  for _, isIncomplete in ipairs({ true, false }) do
    it(('isIncomplete=%s'):format(isIncomplete), function()
      spec.start_profile()
      local _, provider = spec.setup({
        buffer_text = {
          '|',
        },
        item_defaults = tailwindcss_fixture.itemDefaults,
        is_incomplete = isIncomplete,
        items = tailwindcss_fixture.items,
      })
      local service = CompletionService.new({
        sorter = DefaultSorter.sorter,
        matcher = DefaultMatcher.matcher,
        provider_groups = {
          {
            {
              provider = provider
            }
          }
        }
      })

      local bufnr = vim.api.nvim_get_current_buf()
      for i = 1, 3 do
        run(('isIncomplete=%s: %s'):format(isIncomplete, i), function()
          service:complete(TriggerContext.new('i', 0, 0, '', bufnr))
          service:complete(TriggerContext.new('i', 0, 1, 'g', bufnr))
          service:complete(TriggerContext.new('i', 0, 2, 'gr', bufnr))
          service:complete(TriggerContext.new('i', 0, 3, 'gro', bufnr))
          service:complete(TriggerContext.new('i', 0, 4, 'grou', bufnr))
          service:complete(TriggerContext.new('i', 0, 5, 'group', bufnr))
        end)
      end
      spec.print_profile()
    end)
  end
end)
