local tailwindcss_fixture = require('complete.spec.fixtures.tailwindcss')

local spec = require('complete.spec')
local CompletionService = require('complete.core.CompletionService')
local TriggerContext = require('complete.core.TriggerContext')

local function run(name, fn)
  collectgarbage('collect')
  collectgarbage('stop')
  local s = vim.uv.hrtime() / 1000000
  fn()
  local e = vim.uv.hrtime() / 1000000
  print(('[%s]: elapsed time: %sms, memory: %skb'):format(name, e - s, collectgarbage('count')))
  print('\n')
  collectgarbage('restart')
end

describe('complete.misc.spec.benchmark', function()
  local input = function(text)
    local cursor = vim.api.nvim_win_get_cursor(0)
    vim.api.nvim_buf_set_text(0, cursor[1] - 1, cursor[2], cursor[1] - 1, cursor[2], { text })
    vim.api.nvim_win_set_cursor(0, { cursor[1], cursor[2] + #text })
  end
  for _, isIncomplete in ipairs({ true, false }) do
    it(('isIncomplete=%s'):format(isIncomplete), function()
      local response = tailwindcss_fixture()
      local _, provider = spec.setup({
        buffer_text = {
          '|',
        },
        item_defaults = response.itemDefaults,
        is_incomplete = response.isIncomplete,
        items = response.items,
      })
      local service = CompletionService.new({})
      service:register_provider(provider)
      for i = 1, 3 do
        vim.cmd.enew()
        run(('isIncomplete=%s: %s'):format(isIncomplete, i), function()
          input('')
          service:complete(TriggerContext.create({ force = true }))
          input('g')
          service:complete(TriggerContext.create())
          input('r')
          service:complete(TriggerContext.create())
          input('o')
          service:complete(TriggerContext.create())
          input('u')
          service:complete(TriggerContext.create())
          input('p')
          service:complete(TriggerContext.create())
        end)
      end
    end)
  end
end)
