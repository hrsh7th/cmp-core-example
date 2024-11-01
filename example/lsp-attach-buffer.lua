local Async = require('complete.kit.Async')
local Client = require('complete.kit.LSP.Client')
local CompletionService = require('complete.core.CompletionService')
local CompletionProvider = require('complete.core.CompletionProvider')
local DefaultMatcher = require('complete.ext.DefaultMatcher')
local DefaultSorter = require('complete.ext.DefaultSorter')
local DefaultView = require('complete.ext.DefaultView')

local bufnr = vim.api.nvim_get_current_buf()

local ok, cmp = pcall(require, 'cmp')
if ok then
  cmp.setup.buffer { enabled = false }
end

---Create complete.core.CompletionSource from active clients.
---@type complete.core.CompletionSource[]
local sources = vim.iter(vim.lsp.get_clients({ bufnr = bufnr }))
    :filter(function(c)
      return c.server_capabilities.completionProvider ~= nil
    end)
    :map(function(c)
      local client = Client.new(c)
      return {
        name = c.name,
        initialize = function(_, params)
          params.configure({
            completion_options = c.server_capabilities.completionProvider
          })
        end,
        resolve = function(_, completion_item)
          return Async.run(function()
            return client:completionItem_resolve(completion_item):await()
          end)
        end,
        ---@param command complete.kit.LSP.Command
        execute = function(_, command)
          return Async.run(function()
            return client:workspace_executeCommand({
              command = command.command,
              arguments = command.arguments
            }):await()
          end)
        end,
        complete = function()
          local position_params = vim.lsp.util.make_position_params()
          return Async.run(function()
            return client:textDocument_completion({
              textDocument = {
                uri = position_params.textDocument.uri,
              },
              position = {
                line = position_params.position.line,
                character = position_params.position.character,
              }
            }):await()
          end)
        end
      }
    end)
    :totable()

---Create complete.core.CompletionProvider from sources.
---@type complete.core.CompletionProvider[]
local providers = vim.iter(sources):map(function(source)
  return CompletionProvider.new(source)
end):totable()

-- Create CompletionService.
local service = CompletionService.new({
  sorter = DefaultSorter.sorter,
  matcher = DefaultMatcher.matcher,
  provider_groups = {
    vim.iter(providers):map(function(provider)
      return {
        provider = provider
      }
    end):totable()
  }
})

-- Create DefaultView and attach buffer.
local view = DefaultView.new(service)

view:attach(bufnr)

local ok, insx = pcall(require, 'insx')
if ok then
  insx.add('<C-n>', {
    enabled = function()
      return view:is_visible()
    end,
    action = function()
      local selection = view:get_selection()
      view:select(selection and selection.index + 1 or 1)
    end
  })
  insx.add('<C-p>', {
    enabled = function()
      return view:is_visible()
    end,
    action = function()
      local selection = view:get_selection()
      view:select(selection and selection.index - 1 or 1)
    end
  })
  insx.add('<CR>', {
    enabled = function()
      return view:get_selection() and view:get_selection().index > 0
    end,
    action = function()
      local selection = view:get_selection()
      if selection then
        local match = view:get_match_at(selection.index)
        if match then
          service:commit(match.item, {
            replace = false,
            expand_snippet = function(snippet)
              vim.fn['vsnip#anonymous'](snippet)
            end
          })
          return
        end
      end
      vim.fn.feedkeys(vim.api.nvim_replace_termcodes('<CR>', true, false, true), 'n')
    end
  })
else
  vim.keymap.set('i', '<C-n>', function()
    local selection = view:get_selection()
    view:select(selection and selection.index + 1 or 1)
  end)

  vim.keymap.set('i', '<C-p>', function()
    local selection = view:get_selection()
    view:select(selection and selection.index - 1 or -1)
  end)

  vim.keymap.set('i', '<CR>', function()
    local selection = view:get_selection()
    if selection then
      local match = view:get_match_at(selection.index)
      if match then
        service:commit(match.item, {
          replace = false,
          expand_snippet = function(snippet)
            vim.fn['vsnip#anonymous'](snippet)
          end
        })
        return
      end
    end
    vim.fn.feedkeys(vim.api.nvim_replace_termcodes('<CR>', true, false, true), 'n')
  end)
end
