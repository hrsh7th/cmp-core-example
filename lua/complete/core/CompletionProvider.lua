---@diagnostic disable: invisible
local kit = require('complete.kit')
local LSP = require('complete.kit.LSP')
local Async = require('complete.kit.Async')
local RegExp = require('complete.kit.Vim.RegExp')
local CompletionItem = require('complete.core.CompletionItem')
local DocumentSelector = require('complete.kit.LSP.DocumentSelector')

---@enum complete.core.CompletionProvider.ReadyState
local ReadyState = {
  Waiiting = 'Waiting',
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
    return response
  end
  return {
    isIncomplete = false,
    items = response,
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
---@field public ready_state? complete.core.CompletionProvider.ReadyState
---@field public completion_context? complete.kit.LSP.CompletionContext
---@field public completion_offset? integer
---@field public trigger_context? complete.core.TriggerContext
---@field public is_incomplete? boolean
---@field public items? complete.core.CompletionItem[]
---@field public matches? complete.core.Match[]
---@field public matches_items? complete.core.CompletionItem[]
---@field public matches_before_text? string
---@field public matches_cursor_offset? integer
---@field public matches_keyword_offset? integer

---@class complete.core.CompletionProvider
---@field private _source complete.core.CompletionSource
---@field private _config complete.core.CompletionSource.Configuration
---@field private _state complete.core.CompletionProvider.State
local CompletionProvider = {}
CompletionProvider.__index = CompletionProvider
CompletionProvider.ReadyState = ReadyState

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
    _state = { ready_state = ReadyState.Waiiting },
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

---Completion (textDocument/completion).
---@param trigger_context complete.core.TriggerContext
---@return complete.kit.Async.AsyncTask complete.kit.LSP.CompletionContext?
function CompletionProvider:complete(trigger_context)
  return Async.run(function()
    local completion_options = self:get_completion_options()
    local trigger_characters = completion_options.triggerCharacters or {}

    ---Check should complete for new trigger context or not.
    local completion_context ---@type complete.kit.LSP.CompletionContext
    local completion_offset = self._state.completion_offset
    if kit.contains(trigger_characters, trigger_context.trigger_character) then
      -- trigger character based completion.
      -- TODO: VSCode does not show completion for `const a = |` case on the @vtsls/language-server even if language-server tells `<Space>` as trigger_character.
      completion_context = {
        triggerKind = LSP.CompletionTriggerKind.TriggerCharacter,
        triggerCharacter = trigger_context.trigger_character,
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
      local keyword_pattern = self:get_keyword_pattern()
      local next_keyword_offset = trigger_context:get_keyword_offset(keyword_pattern)
      if next_keyword_offset and next_keyword_offset < trigger_context.character + 1 then
        local prev_keyword_offset = self._state.trigger_context and self._state.trigger_context:get_keyword_offset(keyword_pattern)
        local is_incomplete = self._state and self._state.is_incomplete

        if is_incomplete and next_keyword_offset == prev_keyword_offset then
          -- invoke completion if previous response specifies the `isIncomplete=true` and offset is not changed.
          completion_context = {
            triggerKind = LSP.CompletionTriggerKind.TriggerForIncompleteCompletions,
          }
          completion_offset = next_keyword_offset
        elseif next_keyword_offset and next_keyword_offset ~= prev_keyword_offset then
          -- invoke completion if keyword_offset is changed.
          completion_context = {
            triggerKind = LSP.CompletionTriggerKind.Invoked,
          }
          completion_offset = next_keyword_offset
        end
      else
        -- drop previous completion response if keyword based completion was selected and not available.
        local is_not_trigger_character_completion = not self._state.completion_context or self._state.completion_context.triggerKind ~= LSP.CompletionTriggerKind.TriggerCharacter
        if is_not_trigger_character_completion then
          self:clear()
        end
      end
    end

    -- do not invoke new completion.
    if not completion_context then
      return
    end

    -- keep completion state for isIncomplete completion.
    local is_not_incomplete_completion = not self._state.is_incomplete or completion_context.triggerKind ~= LSP.CompletionTriggerKind.TriggerForIncompleteCompletions
    if not is_not_incomplete_completion then
      self._state = { ready_state = ReadyState.Waiiting }
    end
    self._state.ready_state = ReadyState.Fetching
    self._state.trigger_context = trigger_context
    self._state.completion_context = completion_context
    self._state.completion_offset = completion_offset

    -- invoke completion.
    local response = to_completion_list(self._source:complete(completion_context):await())

    -- ignore obsolete response.
    if self._state.trigger_context ~= trigger_context then
      return
    end

    -- adopt response.
    self:_adopt_response(trigger_context, response)

    return completion_context
  end)
end

---Accept completion response.
---@param list complete.kit.LSP.CompletionList
function CompletionProvider:_adopt_response(trigger_context, list)
  self._state.ready_state = ReadyState.Completed
  self._state.is_incomplete = list.isIncomplete or false
  self._state.items = {}
  for _, item in ipairs(list.items) do
    self._state.items[#self._state.items + 1] = CompletionItem.new(trigger_context, self, list, item)
  end
  self._state.matches = {}
  self._state.matches_items = {}
  self._state.matches_before_text = nil
  self._state.matches_cursor_offset = nil
  self._state.matches_keyword_offset = nil
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
  return not completion_options.documentSelector or DocumentSelector.score(trigger_context.bufnr, completion_options.documentSelector) ~= 0
end

---TODO: We should decide how to get the default keyword pattern here.
---@return string
function CompletionProvider:get_keyword_pattern()
  return self._config.keyword_pattern
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

---Clear completion state.
function CompletionProvider:clear()
  self._state = { ready_state = ReadyState.Waiiting }
end

---Return ready state.
---@return complete.core.CompletionProvider.ReadyState
function CompletionProvider:get_ready_state()
  return self._state.ready_state
end

---Return completion items.
---@param trigger_context complete.core.TriggerContext
---@param matcher complete.core.Matcher
---@return complete.core.Match[]
function CompletionProvider:get_matches(trigger_context, matcher)
  local next_cursor_offset = trigger_context.character + 1
  local next_keyword_offset = trigger_context:get_keyword_offset(self:get_keyword_pattern()) or -1
  local next_before_text = trigger_context.text_before
  local prev_cursor_offset = self._state.matches_cursor_offset or -2
  local prev_keyword_offset = self._state.matches_keyword_offset or -2
  local prev_before_text = self._state.matches_before_text
  self._state.matches_before_text = next_before_text
  self._state.matches_cursor_offset = next_cursor_offset
  self._state.matches_keyword_offset = next_keyword_offset

  local target_items = self._state.items or {}
  local is_forward_completion = prev_keyword_offset == next_keyword_offset and prev_cursor_offset <= next_cursor_offset
  if is_forward_completion then
    if prev_cursor_offset == next_cursor_offset and prev_before_text == next_before_text then
      return self._state.matches
    elseif prev_before_text == next_before_text:sub(1, #prev_before_text) then
      target_items = self._state.matches_items or {}
    end
  end

  self._state.matches = {}
  self._state.matches_items = {}
  for _, item in ipairs(target_items) do
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
        match_positions = label_text ~= filter_text and select(2, matcher(query_text, label_text)) or match_positions,
      }
    end
  end
  return self._state.matches
end

---Return keyword offest position.
---@return integer 1-origin utf8 byte index
function CompletionProvider:get_keyword_offset()
  if not self._state.trigger_context then
    error('The CompletionProvider: can only be called after completion has been called.')
  end

  return extract_keyword_range(self._state.trigger_context, self:get_keyword_pattern())[1]
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
