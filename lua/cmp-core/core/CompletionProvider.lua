local LSP = require('cmp-core.kit.LSP')
local Async = require('cmp-core.kit.Async')
local RegExp = require('cmp-core.kit.Vim.RegExp')

---@class cmp-core.core.CompletionSource
---@field public get_keyword_pattern? fun(self: unknown): string
---@field public get_position_encoding_kind? fun(self: unknown): cmp-core.kit.LSP.PositionEncodingKind
---@field public get_completion_options? fun(self: unknown): cmp-core.kit.LSP.CompletionOptions
---@field public resolve? fun(self: unknown, item: cmp-core.kit.LSP.CompletionItem): cmp-core.kit.Async.AsyncTask
---@field public execute? fun(self: unknown, command: cmp-core.kit.LSP.Command): cmp-core.kit.Async.AsyncTask
---@field public complete fun(self: unknown, completion_context: cmp-core.kit.LSP.CompletionContext): cmp-core.kit.Async.AsyncTask

---Normalize response.
---@param response (cmp-core.kit.LSP.CompletionList|cmp-core.kit.LSP.CompletionItem[])?
---@return cmp-core.kit.LSP.CompletionList
local function normalize_response(response)
  response = response or {}
  if response.items then
    return response
  end
  return {
    isIncomplete = false,
    items = response,
  }
end

---Extract keyword pattern range for requested line context.
---@param context cmp-core.core.LineContext
---@param keyword_pattern string
---@return integer, integer 1-origin utf8 byte index
local function extract_keyword_range(context, keyword_pattern)
  return unpack(context.cache:ensure('CompletionProvider:extract_keyword_range:' .. keyword_pattern, function()
    local c = context.character + 1
    local _, s, e = RegExp.extract_at(context.text, keyword_pattern, c)
    return { s or c, e or c }
  end))
end

---@class cmp-core.core.CompletionProvider
---@field private _source cmp-core.core.CompletionSource
---@field private _context? cmp-core.core.LineContext
---@field private _list? cmp-core.kit.LSP.CompletionList
local CompletionProvider = {}
CompletionProvider.__index = CompletionProvider

---Create new CompletionProvider.
---@param source cmp-core.core.CompletionSource
---@return cmp-core.core.CompletionProvider
function CompletionProvider.new(source)
  local self = setmetatable({}, CompletionProvider)
  self._source = source
  self._context = nil
  return self
end

---Return LSP.PositionEncodingKind.
---@return cmp-core.kit.LSP.PositionEncodingKind
function CompletionProvider:get_position_encoding_kind()
  if not self._source.get_position_encoding_kind then
    return LSP.PositionEncodingKind.UTF16
  end
  return self._source:get_position_encoding_kind()
end

---Return LSP.CompletionOptions
---TODO: should consider how to listen to the source's option changes.
---@return cmp-core.kit.LSP.CompletionOptions
function CompletionProvider:get_completion_options()
  if not self._source.get_completion_options then
    return {}
  end
  return self._source:get_completion_options()
end

---Completion (textDocument/completion).
---TODO: not yet implemented.
---@param context cmp-core.core.LineContext
---@param force boolean?
---@return cmp-core.kit.Async.AsyncTask cmp-core.kit.LSP.CompletionList
function CompletionProvider:complete(context, force)
  local completion_context = self:_create_completion_context(context, force)
  if not completion_context then
    return Async.resolve()
  end

  self._context = context
  return self._source
      :complete(completion_context)
      :next(function(response)
        return normalize_response(response)
      end)
      :next(function(list)
        return list
      end)
end

---Resolve completion item (completionItem/resolve).
---@param item cmp-core.kit.LSP.CompletionItem
---@return cmp-core.kit.Async.AsyncTask
function CompletionProvider:resolve(item)
  if not self._source.resolve then
    return Async.resolve(item)
  end
  return self._source:resolve(item)
end

---Execute command (workspace/executeCommand).
---@param command cmp-core.kit.LSP.Command
---@return cmp-core.kit.Async.AsyncTask
function CompletionProvider:execute(command)
  if not self._source.resolve then
    return Async.resolve()
  end
  return self._source:execute(command)
end

---TODO: We should decide how to get the default keyword pattern here.
---@return string
function CompletionProvider:get_keyword_pattern()
  if self._source.get_keyword_pattern then
    return self._source:get_keyword_pattern()
  end
  return [[\h\?\w*]]
end

---Return default offest position.
---@return integer 1-origin utf8 byte index
function CompletionProvider:get_default_offset()
  if not self._context then
    error('The CompletionProvider: can only be called after completion has been called.')
  end

  return (extract_keyword_range(self._context, self:get_keyword_pattern()))
end

---Create default insert range from keyword pattern.
---NOTE: This method returns the range that always specifies to 0-line.
---@return cmp-core.kit.LSP.Range utf8 byte index
function CompletionProvider:get_default_insert_range()
  if not self._context then
    error('The CompletionProvider: can only be called after completion has been called.')
  end

  local keyword_pattern = self:get_keyword_pattern()
  return self._context.cache:ensure('CompletionProvider:get_default_insert_range:' .. keyword_pattern, function()
    local s = extract_keyword_range(self._context, keyword_pattern)
    return {
      start = {
        line = 0,
        character = s - 1,
      },
      ['end'] = {
        line = 0,
        character = self._context.character,
      },
    }
  end)
end

---Create default replace range from keyword pattern.
---NOTE: This method returns the range that always specifies to 0-line.
---@return cmp-core.kit.LSP.Range utf8 byte index
function CompletionProvider:get_default_replace_range()
  if not self._context then
    error('The CompletionProvider: can only be called after completion has been called.')
  end

  local keyword_pattern = self:get_keyword_pattern()
  return self._context.cache:ensure('CompletionProvider:get_default_replace_range:' .. keyword_pattern, function()
    local s, e = extract_keyword_range(self._context, keyword_pattern)
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

---Create CompletionContext.
---@param context cmp-core.core.LineContext
---@param force boolean?
---@return cmp-core.kit.LSP.CompletionContext
function CompletionProvider:_create_completion_context(context, force)
  local completion_options = self:get_completion_options()
  local trigger_characters = completion_options.triggerCharacters or {}

  ---@type cmp-core.kit.LSP.CompletionContext
  local completion_context
  if vim.tbl_contains(trigger_characters, context.char) then
    completion_context = {
      triggerKind = LSP.CompletionTriggerKind.TriggerCharacter,
      triggerCharacter = context.char,
    }
  else
    if force then
      completion_context = {
        triggerKind = LSP.CompletionTriggerKind.Invoked,
      }
    else
      local is_incomplete = self._list and self._list.isIncomplete
      local keyword_pattern = self:get_keyword_pattern()
      local keyword_offset = context:get_keyword_offset(keyword_pattern)
      if keyword_offset then
        if is_incomplete then
          completion_context = {
            triggerKind = LSP.CompletionTriggerKind.TriggerForIncompleteCompletions,
          }
        elseif not self._context or keyword_offset ~= self._context:get_keyword_offset(keyword_pattern) then
          vim.print({
            new_keyword_offset = keyword_offset,
            old_keyword_offset = self._context and self._context:get_keyword_offset(keyword_pattern),
          })
          completion_context = {
            triggerKind = LSP.CompletionTriggerKind.Invoked,
          }
        end
      end
    end
  end
  self._context = context
  return completion_context
end

return CompletionProvider
