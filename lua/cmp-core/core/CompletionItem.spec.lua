local spec = require('cmp-core.core.spec')
local LSP = require('cmp-core.kit.LSP')
local Async = require('cmp-core.kit.Async')
local Keymap = require('cmp-core.kit.Vim.Keymap')

describe('cmp-core.core', function()
  describe('CompletionItem', function()
    it('should support dot-to-arrow completion (clangd)', function()
      local _, item = spec.setup({
        buffer_text = { 'obj.|' },
        item = {
          label = 'foo',
          textEdit = {
            newText = '->foo',
            range = {
              start = {
                line = 0,
                character = 3,
              },
              ['end'] = {
                line = 0,
                character = 4,
              },
            },
          },
        },
      })
      Keymap.spec(function()
        Keymap.send('i', 'in'):await()
        assert.equals(item:get_offset(), #'obj' + 1)
        assert.equals(item:get_select_text(), '->foo')
        assert.equals(item:get_filter_text(), '.foo')
        item:confirm():await()
        assert.equals('obj->foo', vim.api.nvim_get_current_line())
      end)
    end)

    it('should support symbol reference completion (typescript-language-server)', function()
      local _, item = spec.setup({
        buffer_text = { '[].|' },
        item = {
          label = 'Symbol',
          filterText = '.Symbol',
          textEdit = {
            newText = '[Symbol]',
            range = {
              start = {
                line = 0,
                character = 2,
              },
              ['end'] = {
                line = 0,
                character = 3,
              },
            },
          },
        },
      })
      Keymap.spec(function()
        Keymap.send('i', 'in'):await()
        assert.equals(item:get_offset(), #'[]' + 1)
        assert.equals(item:get_select_text(), '[Symbol]')
        assert.equals(item:get_filter_text(), '.Symbol')
        item:confirm():await()
        assert.equals('[][Symbol]', vim.api.nvim_get_current_line())
      end)
    end)

    it('should support indent fixing completion (vscode-html-language-server)', function()
      local _, item = spec.setup({
        buffer_text = {
          '<div>',
          '  <|>',
        },
        item = {
          label = '/div',
          filterText = '\t</div',
          textEdit = {
            newText = '</div',
            range = {
              start = {
                line = 0,
                character = 0,
              },
              ['end'] = {
                line = 0,
                character = 3,
              },
            },
          },
        },
      })
      Keymap.spec(function()
        Keymap.send('i', 'in'):await()
        assert.equals(item:get_offset(), #'  ' + 1)
        assert.equals(item:get_select_text(), '</div')
        assert.equals(item:get_filter_text(), '</div')
        item:confirm():await()
        assert.equals('</div>', vim.api.nvim_get_current_line())
      end)
    end)

    it('should support extreme additionalTextEdits completion (rust-analyzer)', function()
      local _, item = spec.setup({
        buffer_text = {
          'fn main() {',
          '  let s = ""',
          '    .|',
          '}',
        },
        item = {
          label = 'dbg',
          filterText = 'dbg',
          insertTextFormat = LSP.InsertTextFormat.Snippet,
          textEdit = {
            newText = 'dbg!("")',
            range = {
              start = {
                character = 5,
                line = 2,
              },
              ['end'] = {
                character = 8,
                line = 2,
              },
            },
          },
        },
        resolve = function(item)
          local clone = vim.tbl_deep_extend('keep', {}, item)
          clone.additionalTextEdits = {
            {
              newText = '',
              range = {
                start = {
                  character = 10,
                  line = 1,
                },
                ['end'] = {
                  character = 5,
                  line = 2,
                },
              },
            },
          }
          return Async.resolve(clone)
        end,
      })
      Keymap.spec(function()
        Keymap.send('i', 'in'):await()
        assert.equals(item:get_offset(), #'    .' + 1)
        assert.equals(item:get_select_text(), 'dbg!')
        assert.equals(item:get_filter_text(), 'dbg')
        item:confirm():await()
        assert.equals('  let s = dbg!("")', vim.api.nvim_get_current_line())
      end)
    end)
  end)
end)
