---@diagnostic disable: invisible
local kit = require('complete.kit')
local LSP = require('complete.kit.LSP')
local Async = require('complete.kit.Async')
local RegExp = require('complete.kit.Vim.RegExp')
local CompletionItem = require('complete.core.CompletionItem')

---@enum complete.core.CompletionProvider.ReadyState
local ReadyState = {
  Waiiting = 'Waiting',
  Fetching = 'Fetching',
  Completed = 'Completed',
}

---@class complete.core.CompletionProvider.State
---@field public ready_state? complete.core.CompletionProvider.ReadyState
---@field public is_incomplete? boolean
---@field public items? complete.core.CompletionItem[]

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

---@class complete.core.CompletionProvider
---@field private _source complete.core.CompletionSource
---@field private _config complete.core.CompletionSource.Configuration
---@field private _state complete.core.CompletionProvider.State
---@field private _trigger_context? complete.core.TriggerContext
---@field private _completion_offset? integer
local CompletionProvider = {}
CompletionProvider.__index = CompletionProvider

---Create new CompletionProvider.
---@param source complete.core.CompletionSource
---@return complete.core.CompletionProvider
function CompletionProvider.new(source)
  local self = setmetatable({}, CompletionProvider)
  self._source = source
  self._config = {
    keyword_pattern = [[\%(-\?\d\+\%(\.\d\+\)\?\|\h\w*\%(-\w*\)*\)]],
    position_encoding_kind = LSP.PositionEncodingKind.UTF16,
    completion_options = {},
  }
  self._state = { ready_state = ReadyState.Waiiting }

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
      end
    })
  end

  return self
end

---Completion (textDocument/completion).
---@param trigger_context complete.core.TriggerContext
---@return complete.kit.Async.AsyncTask complete.kit.LSP.CompletionList?
function CompletionProvider:complete(trigger_context)
  return Async.run(function()
    local completion_options = self:get_completion_options()
    local trigger_characters = completion_options.triggerCharacters or {}

    ---Check should complete for new trigger context or not.
    local completion_context --@type complete.kit.LSP.CompletionContext
    local completion_offset = self._completion_offset
    if kit.contains(trigger_characters, trigger_context.trigger_character) then
      -- invoke completion if triggerCharacters contains the context.char.
      completion_context = {
        triggerKind = LSP.CompletionTriggerKind.TriggerCharacter,
        triggerCharacter = trigger_context.trigger_character,
      }
      completion_offset = trigger_context.character + 1
    elseif trigger_context.force then
      -- invoke completion if force is true. (manual completion)
      completion_context = {
        triggerKind = LSP.CompletionTriggerKind.Invoked,
      }
      completion_offset = trigger_context.character + 1
    else
      local keyword_pattern = self:get_keyword_pattern()
      local next_keyword_offset = trigger_context:get_keyword_offset(keyword_pattern)
      local prev_keyword_offset = self._trigger_context and self._trigger_context:get_keyword_offset(keyword_pattern)
      local is_incomplete = self._state and self._state.is_incomplete

      if is_incomplete and next_keyword_offset == prev_keyword_offset then
        -- invoke completion if previous response specifies the `isIncomplete=true` and offset is not changed.
        completion_context = {
          triggerKind = LSP.CompletionTriggerKind.TriggerForIncompleteCompletions,
        }
        completion_offset = next_keyword_offset
      elseif next_keyword_offset and next_keyword_offset ~= prev_keyword_offset then
        -- invoke completion if matched the new keyword or keyword offset is changed.
        completion_context = {
          triggerKind = LSP.CompletionTriggerKind.Invoked,
        }
        completion_offset = next_keyword_offset
      end
    end
    if not completion_context then
      if self._completion_offset ~= completion_offset then
        self._state = { ready_state = ReadyState.Waiiting }
      end
      return
    end
    self._trigger_context = trigger_context
    self._completion_offset = completion_offset
    self._state = {
      -- TODO: can we set 'fetching' always and it can be improve the performance without degrading UX?
      ready_state = self._state.is_incomplete and self._state.ready_state or ReadyState.Fetching
    }

    -- Invoke completion.
    local response = self._source:complete(completion_context):await()

    -- Ignore obsolete response.
    if self._trigger_context ~= trigger_context then
      return
    end

    -- Adopt response.
    local list = to_completion_list(response)
    self._state = {} ---@type complete.core.CompletionProvider.State
    self._state.ready_state = ReadyState.Completed
    self._state.is_incomplete = list.isIncomplete or false
    self._state.items = {}
    for _, item in ipairs(list.items) do
      table.insert(self._state.items, CompletionItem.new(trigger_context, self, response, item))
    end

    return completion_context
  end)
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

---Return ready state.
---@return complete.core.CompletionProvider.ReadyState
function CompletionProvider:get_ready_state()
  return self._state.ready_state
end

---Return completion items.
---@return complete.core.CompletionItem[]
function CompletionProvider:get_items()
  return self._state.items
end

---Return keyword offest position.
---@return integer 1-origin utf8 byte index
function CompletionProvider:get_keyword_offset()
  if not self._trigger_context then
    error('The CompletionProvider: can only be called after completion has been called.')
  end

  return extract_keyword_range(self._trigger_context, self:get_keyword_pattern())[1]
end

---Create default insert range from keyword pattern.
---NOTE: This method returns the range that always specifies to 0-line.
---@return complete.kit.LSP.Range utf8 byte index
function CompletionProvider:get_default_insert_range()
  if not self._trigger_context then
    error('The CompletionProvider: can only be called after completion has been called.')
  end

  local keyword_pattern = self:get_keyword_pattern()
  local cache_key = string.format('%s:%s', 'CompletionProvider:get_default_insert_range', keyword_pattern)
  if not self._trigger_context.cache[cache_key] then
    local s = extract_keyword_range(self._trigger_context, keyword_pattern)[1]
    self._trigger_context.cache[cache_key] = {
      start = {
        line = 0,
        character = s - 1,
      },
      ['end'] = {
        line = 0,
        character = self._trigger_context.character,
      },
    }
  end
  return self._trigger_context.cache[cache_key]
end

---Create default replace range from keyword pattern.
---NOTE: This method returns the range that always specifies to 0-line.
---@return complete.kit.LSP.Range utf8 byte index
function CompletionProvider:get_default_replace_range()
  if not self._trigger_context then
    error('The CompletionProvider: can only be called after completion has been called.')
  end

  local keyword_pattern = self:get_keyword_pattern()
  local cache_key = string.format('%s:%s', 'CompletionProvider:get_default_replace_range', keyword_pattern)
  if not self._trigger_context.cache[cache_key] then
    local s, e = unpack(extract_keyword_range(self._trigger_context, keyword_pattern))
    self._trigger_context.cache[cache_key] = {
      start = {
        line = 0,
        character = s - 1,
      },
      ['end'] = {
        line = 0,
        character = e - 1,
      },
    }
  end
  return self._trigger_context.cache[cache_key]
end

return CompletionProvider
