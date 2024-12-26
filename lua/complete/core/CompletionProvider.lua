---@diagnostic disable: invisible
local LSP = require('complete.kit.LSP')
local Async = require('complete.kit.Async')
local RegExp = require('complete.kit.Vim.RegExp')
local CompletionItem = require('complete.core.CompletionItem')
local DocumentSelector = require('complete.kit.LSP.DocumentSelector')

---@enum complete.core.CompletionProvider.RequestState
local RequestState = {
  Waiting = 'Waiting',
  Fetching = 'Fetching',
  Completed = 'Completed',
}

---Convert completion response to LSP.CompletionList.
---@param response (complete.kit.LSP.CompletionList|complete.kit.LSP.CompletionItem[])?
---@return complete.kit.LSP.CompletionList
local function to_completion_list(response)
  response = response or {}
  if response.items then
    response.isIncomplete = response.isIncomplete or false
    response.items = response.items or {}
    return response
  end
  return {
    isIncomplete = false,
    items = response or {},
  }
end

---Extract keyword pattern range for requested line context.
---@param trigger_context complete.core.TriggerContext
---@param keyword_pattern string
---@return { [1]: integer, [2]: integer } 1-origin utf8 byte index
local function extract_keyword_range(trigger_context, keyword_pattern)
  local cache_key = string.format('%s:%s', 'CompletionProvider:extract_keyword_range', keyword_pattern)
  if not trigger_context.cache[cache_key] then
    local c = trigger_context.character + 1
    local _, s, e = RegExp.extract_at(trigger_context.text, keyword_pattern, c)
    trigger_context.cache[cache_key] = { s or c, e or c }
  end
  return trigger_context.cache[cache_key]
end

---@class complete.core.CompletionProvider.State
---@field public request_state? complete.core.CompletionProvider.RequestState
---@field public request_time? integer
---@field public completion_context? complete.kit.LSP.CompletionContext
---@field public completion_offset? integer
---@field public trigger_context? complete.core.TriggerContext
---@field public is_incomplete? boolean
---@field public items? complete.core.CompletionItem[]
---@field public matches? complete.core.Match[]
---@field public matches_items? complete.core.CompletionItem[]
---@field public matches_before_text? string

---@class complete.core.CompletionProvider
---@field private _source complete.core.CompletionSource
---@field private _config complete.core.CompletionSource.Configuration
---@field private _state complete.core.CompletionProvider.State
local CompletionProvider = {}
CompletionProvider.__index = CompletionProvider
CompletionProvider.RequestState = RequestState

---Create new CompletionProvider.
---@param source complete.core.CompletionSource
---@return complete.core.CompletionProvider
function CompletionProvider.new(source)
  local self = setmetatable({
    _source = source,
    _config = {
      keyword_pattern = [[\%(-\?\d\+\%(\.\d\+\)\?\|\h\w*\%(-\w*\)*\)]],
      position_encoding_kind = LSP.PositionEncodingKind.UTF16,
      completion_options = {},
    },
    _state = { ready_state = RequestState.Waiting },
  }, CompletionProvider)

  -- initialize source.
  if source.initialize then
    source:initialize({
      configure = function(configuration)
        if configuration.keyword_pattern ~= nil then
          self._config.keyword_pattern = configuration.keyword_pattern
        end
        if configuration.position_encoding_kind ~= nil then
          self._config.position_encoding_kind = configuration.position_encoding_kind
        end
        if configuration.completion_options ~= nil then
          self._config.completion_options = configuration.completion_options
        end
      end,
    })
  end

  return self
end

---Get provider name.
---@return string
function CompletionProvider:get_name()
  return self._source.name
end

---Completion (textDocument/completion).
---@param trigger_context complete.core.TriggerContext
---@return complete.kit.Async.AsyncTask complete.kit.LSP.CompletionContext?
function CompletionProvider:complete(trigger_context)
  return Async.run(function()
    local completion_options = self:get_completion_options()
    local trigger_characters = completion_options.triggerCharacters or {}
    local keyword_pattern = self:get_keyword_pattern()
    local keyword_offset = trigger_context:get_keyword_offset(keyword_pattern)

    ---Check should complete for new trigger context or not.
    local completion_context ---@type complete.kit.LSP.CompletionContext
    local completion_offset ---@type integer?
    if vim.tbl_contains(trigger_characters, trigger_context.before_character) then
      -- trigger character based completion.
      -- TODO: VSCode does not show completion for `const a = |` case on the @vtsls/language-server even if language-server tells `<Space>` as trigger_character.
      completion_context = {
        triggerKind = LSP.CompletionTriggerKind.TriggerCharacter,
        triggerCharacter = trigger_context.before_character,
      }
      completion_offset = trigger_context.character + 1
    elseif trigger_context.force then
      -- manual based completion
      completion_context = {
        triggerKind = LSP.CompletionTriggerKind.Invoked,
      }
      completion_offset = trigger_context.character + 1
    else
      -- keyword based completion.
      if keyword_offset and keyword_offset < trigger_context.character + 1 then
        local prev_keyword_offset = self._state.completion_offset
        local is_incomplete = self._state and self._state.is_incomplete

        if is_incomplete and keyword_offset == prev_keyword_offset then
          -- invoke completion if previous response specifies the `isIncomplete=true` and offset is not changed.
          completion_context = {
            triggerKind = LSP.CompletionTriggerKind.TriggerForIncompleteCompletions,
          }
          completion_offset = keyword_offset
        elseif keyword_offset and keyword_offset ~= prev_keyword_offset then
          -- invoke completion if keyword_offset is changed.
          completion_context = {
            triggerKind = LSP.CompletionTriggerKind.Invoked,
          }
          completion_offset = keyword_offset
        end
      end
    end

    -- do not invoke new completion.
    if not completion_context then
      if not keyword_offset then
        self:clear()
      end
      return
    end

    self._state.request_state = RequestState.Fetching
    self._state.trigger_context = trigger_context
    self._state.completion_context = completion_context
    self._state.completion_offset = completion_offset

    -- invoke completion.
    local raw_response = self._source:complete(completion_context):await()
    local response = to_completion_list(raw_response)

    -- ignore obsolete response.
    if self._state.trigger_context ~= trigger_context then
      return
    end

    -- adopt response.
    self:_adopt_response(trigger_context, response)

    if #self._state.items == 0 then
      self:clear()
    end

    return completion_context
  end)
end

---Accept completion response.
---@param list complete.kit.LSP.CompletionList
function CompletionProvider:_adopt_response(trigger_context, list)
  self._state.request_state = RequestState.Completed
  self._state.is_incomplete = list.isIncomplete or false
  self._state.items = {}
  for _, item in ipairs(list.items) do
    self._state.items[#self._state.items + 1] = CompletionItem.new(trigger_context, self, list, item)
  end
  self._state.matches = {}
  self._state.matches_items = {}
  self._state.matches_before_text = nil
end

---Resolve completion item (completionItem/resolve).
---@param item complete.kit.LSP.CompletionItem
---@return complete.kit.Async.AsyncTask
function CompletionProvider:resolve(item)
  if not self._source.resolve then
    return Async.resolve(item)
  end
  return self._source:resolve(item)
end

---Execute command (workspace/executeCommand).
---@param command complete.kit.LSP.Command
---@return complete.kit.Async.AsyncTask
function CompletionProvider:execute(command)
  if not self._source.execute then
    return Async.resolve()
  end
  return self._source:execute(command)
end

---Check if the provider is capable for the trigger context.
---@param trigger_context complete.core.TriggerContext
---@return boolean
function CompletionProvider:capable(trigger_context)
  local completion_options = self:get_completion_options()
  return not completion_options.documentSelector or
      DocumentSelector.score(trigger_context.bufnr, completion_options.documentSelector) ~= 0
end

---Return LSP.PositionEncodingKind.
---@return complete.kit.LSP.PositionEncodingKind
function CompletionProvider:get_position_encoding_kind()
  return self._config.position_encoding_kind
end

---Return LSP.CompletionOptions
---TODO: should consider how to listen to the source's option changes.
---@return complete.kit.LSP.CompletionRegistrationOptions
function CompletionProvider:get_completion_options()
  return self._config.completion_options
end

---TODO: We should decide how to get the default keyword pattern here.
---@return string
function CompletionProvider:get_keyword_pattern()
  return self._config.keyword_pattern
end

---Return keyword offest position.
---@return integer 1-origin utf8 byte index
function CompletionProvider:get_keyword_offset()
  if not self._state.trigger_context then
    error('The CompletionProvider: can only be called after completion has been called.')
  end

  return extract_keyword_range(self._state.trigger_context, self:get_keyword_pattern())[1]
end

---Return ready state.
---@return complete.core.CompletionProvider.RequestState
function CompletionProvider:get_request_state()
  return self._state.request_state
end

---Return current completion context.
---@return complete.kit.LSP.CompletionContext?
function CompletionProvider:get_completion_context()
  return self._state.completion_context
end

---Clear completion state.
function CompletionProvider:clear()
  self._state = { ready_state = RequestState.Waiting }
end

---Return items.
---@return complete.core.CompletionItem[]
function CompletionProvider:get_items()
  return self._state.items or {}
end

---Return matches.
---@param trigger_context complete.core.TriggerContext
---@param matcher complete.core.Matcher
---@return complete.core.Match[]
function CompletionProvider:get_matches(trigger_context, matcher)
  local is_acceptable = not not self._state.trigger_context
  is_acceptable = is_acceptable and self._state.trigger_context.bufnr == trigger_context.bufnr
  is_acceptable = is_acceptable and self._state.trigger_context.line == trigger_context.line
  if not is_acceptable then
    return {}
  end

  local next_before_text = trigger_context.text_before
  local prev_before_text = self._state.matches_before_text
  self._state.matches_before_text = next_before_text

  -- completely same situation.
  if prev_before_text and prev_before_text == next_before_text then
    return self._state.matches
  end

  -- filter target items (all items by default).
  local target_items = self._state.items or {}
  if prev_before_text and prev_before_text == next_before_text:sub(1, #prev_before_text) then
    -- re-use already filtered items for new filter text.
    target_items = self._state.matches_items or {}
  end

  self._state.matches = {}
  self._state.matches_items = {}
  for i, item in ipairs(target_items) do
    local query_text = trigger_context:get_query(item:get_offset())
    local filter_text = item:get_filter_text()
    local score, match_positions = matcher(query_text, filter_text)
    if score > 0 then
      local label_text = item:get_label_text()
      self._state.matches_items[#self._state.matches_items + 1] = item
      self._state.matches[#self._state.matches + 1] = {
        provider = self,
        item = item,
        score = score,
        index = i,
        match_positions = label_text ~= filter_text and select(2, matcher(query_text, label_text)) or match_positions,
      }
    end
  end
  return self._state.matches
end

---Create default insert range from keyword pattern.
---NOTE: This method returns the range that always specifies to 0-line.
---@return complete.kit.LSP.Range utf8 byte index
function CompletionProvider:get_default_insert_range()
  if not self._state.trigger_context then
    error('The CompletionProvider: can only be called after completion has been called.')
  end

  local keyword_pattern = self:get_keyword_pattern()
  local cache_key = string.format('%s:%s', 'CompletionProvider:get_default_insert_range', keyword_pattern)
  if not self._state.trigger_context.cache[cache_key] then
    local r = extract_keyword_range(self._state.trigger_context, keyword_pattern)
    self._state.trigger_context.cache[cache_key] = {
      start = {
        line = 0,
        character = r[1] - 1,
      },
      ['end'] = {
        line = 0,
        character = self._state.trigger_context.character,
      },
    }
  end
  return self._state.trigger_context.cache[cache_key]
end

---Create default replace range from keyword pattern.
---NOTE: This method returns the range that always specifies to 0-line.
---@return complete.kit.LSP.Range utf8 byte index
function CompletionProvider:get_default_replace_range()
  if not self._state.trigger_context then
    error('The CompletionProvider: can only be called after completion has been called.')
  end

  local keyword_pattern = self:get_keyword_pattern()
  local cache_key = string.format('%s:%s', 'CompletionProvider:get_default_replace_range', keyword_pattern)
  if not self._state.trigger_context.cache[cache_key] then
    local r = extract_keyword_range(self._state.trigger_context, keyword_pattern)
    self._state.trigger_context.cache[cache_key] = {
      start = {
        line = 0,
        character = r[1] - 1,
      },
      ['end'] = {
        line = 0,
        character = r[2] - 1,
      },
    }
  end
  return self._state.trigger_context.cache[cache_key]
end

return CompletionProvider
