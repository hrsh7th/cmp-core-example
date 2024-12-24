local Async = require('complete.kit.Async')
local CompletionProvider = require('complete.core.CompletionProvider')
local context = require('complete.ext.cmp_compat.context')

---Create a new Cmp object from a source object.
---@param cmp_source cmp.Source
local function create_provider_by_cmp(cmp_source)
  return CompletionProvider.new({
    name = ('cmp:%s'):format(cmp_source.name),
    initialize = function(_, params)
      pcall(function()
        params.configure({
          position_encoding_kind = cmp_source:get_position_encoding_kind(),
          completion_options = {
            completionItem = {
              labelDetailsSupport = true,
            },
            triggerCharacters = cmp_source:get_trigger_characters(),
            resolveProvider = true,
          },
          keyword_pattern = cmp_source:get_keyword_pattern(),
        })
      end)
    end,
    complete = function(_)
      return Async.new(function(resolve)
        vim.schedule(function()
          cmp_source:complete(context.new(), function()
            resolve(cmp_source.response)
          end)
        end)
      end)
    end,
    resolve = function(_, item)
      return Async.new(function(resolve)
        cmp_source:resolve(item --[[@as any]], resolve)
      end)
    end,
    execute = function(_, command)
      return Async.new(function(resolve)
        cmp_source:execute({ command = command } --[[@as any]], resolve)
      end)
    end
  })
end

return {
  create_provider_by_cmp = create_provider_by_cmp
}
