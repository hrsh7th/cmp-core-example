local kit = require('complete.kit')
local LSP = require('complete.kit.LSP')
local Async = require('complete.kit.Async')
local Keymap = require('complete.kit.Vim.Keymap')
local Character = require('complete.core.Character')
local DefaultMatcher = require('complete.core.DefaultMatcher')
local DefaultSorter = require('complete.core.DefaultSorter')
local TriggerContext = require('complete.core.TriggerContext')
local CompletionProvider = require('complete.core.CompletionProvider')

local default_option = {
  performance = {
    fetching_timeout_ms = 500,
  },
  sorter = DefaultSorter.sorter,
  matcher = DefaultMatcher.matcher,
} --[[@as complete.core.CompletionService.Option]]

local stop_emitting = false

---Emit event.
---@generic T
---@param events (fun(payload: T): nil)[]
---@param payload T
---@return nil
local function emit(events, payload)
  if stop_emitting then
    return
  end
  for _, c in ipairs(events) do
    c(payload)
  end
end

---@class complete.core.CompletionService.OnUpdate.Payload
---@field public trigger_context complete.core.TriggerContext
---@field public matches complete.core.Match[] }
---@alias complete.core.CompletionService.OnUpdate fun(payload: complete.core.CompletionService.OnUpdate.Payload): nil

---@class complete.core.CompletionService.OnSelect.Payload
---@field public selection complete.core.CompletionService.Selection
---@field public matches complete.core.Match[] }
---@alias complete.core.CompletionService.OnSelect fun(payload: complete.core.CompletionService.OnSelect.Payload): nil

---@class complete.core.CompletionService.ProviderConfiguration
---@field public index integer
---@field public group integer
---@field public priority integer
---@field public item_count integer
---@field public provider complete.core.CompletionProvider

---@class complete.core.CompletionService.Option
---@field public performance { fetching_timeout_ms: number }
---@field public sorter complete.core.Sorter
---@field public matcher complete.core.Matcher

---@class complete.core.CompletionService.Selection
---@field public index integer
---@field public preselect boolean
---@field public text_before string

---@class complete.core.CompletionService.State
---@field public complete_trigger_context complete.core.TriggerContext
---@field public update_trigger_context complete.core.TriggerContext
---@field public selection complete.core.CompletionService.Selection
---@field public matches complete.core.Match[]

---@class complete.core.CompletionService
---@field private _preventing integer
---@field private _request_time integer
---@field private _state complete.core.CompletionService.State
---@field private _events table<string, (fun(): any)[]>
---@field private _option complete.core.CompletionService.Option
---@field private _keys table<string, string>
---@field private _macro_completion complete.kit.Async.AsyncTask[]
---@field private _provider_configurations complete.core.CompletionService.ProviderConfiguration[]
---@field private _debounced_update fun(): nil
local CompletionService = {}
CompletionService.__index = CompletionService

---Create a new CompletionService.
---@param option complete.core.CompletionService.Option|{}
---@return complete.core.CompletionService
function CompletionService.new(option)
  local self = setmetatable({
    _id = kit.unique_id(),
    _preventing = 0,
    _request_time = 0,
    _changedtick = 0,
    _option = kit.merge(option or {}, default_option),
    _events = {},
    _provider_configurations = {},
    _keys = {},
    _macro_completion = {},
    _state = {
      complete_trigger_context = TriggerContext.create_empty_context(),
      update_trigger_context = TriggerContext.create_empty_context(),
      selection = {
        index = 0,
        preselect = false,
        text_before = '',
      },
      matches = {},
    },
  }, CompletionService)

  self._keys.complete = ('<Plug>(c:%s:c)'):format(self._id)
  vim.keymap.set('i', self._keys.complete, function()
    if vim.fn.reg_executing() ~= '' then
      local trigger_context = TriggerContext.create()
      ---@diagnostic disable-next-line: invisible
      table.insert(self._macro_completion, self:complete(trigger_context))
    end
  end)

  return self
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

---Add handler.
---@param callback complete.core.CompletionService.OnSelect
---@return fun(): nil
function CompletionService:on_select(callback)
  self._events.on_select = self._events.on_select or {}
  table.insert(self._events.on_select, callback)
  return function()
    for i, c in ipairs(self._events.on_select) do
      if c == callback then
        table.remove(self._events.on_select, i)
        break
      end
    end
  end
end

---Register provider.
---@param provider complete.core.CompletionProvider
---@param config? { group?: integer, priority?: integer, item_count?: integer }
---@return fun(): nil
function CompletionService:register_provider(provider, config)
  table.insert(self._provider_configurations, {
    index = #self._provider_configurations + 1,
    group = config and config.group or 0,
    priority = config and config.priority or 0,
    item_count = config and config.item_count or math.huge,
    provider = provider,
  })
  return function()
    for i, c in ipairs(self._provider_configurations) do
      if c.provider == provider then
        table.remove(self._provider_configurations, i)
        break
      end
    end
  end
end

---Clear completion.
function CompletionService:clear()
  for _, provider_group in ipairs(self:_get_provider_groups()) do
    for _, provider_configuration in ipairs(provider_group) do
      provider_configuration.provider:clear()
    end
  end

  -- reset current TriggerContext for preventing new completion in same context.
  self._state = {
    complete_trigger_context = TriggerContext.create(),
    update_trigger_context = TriggerContext.create(),
    selection = {
      index = 0,
      preselect = false,
      text_before = '',
    },
    matches = {},
  }

  -- reset menu.
  emit(self._events.on_update or {}, {
    trigger_context = self._state.complete_trigger_context,
    matches = {},
  })
end

---Select completion.
---@param index integer
---@param preselect? boolean
function CompletionService:select(index, preselect)
  if vim.fn.reg_executing() ~= '' then
    local p = self._macro_completion
    self._macro_completion = {}
    Async.all(p):sync(2 * 1000)
    self:update()
  end

  index = index % (#self._state.matches + 1)

  local changed = false
  changed = changed or self._state.selection.index ~= index
  changed = changed or self._state.selection.preselect ~= (preselect or false)
  if not changed then
    return
  end

  -- store current leading text for de-selecting.
  local text_before = self._state.selection.text_before
  if not preselect and self._state.selection.index == 0 then
    text_before = TriggerContext.create().text_before
  end
  self._state.selection = {
    index = index,
    preselect = preselect or false,
    text_before = text_before,
  }

  emit(self._events.on_select or {}, {
    selection = self._state.selection,
    matches = self._state.matches,
  })
end

---Get selection.
---@return complete.core.CompletionService.Selection
function CompletionService:get_selection()
  if vim.fn.reg_executing() ~= '' then
    local p = self._macro_completion
    self._macro_completion = {}
    Async.all(p):sync(2 * 1000)
    self:update()
  end
  return kit.clone(self._state.selection)
end

---Get match at index.
---@param index integer
---@return complete.core.Match
function CompletionService:get_match_at(index)
  return self._state.matches[index]
end

---Complete.
---@param trigger_context complete.core.TriggerContext
---@return complete.kit.Async.AsyncTask
function CompletionService:complete(trigger_context)
  return Async.run(function()
    local changed = self._state.complete_trigger_context:changed(trigger_context)
    if not changed then
      return Async.resolve({})
    end
    self._state.complete_trigger_context = trigger_context

    -- reset selection for new completion.
    self._state.selection = {
      index = 0,
      preselect = true,
      text_before = trigger_context.text_before,
    }

    -- trigger.
    local new_completing_providers = {}
    local tasks = {} --[=[@type complete.kit.Async.AsyncTask[]]=]
    for _, provider_group in ipairs(self:_get_provider_groups()) do
      for _, provider_configuration in ipairs(provider_group) do
        if provider_configuration.provider:capable(trigger_context) then
          local prev_request_state = provider_configuration.provider:get_request_state()
          table.insert(
            tasks,
            provider_configuration.provider:complete(trigger_context):next(function(completion_context)
              -- update menu window if some of the conditions.
              -- 1. new completion was invoked.
              -- 2. change provider's `Completed` state. (true -> false or false -> true)
              local next_request_state = provider_configuration.provider:get_request_state()
              if completion_context or (prev_request_state == CompletionProvider.RequestState.Completed) ~= (next_request_state == CompletionProvider.RequestState.Completed) then
                self._state.update_trigger_context = TriggerContext.create_empty_context()
                self:update()
              end
            end)
          )

          -- gather new completion request was invoked providers.
          local next_request_state = provider_configuration.provider:get_request_state()
          if prev_request_state ~= CompletionProvider.RequestState.Fetching and next_request_state == CompletionProvider.RequestState.Fetching then
            table.insert(new_completing_providers, provider_configuration.provider)
          end
        end
      end
    end

    if #new_completing_providers == 0 then
      -- on-demand filter (if does not invoked new completion).
      if vim.fn.reg_executing() == '' then
        self:update()
      end
    else
      self._request_time = vim.uv.hrtime() / 1000000

      -- set new-completion position for macro.
      if vim.fn.reg_executing() == '' then
        vim.api.nvim_feedkeys(Keymap.termcodes(self._keys.complete), 'nit', true)
      end
    end

    return Async.all(tasks)
  end)
end

---Update completion.
---@param option? { force?: boolean }
function CompletionService:update(option)
  option = option or {}
  option.force = option.force or false

  local trigger_context = TriggerContext.create()

  -- check prev update_trigger_context.
  local changed = self._state.update_trigger_context:changed(trigger_context)
  if not changed and not option.force then
    return Async.resolve({})
  end
  self._state.update_trigger_context = trigger_context

  -- check user is selecting manually.
  if self:_is_active_selection() then
    return
  end

  -- basically, 1st group's higiher priority provider is preferred (for reducing flickering).
  -- but when it's response is too slow, we ignore it.
  local elapsed_ms = vim.uv.hrtime() / 1000000 - self._request_time
  local fetching_timeout_ms = self._option.performance.fetching_timeout_ms
  local fetching_timeout_remaining_ms = math.max(0, fetching_timeout_ms - elapsed_ms)

  self._state.matches = {}

  local has_fetching_provider = false
  local has_provider_triggered_by_character = false
  for _, provider_group in ipairs(self:_get_provider_groups()) do
    local provider_configurations = {} --[=[@type complete.core.CompletionService.ProviderConfiguration[]]=]
    for _, provider_configuration in ipairs(provider_group) do
      if provider_configuration.provider:capable(trigger_context) then
        -- check the provider was triggered by triggerCharacters.
        local completion_context = provider_configuration.provider:get_completion_context()
        if completion_context and completion_context.triggerKind == LSP.CompletionTriggerKind.TriggerCharacter then
          has_provider_triggered_by_character = has_provider_triggered_by_character or
              #provider_configuration.provider:get_items() > 0
        end

        -- if higher priority provider is fetching, skip the lower priority providers in same group. (reduce flickering).
        -- NOTE: the providers are ordered by priority.
        if provider_configuration.provider:get_request_state() == CompletionProvider.RequestState.Fetching then
          has_fetching_provider = true
          if fetching_timeout_remaining_ms > 0 then
            break
          end
        elseif provider_configuration.provider:get_request_state() == CompletionProvider.RequestState.Completed then
          table.insert(provider_configurations, provider_configuration)
        end
      end
    end

    -- if trigger character is found, remove non-trigger character providers (for UX).
    if has_provider_triggered_by_character then
      for j = #provider_configurations, 1, -1 do
        local completion_context = provider_configurations[j].provider:get_completion_context()
        if not (completion_context and completion_context.triggerKind == LSP.CompletionTriggerKind.TriggerCharacter) then
          table.remove(provider_configurations, j)
        end
      end
    end

    -- group providers are capable.
    if #provider_configurations ~= 0 then
      local has_preselect = false
      self._state.matches = {}
      for _, provider_configuration in ipairs(provider_configurations) do
        local score_boost = self:_get_score_boost(provider_configuration.provider)
        for _, match in ipairs(provider_configuration.provider:get_matches(trigger_context, self._option.matcher)) do
          match.score = match.score + score_boost
          self._state.matches[#self._state.matches + 1] = match
          if match.item:is_preselect() then
            has_preselect = true
          end
        end
      end

      -- group matches are found.
      if #self._state.matches > 0 then
        -- sort items.
        self._state.matches = self._option.sorter(self._state.matches)

        -- preselect index.
        local preselect = nil
        if has_preselect then
          for j, match in ipairs(self._state.matches) do
            if match.item:is_preselect() then
              preselect = j
              break
            end
          end
        end

        -- completion found.
        emit(self._events.on_update or {}, {
          trigger_context = trigger_context,
          matches = self._state.matches,
        })

        -- emit selection.
        if has_preselect then
          self:select(preselect or 0, true)
        end
        return
      end
    end

    -- do not fallback to the next group if current group has fetching providers.
    if has_fetching_provider then
      if fetching_timeout_remaining_ms > 0 then
        vim.defer_fn(function()
          -- if trigger_context is not changed, update menu forcely.
          if self._state.update_trigger_context == trigger_context then
            self:update({ force = true })
          end
        end, fetching_timeout_remaining_ms + 1)
      end
      return
    end
  end

  -- no completion found.
  if not has_fetching_provider or option.force then
    emit(self._events.on_update or {}, {
      trigger_context = trigger_context,
      preselect = nil,
      matches = {},
    })
  end
end

---Commit completion.
---@param item complete.core.CompletionItem
---@param option? { replace?: boolean, expand_snippet?: complete.core.ExpandSnippet }
function CompletionService:commit(item, option)
  local resume = self:prevent()
  return item
      :commit({
        replace = option and option.replace,
        expand_snippet = option and option.expand_snippet,
      })
      :next(resume)
      :next(function()
        self:clear()

        -- re-trigger completion for trigger characters.
        --For this to run, we need to ignore contexts marked by `self:clear()`, so `force=true` is required.
        local trigger_context = TriggerContext.create({ force = true })
        if trigger_context.before_character and Character.is_symbol(trigger_context.before_character:byte(1)) then
          for _, provider_group in ipairs(self:_get_provider_groups()) do
            local provider_configurations = {} --[=[@type complete.core.CompletionService.ProviderConfiguration[]]=]
            for _, provider_configuration in ipairs(provider_group) do
              if provider_configuration.provider:capable(trigger_context) then
                table.insert(provider_configurations, provider_configuration)
              end
            end
            for _, provider_configuration in ipairs(provider_configurations) do
              local completion_options = provider_configuration.provider:get_completion_options()
              if vim.tbl_contains(completion_options.triggerCharacters or {}, trigger_context.before_character) then
                return self:complete(trigger_context)
              end
            end
          end
        end
      end)
end

---Prevent completion.
---@return fun(): complete.kit.Async.AsyncTask
function CompletionService:prevent()
  self._preventing = self._preventing + 1
  return function()
    self._preventing = self._preventing - 1
    self._state.complete_trigger_context = TriggerContext.create()
    self._state.update_trigger_context = TriggerContext.create()
    return Async.resolve()
  end
end

---Is active selection.
---@return boolean
function CompletionService:_is_active_selection()
  local selection = self._state.selection
  return not selection.preselect and selection.index > 0
end

---Get provider groups.
---@return complete.core.CompletionService.ProviderConfiguration[][]
function CompletionService:_get_provider_groups()
  -- sort by group.
  table.sort(self._provider_configurations, function(a, b)
    if a.group ~= b.group then
      return a.group < b.group
    end
    if a.priority ~= b.priority then
      return a.priority > b.priority
    end
    return a.index < b.index
  end)

  -- group by group.
  local groups = {}
  for _, provider_configuration in ipairs(self._provider_configurations) do
    if not groups[provider_configuration.group] then
      groups[provider_configuration.group] = {}
    end
    table.insert(groups[provider_configuration.group], provider_configuration)
  end

  -- create group_index.
  local group_indexes = vim.tbl_keys(groups)
  table.sort(group_indexes)

  -- sort by group.
  local sorted_groups = {}
  for _, group_index in ipairs(group_indexes) do
    table.insert(sorted_groups, groups[group_index])
  end
  return sorted_groups
end

---Get score boost.
---@param provider complete.core.CompletionProvider
---@return number
function CompletionService:_get_score_boost(provider)
  local cur_priority = 0
  local max_priority = 0
  for _, provider_configuration in ipairs(self._provider_configurations) do
    max_priority = math.max(max_priority, provider_configuration.priority)
    if provider == provider_configuration.provider then
      cur_priority = provider_configuration.priority
    end
  end
  return 5 * (cur_priority / max_priority)
end

return CompletionService
