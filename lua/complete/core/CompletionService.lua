---@class complete.core.CompletionService
---@field private _providers complete.core.CompletionProvider[]
local CompletionService = {}
CompletionService.__index = CompletionService

---Create a new CompletionService.
function CompletionService.new()
  local self = setmetatable({}, CompletionService)
  self._providers = {}
  return self
end

---Add provider.
---@param provider complete.core.CompletionProvider
function CompletionService:add_provider(provider)
  table.insert(self._providers, provider)
end

---Remove provider.
---@param provider complete.core.CompletionProvider
function CompletionService:remove_provider(provider)
  for i, p in ipairs(self._providers) do
    if p == provider then
      table.remove(self._providers, i)
      return
    end
  end
  error('provider not found.')
end

---Complete.
---@param trigger_context complete.core.TriggerContext
function CompletionService:complete(trigger_context)
  -- trigger phase.
  for _, provider in ipairs(self._providers) do
    local completion_options = provider:get_completion_options()
    provider:complete(trigger_context):next(function(completion_context)
      if not completion_context then
        return -- don't invoke new completion.
      end
    end)
  end
end

function CompletionService:_display()
end

return CompletionService
