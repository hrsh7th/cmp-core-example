local Async = require('complete.kit.Async')
local cmp_compat = require('complete.ext.cmp_compat.source')
local Client = require('complete.kit.LSP.Client')
local CompletionService = require('complete.core.CompletionService')
local CompletionProvider = require('complete.core.CompletionProvider')
local DefaultView = require('complete.ext.DefaultView')

return {
  setup = function()
    ---@type table<integer, { service: complete.core.CompletionService, view: complete.ext.DefaultView }>
    local buf_state = {}

    ---@return { service: complete.core.CompletionService, view: complete.ext.DefaultView }
    local function get(specified_buf)
      local buf = (specified_buf == nil or specified_buf == 0) and vim.api.nvim_get_current_buf() or specified_buf
      if not buf_state[buf] then
        local service = CompletionService.new({})
        local view = DefaultView.new(service, {
          border = 'rounded'
          -- border = nil
        })
        view:attach(buf)
        buf_state[buf] = { service = service, view = view }

        -- register cmp sources.
        local ok_cmp, cmp = pcall(require, 'cmp')
        if ok_cmp then
          for _, source in ipairs(cmp.get_registered_sources()) do
            if source.name ~= 'nvim_lsp' and source.name ~= 'cmdline' then
              service:register_provider(cmp_compat.create_provider_by_cmp(source), {
                group = 10
              })
            end
          end
        end

        -- register test source.
        service:register_provider(CompletionProvider.new({
          name = 'test',
          complete = function(_)
            return Async.run(function()
              return {
                items = {
                  {
                    label = '\\date',
                    insertText = os.date('%Y-%m-%d'),
                  }
                }
              }
            end)
          end
        }))
      end
      return buf_state[buf]
    end

    vim.api.nvim_create_autocmd('InsertEnter', {
      callback = function()
        get(0)
      end
    })

    vim.api.nvim_create_autocmd('LspAttach', {
      callback = function(e)
        local c = vim.lsp.get_clients({
          bufnr = e.buf,
          id = e.data.client_id
        })[1]
        if not c or not c.server_capabilities.completionProvider then
          return
        end

        local client = Client.new(c)
        local last_request = nil
        get(e.buf).service:register_provider(CompletionProvider.new({
          name = c.name,
          initialize = function(_, params)
            params.configure({
              position_encoding_kind = c.offset_encoding,
              completion_options = c.server_capabilities
                  .completionProvider --[[@as complete.kit.LSP.CompletionRegistrationOptions]]
            })
          end,
          resolve = function(_, completion_item)
            return Async.run(function()
              if c.server_capabilities.completionProvider.resolveProvider then
                return client:completionItem_resolve(completion_item):await()
              end
              return completion_item
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
          complete = function(_, completion_context)
            if last_request then
              last_request.cancel()
            end
            local position_params = vim.lsp.util.make_position_params(0, c.offset_encoding)
            return Async.run(function()
              last_request = client:textDocument_completion({
                textDocument = {
                  uri = position_params.textDocument.uri,
                },
                position = {
                  line = position_params.position.line,
                  character = position_params.position.character,
                },
                context = completion_context
              })
              local response = last_request:catch(function()
                return nil
              end):await()
              last_request = nil
              return response
            end)
          end
        }), {
          priority = 100
        })
      end
    })

    do
      local select = function(option)
        option = option or {}
        option.delta = option.delta or 1
        option.preselect = option.preselect or false
        return {
          enabled = function()
            return get().service:get_match_at(1)
          end,
          action = function()
            local selection = get().service:get_selection()
            get().service:select(selection and selection.index + option.delta, option.preselect)
          end
        }
      end
      local commit = function(option)
        option = option or {}
        option.replace = option.replace or false
        option.select_first = option.select_first or false
        return {
          enabled = function()
            return get().service and (get().service:get_selection().index > 0 or option.select_first)
          end,
          action = function(ctx)
            local selection = get().service:get_selection()
            if selection then
              local match = get().service:get_match_at(selection.index)
              if not match and option.select_first then
                match = get().service:get_match_at(1)
              end
              if match then
                get().service:commit(match.item, {
                  replace = option.replace,
                  expand_snippet = function(snippet)
                    vim.fn['vsnip#anonymous'](snippet)
                  end
                })
                return
              end
            end
            ctx.next()
          end
        }
      end

      local ok, insx = pcall(require, 'insx')
      if ok then
        insx.add('<C-n>', select({ delta = 1, preselect = false }))
        insx.add('<C-p>', select({ delta = -1, preselect = false }))
        insx.add('<Down>', select({ delta = 1, preselect = true }))
        insx.add('<Up>', select({ delta = -1, preselect = true }))
        insx.add('<CR>', commit({ select_first = true, replace = false }))
        insx.add('<C-y>', commit({ select_first = true, replace = true }))
        insx.add('<C-n>', {
          enabled = function()
            return not get().service:get_match_at(1)
          end,
          action = function()
            get().service:complete(require('complete.core.TriggerContext').create({ force = true }))
          end
        })
        insx.add('<C-Space>', function()
          get().service:complete(require('complete.core.TriggerContext').create({ force = true }))
        end)
      end
    end
  end
}
