---@diagnostic disable: invisible
local kit = require('complete.kit')
local LSP = require('complete.kit.LSP')
local Async = require('complete.kit.Async')
local RegExp = require('complete.kit.Vim.RegExp')
local CompletionItem = require('complete.core.CompletionItem')

---@class complete.core.CompletionSource.Configuration
---@field public keyword_pattern? string
---@field public position_encoding_kind? complete.kit.LSP.PositionEncodingKind
---@field public completion_options? complete.kit.LSP.CompletionRegistrationOptions

---@class complete.core.CompletionSource
---@field public configure? fun(self: unknown, configure: fun(configuration: complete.core.CompletionSource.Configuration))
---@field public resolve? fun(self: unknown, item: complete.kit.LSP.CompletionItem): complete.kit.Async.AsyncTask
---@field public execute? fun(self: unknown, command: complete.kit.LSP.Command): complete.kit.Async.AsyncTask
---@field public complete fun(self: unknown, completion_context: complete.kit.LSP.CompletionContext): complete.kit.Async.AsyncTask

---@class complete.core.CompletionState
---@field public incomplete boolean
---@field public items complete.core.CompletionItem[]

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
---@return integer, integer 1-origin utf8 byte index
local function extract_keyword_range(trigger_context, keyword_pattern)
  return unpack(trigger_context.cache:ensure('CompletionProvider:extract_keyword_range:' .. keyword_pattern, function()
    local c = trigger_context.character + 1
    local _, s, e = RegExp.extract_at(trigger_context.text, keyword_pattern, c)
    return { s or c, e or c }
  end))
end

---@class complete.core.CompletionProvider
---@field private _source complete.core.CompletionSource
---@field private _config complete.core.CompletionSource.Configuration
---@field private _trigger_context? complete.core.TriggerContext
---@field private _state? complete.core.CompletionState
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

  if source.configure then
    source:configure(function(configuration)
      self._config.keyword_pattern = configuration.keyword_pattern or self._config.keyword_pattern
      self._config.position_encoding_kind = configuration.position_encoding_kind or self._config.position_encoding_kind
      self._config.completion_options = configuration.completion_options or self._config.completion_options
    end)
  end

  return self
end

---Completion (textDocument/completion).
---@param trigger_context complete.core.TriggerContext
---@return complete.kit.Async.AsyncTask complete.kit.LSP.CompletionList?
function CompletionProvider:complete(trigger_context)
  return Async.run(function()
    -- Check completion context.
    local completion_context = self:_ensure_completion_context(trigger_context)
    if not completion_context then
      return
    end
    self._trigger_context = trigger_context

    -- Invoke completion.
    local response = self._source:complete(completion_context):await()

    -- Skip for new context.
    if self._trigger_context ~= trigger_context then
      return
    end

    -- Adopt response.
    local list = to_completion_list(response)
    self._state = {} ---@type complete.core.CompletionState
    self._state.incomplete = list.isIncomplete or false
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

---Return completion items.
---@return complete.core.CompletionItem[]
function CompletionProvider:get_items()
  return self._state.items
end

---Return default offest position.
---@return integer 1-origin utf8 byte index
function CompletionProvider:get_default_offset()
  if not self._trigger_context then
    error('The CompletionProvider: can only be called after completion has been called.')
  end

  return (extract_keyword_range(self._trigger_context, self:get_keyword_pattern()))
end

---Create default insert range from keyword pattern.
---NOTE: This method returns the range that always specifies to 0-line.
---@return complete.kit.LSP.Range utf8 byte index
function CompletionProvider:get_default_insert_range()
  if not self._trigger_context then
    error('The CompletionProvider: can only be called after completion has been called.')
  end

  local keyword_pattern = self:get_keyword_pattern()
  return self._trigger_context.cache:ensure('CompletionProvider:get_default_insert_range:' .. keyword_pattern, function()
    local s = extract_keyword_range(self._trigger_context, keyword_pattern)
    return {
      start = {
        line = 0,
        character = s - 1,
      },
      ['end'] = {
        line = 0,
        character = self._trigger_context.character,
      },
    }
  end)
end

---Create default replace range from keyword pattern.
---NOTE: This method returns the range that always specifies to 0-line.
---@return complete.kit.LSP.Range utf8 byte index
function CompletionProvider:get_default_replace_range()
  if not self._trigger_context then
    error('The CompletionProvider: can only be called after completion has been called.')
  end

  local keyword_pattern = self:get_keyword_pattern()
  return self._trigger_context.cache:ensure('CompletionProvider:get_default_replace_range:' .. keyword_pattern, function()
    local s, e = extract_keyword_range(self._trigger_context, keyword_pattern)
    return {
      start = {
        line = 0,
        character = s - 1,
      },
      ['end'] = {
        line = 0,
        character = e - 1,
      },
    }
  end)
end

---Ensure CompletionContext.
---@param trigger_context complete.core.TriggerContext
---@return complete.kit.LSP.CompletionContext
function CompletionProvider:_ensure_completion_context(trigger_context)
  local completion_options = self:get_completion_options()
  local trigger_characters = completion_options.triggerCharacters or {}

  ---@type complete.kit.LSP.CompletionContext
  local completion_context

  if kit.contains(trigger_characters, trigger_context.trigger_character) then
    -- invoke completion if triggerCharacters contains the context.char.
    completion_context = {
      triggerKind = LSP.CompletionTriggerKind.TriggerCharacter,
      triggerCharacter = trigger_context.trigger_character,
    }
  else
    if trigger_context.force then
      -- invoke completion if force is true. (manual completion)
      completion_context = {
        triggerKind = LSP.CompletionTriggerKind.Invoked,
      }
    else
      local is_incomplete = self._state and self._state.incomplete
      local keyword_pattern = self:get_keyword_pattern()
      local keyword_offset = trigger_context:get_keyword_offset(keyword_pattern)

      -- check keyword pattern is matched or not.
      if keyword_offset then
        if is_incomplete then
          -- invoke completion if previous response specifies the `isIncomplete=true`.
          completion_context = {
            triggerKind = LSP.CompletionTriggerKind.TriggerForIncompleteCompletions,
          }
        elseif not self._trigger_context or keyword_offset ~= self._trigger_context:get_keyword_offset(keyword_pattern) then
          -- invoke completion if matched the new keyword or keyword offset is changed.
          completion_context = {
            triggerKind = LSP.CompletionTriggerKind.Invoked,
          }
        end
      end
    end
  end
  return completion_context
end

return CompletionProvider
