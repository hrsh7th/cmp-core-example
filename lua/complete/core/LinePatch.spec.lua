---@diagnostic disable: invisible
local spec = require('complete.spec')
local Keymap = require('complete.kit.Vim.Keymap')
local LinePatch = require('complete.core.LinePatch')
local TriggerContext = require('complete.core.TriggerContext')
local DefaultMatcher = require('complete.core.DefaultMatcher')

describe('complete.core', function()
  describe('LinePatch', function()
    for _, mode in ipairs({ 'i', 'c' }) do
      for _, fn in ipairs({ 'apply_by_func', 'apply_by_keys' }) do
        describe(('[%s] .%s'):format(mode, fn), function()
          it('should apply the insert-range patch', function()
            Keymap.spec(function()
              Keymap.send(mode == 'i' and 'i' or ':'):await()
              local trigger_context, provider = spec.setup({
                mode = mode,
                buffer_text = {
                  '(ins|ert)',
                },
                items = { {
                  label = 'inserted',
                } },
              })
              local bufnr = vim.api.nvim_get_current_buf()
              local match = provider:get_matches(trigger_context, DefaultMatcher.matcher)[1]
              local range = match.item:get_insert_range()
              local before = trigger_context.character - range.start.character
              local after = range['end'].character - trigger_context.character
              LinePatch[fn](bufnr, before, after, match.item:get_insert_text()):await()

              trigger_context = TriggerContext.create()
              assert.equals(trigger_context.text, '(insertedert)')
              assert.are.same({ trigger_context.line, trigger_context.character }, { 0, 9 })
            end)
          end)

          it('should apply the replace-range patch', function()
            Keymap.spec(function()
              Keymap.send(mode == 'i' and 'i' or ':'):await()
              local trigger_context, provider = spec.setup({
                mode = mode,
                buffer_text = {
                  '(ins|ert)',
                },
                items = { {
                  label = 'inserted',
                } },
              })
              local bufnr = vim.api.nvim_get_current_buf()
              local match = provider:get_matches(trigger_context, DefaultMatcher.matcher)[1]
              local range = (match.item:get_replace_range() or match.item._provider:get_default_replace_range())
              local before = trigger_context.character - range.start.character
              local after = range['end'].character - trigger_context.character
              LinePatch[fn](bufnr, before, after, match.item:get_insert_text()):await()

              trigger_context = TriggerContext.create()
              assert.equals(trigger_context.text, '(inserted)')
              assert.are.same({ trigger_context.line, trigger_context.character }, { 0, 9 })
            end)
          end)
        end)
      end
    end
  end)
end)
