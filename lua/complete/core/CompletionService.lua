local Async = require('complete.kit.Async')

---@class complete.core.CompletionService
---@field private _providers complete.core.CompletionProvider[]
local CompletionService = {}
CompletionService.__index = CompletionService

---Create a new CompletionService.
---@class complete.core.CompletionService.new.Params
---@field providers complete.core.CompletionProvider[]
---@param params complete.core.CompletionService.new.Params
function CompletionService.new(params)
  local self = setmetatable({}, CompletionService)
  self._providers = params.providers
  return self
end

---Complete.
---@param trigger_context complete.core.TriggerContext
function CompletionService:complete(trigger_context)
  return Async.run(function()
    -- trigger phase.
    for _, provider in ipairs(self._providers) do
      local completion_options = provider:get_completion_options()
      provider:complete(trigger_context):next(function(completion_context)
        if not completion_context then
          return -- don't invoke new completion.
        end
      end)
    end
  end)
end

return CompletionService
