---@diagnostic disable: invisible
local spec           = require('complete.misc.spec')
local Keymap         = require('complete.kit.Vim.Keymap')
local LinePatch      = require('complete.core.LinePatch')
local DefaultMatcher = require('complete.ext.DefaultMatcher')

describe('complete.core', function()
  describe('LinePatch', function()
    for _, fn in ipairs({ 'apply_by_func', 'apply_by_keys' }) do
      describe('.' .. fn, function()
        it('should apply the insert-range patch (i)', function()
          Keymap.spec(function()
            Keymap.send('i'):await()
            local trigger_context, provider = spec.setup({
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
            assert.equals(vim.api.nvim_get_current_line(), '(insertedert)')
            assert.are.same(vim.api.nvim_win_get_cursor(0), { 1, 9 })
          end)
        end)

        it('should apply the replace-range patch (i)', function()
          Keymap.spec(function()
            Keymap.send('i'):await()
            local trigger_context, provider = spec.setup({
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
            assert.equals(vim.api.nvim_get_current_line(), '(inserted)')
            assert.are.same(vim.api.nvim_win_get_cursor(0), { 1, 9 })
          end)
        end)

        it('should apply the insert-range patch (c)', function()
          Keymap.spec(function()
            Keymap.send(':'):await()
            local trigger_context, provider = spec.setup({
              mode = 'c',
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
            assert.equals(vim.fn.getcmdline(), '(insertedert)')
            assert.are.same(vim.fn.getcmdpos(), 10)
          end)
        end)

        it('should apply the replace-range patch (c)', function()
          Keymap.spec(function()
            Keymap.send(':'):await()
            local trigger_context, provider = spec.setup({
              mode = 'c',
              buffer_text = {
                '(ins|ert)',
              },
              items = { {
                label = 'inserted',
              } },
            })
            local bufnr = vim.api.nvim_get_current_buf()
            local match = provider:get_matches(trigger_context, DefaultMatcher.matcher)[1]
            local range = (match.item:get_replace_range() or match.provider:get_default_replace_range())
            local before = trigger_context.character - range.start.character
            local after = range['end'].character - trigger_context.character
            LinePatch[fn](bufnr, before, after, match.item:get_insert_text()):await()
            assert.equals(vim.fn.getcmdline(), '(inserted)')
            assert.are.same(vim.fn.getcmdpos(), 10)
          end)
        end)
      end)
    end
  end)
end)
