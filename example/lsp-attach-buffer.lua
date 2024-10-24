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
  cmp.setup.buffer { completion = { autocomplete = false } }
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
        initialize = function(_, params)
          params.configure({
            completion_options = c.server_capabilities.completionProvider
          })
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
DefaultView.new(service):attach(bufnr)
