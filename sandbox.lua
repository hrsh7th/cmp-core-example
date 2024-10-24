local Async = require('complete.kit.Async')
local Client = require('complete.kit.LSP.Client')
local CompletionService = require('complete.core.CompletionService')
local CompletionProvider = require('complete.core.CompletionProvider')
local DefaultView = require('complete.ext.DefaultView')

local bufnr = vim.api.nvim_get_current_buf()

local ok, cmp = pcall(require, 'cmp')
if ok then
  cmp.setup.buffer { completion = { autocomplete = false } }
end

local providers = vim.iter(vim.lsp.get_clients({ bufnr = bufnr }))
    :filter(function(c)
      return c.server_capabilities.completionProvider
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
          return Async.run(function()
            return client:textDocument_completion(vim.lsp.util.make_position_params(0)):await()
          end)
        end
      }
    end)
    :totable()

local service = CompletionService.new({
  provider_groups = {
    vim.iter(providers):map(function(source)
      return {
        provider = CompletionProvider.new(source)
      }
    end):totable()
  }
})

local view = DefaultView.new(service)

view:attach(bufnr)
