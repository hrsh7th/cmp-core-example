local spec = require('cmp-core.core.spec')
local LSP = require('cmp-core.kit.LSP')
local Async = require('cmp-core.kit.Async')
local Keymap = require('cmp-core.kit.Vim.Keymap')

describe('cmp-core.core', function()
  describe('CompletionItem', function()
    local function get_input(context, item)
      return vim.api.nvim_get_current_line():sub(item:get_offset(), context.character)
    end

    it('should support dot-to-arrow completion (clangd)', function()
      local context, item = spec.setup({
        input = 'p',
        buffer_text = { 'obj.|for' },
        item = {
          label = 'prop',
          textEdit = {
            newText = '->prop',
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
        Keymap.send('i'):await()
        assert.equals(item:get_offset(), #'obj' + 1)
        assert.equals(get_input(context, item), '.p')
        assert.equals(item:get_filter_text(), '.prop')
        assert.equals(item:get_select_text(), '->prop')
        item:confirm({ replace = true }):await()
        assert.equals('obj->prop', vim.api.nvim_get_current_line())
      end)
    end)

    it('should support symbol reference completion (typescript-language-server)', function()
      local context, item = spec.setup({
        input = 'S',
        buffer_text = { '[].|foo' },
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
        Keymap.send('i'):await()
        assert.equals(item:get_offset(), #'[]' + 1)
        assert.equals(get_input(context, item), '.S')
        assert.equals(item:get_filter_text(), '.Symbol')
        assert.equals(item:get_select_text(), '[Symbol]')
        item:confirm({ replace = true }):await()
        assert.equals('[][Symbol]', vim.api.nvim_get_current_line())
      end)
    end)

    it('should support indent fixing completion (vscode-html-language-server)', function()
      local context, item = spec.setup({
        input = 'd',
        buffer_text = {
          '<div>',
          '  </|foo>',
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
        Keymap.send('i'):await()
        assert.equals(item:get_offset(), #'  ' + 1)
        assert.equals(get_input(context, item), '</d')
        assert.equals(item:get_select_text(), '</div')
        assert.equals(item:get_filter_text(), '</div')
        item:confirm({ replace = true }):await()
        assert.equals('</div>', vim.api.nvim_get_current_line())
      end)
    end)

    it('should support extreme additionalTextEdits completion (rust-analyzer)', function()
      local context, item = spec.setup({
        input = 'd',
        buffer_text = {
          'fn main() {',
          '  let s = ""',
          '    .|foo',
          '}',
        },
        item = {
          label = 'dbg',
          filterText = 'dbg',
          insertTextFormat = LSP.InsertTextFormat.Snippet,
          textEdit = {
            newText = 'dbg!("")',
            insert = {
              start = {
                character = 5,
                line = 2,
              },
              ['end'] = {
                character = 8,
                line = 2,
              },
            },
            replace = {
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
        Keymap.send('i'):await()
        assert.equals(item:get_offset(), #'    .' + 1)
        assert.equals(get_input(context, item), 'd')
        assert.equals(item:get_select_text(), 'dbg!')
        assert.equals(item:get_filter_text(), 'dbg')
        item:confirm({ replace = true }):await()
        assert.equals('  let s = dbg!("")', vim.api.nvim_get_current_line())
      end)
    end)
  end)
end)
