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
              provider = provider,
            },
          },
        },
      })

      local bufnr = vim.api.nvim_get_current_buf()
      for i = 1, 3 do
        run(('isIncomplete=%s: %s'):format(isIncomplete, i), function()
          vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '' })
          service:complete(TriggerContext.create())
          vim.api.nvim_buf_set_text(bufnr, 0, 0, 0, 0, { 'g' })
          service:complete(TriggerContext.create({ trigger_character = 'g' }))
          vim.api.nvim_buf_set_text(bufnr, 0, 1, 0, 1, { 'r' })
          service:complete(TriggerContext.create({ trigger_character = 'r' }))
          vim.api.nvim_buf_set_text(bufnr, 0, 2, 0, 2, { 'o' })
          service:complete(TriggerContext.create({ trigger_character = 'o' }))
          vim.api.nvim_buf_set_text(bufnr, 0, 3, 0, 3, { 'u' })
          service:complete(TriggerContext.create({ trigger_character = 'u' }))
          vim.api.nvim_buf_set_text(bufnr, 0, 4, 0, 4, { 'p' })
          service:complete(TriggerContext.create({ trigger_character = 'p' }))
        end)
      end
      spec.print_profile()
    end)
  end
end)
