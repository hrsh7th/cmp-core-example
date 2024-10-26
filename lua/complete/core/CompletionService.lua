local Async               = require('complete.kit.Async')
local TriggerContext      = require('complete.core.TriggerContext')
local DocumentSelector    = require('complete.kit.LSP.DocumentSelector')
local CompletionProvider  = require('complete.core.CompletionProvider')

---@class complete.core.CompletionService.OnUpdate.Payload
---@field public trigger_context complete.core.TriggerContext
---@field public preselect? integer
---@field public matches complete.core.Match[] }
---@alias complete.core.CompletionService.OnUpdate fun(payload: complete.core.CompletionService.OnUpdate.Payload): nil

---@class complete.core.CompletionService.ProviderConfiguration
---@field public provider complete.core.CompletionProvider
---@field public item_count? integer

---@class complete.core.CompletionService.Option
---@field public sorter complete.core.Sorter
---@field public matcher complete.core.Matcher
---@field public provider_groups complete.core.CompletionService.ProviderConfiguration[][]

---@class complete.core.CompletionService.State
---@field public trigger_context? complete.core.TriggerContext
---@field public matches? complete.core.Match[]

---@class complete.core.CompletionService
---@field private _option complete.core.CompletionService.Option
---@field private _events table<string, (fun(): any)[]>
---@field private _state complete.core.CompletionService.State
local CompletionService   = {}
CompletionService.__index = CompletionService

---Create a new CompletionService.
---@param option complete.core.CompletionService.Option
---@return complete.core.CompletionService
function CompletionService.new(option)
  return setmetatable({
    _option = option,
    _events = {},
    _state = {},
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
  self._state = {}
end

---Complete.
---@param trigger_context complete.core.TriggerContext
---@return complete.kit.Async.AsyncTask
function CompletionService:complete(trigger_context)
  local changed = not self._state.trigger_context or self._state.trigger_context:changed(trigger_context)

  self._state.trigger_context = trigger_context

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
      local has_preselect = false
      self._state.matches = {}
      for _, provider_configuration in ipairs(provider_configurations) do
        for _, match in ipairs(provider_configuration.provider:get_matches(trigger_context, self._option.matcher)) do
          self._state.matches[#self._state.matches + 1] = match
          if match.item:preselect() then
            has_preselect = true
          end
        end
      end

      -- group matches are found.
      if #self._state.matches ~= 0 then
        -- sort items.
        self._state.matches = self._option.sorter(self._state.matches)

        -- preselect index.
        local preselect = nil
        if has_preselect then
          for i, match in ipairs(self._state.matches) do
            if match.item:preselect() then
              preselect = i
              break
            end
          end
        end

        -- completion found.
        self._events.on_update = self._events.on_update or {}
        for _, c in ipairs(self._events.on_update --[=[@as complete.core.CompletionService.OnUpdate[]]=]) do
          c({
            trigger_context = trigger_context,
            preselect = preselect,
            matches = self._state.matches
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
      preselect = nil,
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
