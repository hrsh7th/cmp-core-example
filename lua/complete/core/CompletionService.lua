local Async               = require('complete.kit.Async')
local TriggerContext      = require('complete.core.TriggerContext')
local DocumentSelector    = require('complete.kit.LSP.DocumentSelector')
local CompletionProvider  = require('complete.core.CompletionProvider')

---@alias complete.core.CompletionService.OnUpdate fun(payload: complete.core.CompletionService.OnUpdate.Payload): nil
---@alias complete.core.CompletionService.OnUpdate.Payload { trigger_context: complete.core.TriggerContext, matches: complete.core.Match[] }

---@class complete.core.CompletionService.ProviderConfiguration
---@field provider complete.core.CompletionProvider
---@field item_count? integer

---@class complete.core.CompletionService.Option
---@field sorter complete.core.Sorter
---@field matcher complete.core.Matcher
---@field provider_groups complete.core.CompletionService.ProviderConfiguration[][]

---@class complete.core.CompletionService.State
---@field trigger_context complete.core.TriggerContext

---@class complete.core.CompletionService
---@field private _option complete.core.CompletionService.Option
---@field private _events table<string, (fun(): any)[]>
---@field private _state? complete.core.CompletionService.State
local CompletionService   = {}
CompletionService.__index = CompletionService

---Create a new CompletionService.
---@param option complete.core.CompletionService.Option
---@return complete.core.CompletionService
function CompletionService.new(option)
  return setmetatable({
    _option = option,
    _events = {},
    _state = nil,
  }, CompletionService)
end

---Add handler.
---@param callback complete.core.CompletionService.OnUpdate
---@return fun(): nil
function CompletionService:on_update(callback)
  self._events.on_update = self._events.on_update or {}
  table.insert(self._events.on_update, callback)
  return function()
    for i, c in ipairs(self._events.on_update) do
      if c == callback then
        table.remove(self._events.on_update, i)
        break
      end
    end
  end
end

---Return completion is in progress or not.
---@return boolean
function CompletionService:is_completing()
  for _, provider_group in ipairs(self._option.provider_groups) do
    for _, provider_configuration in ipairs(provider_group) do
      if provider_configuration.provider:get_ready_state() == CompletionProvider.ReadyState.Fetching then
        return true
      end
    end
  end
  return false
end

---Clear completion.
function CompletionService:clear()
  for _, provider_group in ipairs(self._option.provider_groups) do
    for _, provider_configuration in ipairs(provider_group) do
      provider_configuration.provider:clear()
    end
  end
  self._state = nil
end

---Complete.
---@param trigger_context complete.core.TriggerContext
---@return complete.kit.Async.AsyncTask
function CompletionService:complete(trigger_context)
  local changed = not self._state or self._state.trigger_context:changed(trigger_context)

  self._state = { trigger_context = trigger_context }

  -- ignore completion.
  if not changed then
    return Async.resolve({})
  end

  -- trigger phase.
  local tasks = {} --[=[@type complete.kit.Async.AsyncTask[]]=]
  for _, group in ipairs(self._option.provider_groups) do
    for _, provider_configuration in ipairs(group) do
      if self:_is_capable(trigger_context, provider_configuration.provider) then
        table.insert(tasks, (
          provider_configuration.provider:complete(trigger_context):next(function()
            self:update(TriggerContext.create())
          end)
        ))
      end
    end
  end

  -- filter phase.
  self:update(trigger_context)

  -- return current completions.
  return Async.all(tasks)
end

---Update completion.
---@param trigger_context complete.core.TriggerContext
function CompletionService:update(trigger_context)
  for _, group in ipairs(self._option.provider_groups) do
    -- get capable providers from current group.
    local provider_configurations = {} --[=[@type complete.core.CompletionService.ProviderConfiguration[]]=]
    for _, provider_configuration in ipairs(group) do
      if self:_is_capable(trigger_context, provider_configuration.provider) and provider_configuration.provider:get_ready_state() ~= CompletionProvider.ReadyState.Waiiting then
        table.insert(provider_configurations, provider_configuration)
      end
    end

    -- group providers are capable.
    if #provider_configurations ~= 0 then
      local matches = {} --[=[@type complete.core.Match[]]=]
      for _, provider_configuration in ipairs(provider_configurations) do
        for _, match in ipairs(provider_configuration.provider:get_matches(trigger_context, self._option.matcher)) do
          matches[#matches + 1] = match
        end
      end

      -- group matches are found.
      if #matches ~= 0 then
        -- sort items.
        matches = self._option.sorter(matches)

        -- completion found.
        self._events.on_update = self._events.on_update or {}
        for _, c in ipairs(self._events.on_update --[=[@as complete.core.CompletionService.OnUpdate[]]=]) do
          c({
            trigger_context = trigger_context,
            matches = matches
          })
        end
        return
      end
    end
  end

  -- no completion found.
  self._events.on_update = self._events.on_update or {}
  for _, c in ipairs(self._events.on_update --[=[@as complete.core.CompletionService.OnUpdate[]]=]) do
    c({
      trigger_context = trigger_context,
      matches = {}
    })
  end
end

---Return specified provider is capable or not.
---@param trigger_context complete.core.TriggerContext
---@param provider complete.core.CompletionProvider
---@return boolean
function CompletionService:_is_capable(trigger_context, provider)
  local completion_options = provider:get_completion_options()
  return not completion_options.documentSelector or
  DocumentSelector.score(trigger_context.bufnr, completion_options.documentSelector) ~= 0
end

return CompletionService
