local spec = require('cmp-core.core.spec')
local Keymap = require('cmp-core.kit.Vim.Keymap')
local LinePatch = require('cmp-core.core.LinePatch')

describe('cmp-core.core', function()
  describe('LinePatch', function()
    for _, fn in ipairs({ 'apply_by_func', 'apply_by_keys' }) do
      describe('.' .. fn, function()
        it('should apply the insert-range patch (i)', function()
          Keymap.spec(function()
            Keymap.send('i'):await()
            local context, item = spec.setup({
              buffer_text = {
                '(ins|ert)',
              },
              item = {
                label = 'concat',
              },
            })
            local range = (item:get_insert_range() or item._provider:get_default_insert_range())
            local before = context.character - range.start.character
            local after = range['end'].character - context.character
            LinePatch[fn](before, after, item:get_insert_text()):await()
            assert.equals(vim.api.nvim_get_current_line(), '(concatert)')
            assert.are.same(vim.api.nvim_win_get_cursor(0), { 1, 7 })
          end)
        end)

        it('should apply the replace-range patch (i)', function()
          Keymap.spec(function()
            Keymap.send('i'):await()
            local context, item = spec.setup({
              buffer_text = {
                '(ins|ert)',
              },
              item = {
                label = 'concat',
              },
            })
            local range = (item:get_replace_range() or item._provider:get_default_replace_range())
            local before = context.character - range.start.character
            local after = range['end'].character - context.character
            LinePatch[fn](before, after, item:get_insert_text()):await()
            assert.equals(vim.api.nvim_get_current_line(), '(concat)')
            assert.are.same(vim.api.nvim_win_get_cursor(0), { 1, 7 })
          end)
        end)

        it('should apply the insert-range patch (c)', function()
          Keymap.spec(function()
            Keymap.send(':'):await()
            local context, item = spec.setup({
              mode = 'c',
              buffer_text = {
                '(ins|ert)',
              },
              item = {
                label = 'concat',
              },
            })
            local range = (item:get_insert_range() or item._provider:get_default_insert_range())
            local before = context.character - range.start.character
            local after = range['end'].character - context.character
            LinePatch[fn](before, after, item:get_insert_text()):await()
            assert.equals(vim.fn.getcmdline(), '(concatert)')
            assert.are.same(vim.fn.getcmdpos(), 8)
          end)
        end)

        it('should apply the replace-range patch (c)', function()
          Keymap.spec(function()
            Keymap.send(':'):await()
            local context, item = spec.setup({
              mode = 'c',
              buffer_text = {
                '(ins|ert)',
              },
              item = {
                label = 'concat',
              },
            })
            local range = (item:get_replace_range() or item._provider:get_default_replace_range())
            local before = context.character - range.start.character
            local after = range['end'].character - context.character
            LinePatch[fn](before, after, item:get_insert_text()):await()
            assert.equals(vim.fn.getcmdline(), '(concat)')
            assert.are.same(vim.fn.getcmdpos(), 8)
          end)
        end)
      end)
    end
  end)
end)
