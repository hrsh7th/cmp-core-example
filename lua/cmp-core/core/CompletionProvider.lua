local LSP = require('cmp-core.kit.LSP')
local AsyncTask = require('cmp-core.kit.Async.AsyncTask')
local RegExp = require('cmp-core.kit.Vim.RegExp')

---@class cmp-core.CompletionSource
---@field public get_position_encoding_kind? fun(self: unknown): cmp-core.kit.LSP.PositionEncodingKind
---@field public get_completion_options? fun(self: unknown): cmp-core.kit.LSP.CompletionOptions
---@field public resolve? fun(self: unknown, item: cmp-core.kit.LSP.CompletionItem): cmp-core.kit.Async.AsyncTask
---@field public execute? fun(self: unknown, command: cmp-core.kit.LSP.Command): cmp-core.kit.Async.AsyncTask
---@field public complete fun(self: unknown): cmp-core.kit.Async.AsyncTask
---@field public get_keyword_pattern fun(self: unknown): string

---@class cmp-core.CompletionProvider
---@field public source cmp-core.CompletionSource
---@field public context? cmp-core.LineContext
local CompletionProvider = {}
CompletionProvider.__index = CompletionProvider

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
---@param context cmp-core.LineContext
---@param keyword_pattern string
---@return integer, integer 1-origin utf8 byte index
local function extract_keyword_range(context, keyword_pattern)
  return unpack(context.cache:ensure('CompletionProvider:extract_keyword_range:' .. keyword_pattern, function()
    local c = context.character + 1
    local _, s, e = RegExp.extract_at(context.text, keyword_pattern, c)
    return { s or c, e or c }
  end))
end

---Create new CompletionProvider.
---@param source cmp-core.CompletionSource
---@return cmp-core.CompletionProvider
function CompletionProvider.new(source)
  local self = setmetatable({}, CompletionProvider)
  self.source = source
  self.context = nil
  self.config = {}
  return self
end

---Return LSP.PositionEncodingKind.
---@return cmp-core.kit.LSP.PositionEncodingKind
function CompletionProvider:get_position_encoding_kind()
  if not self.source.get_position_encoding_kind then
    return LSP.PositionEncodingKind.UTF16
  end
  return self.source:get_position_encoding_kind()
end

---Return LSP.CompletionOptions
---@return cmp-core.kit.LSP.CompletionOptions
function CompletionProvider:get_completion_options()
  if not self.source.get_completion_options then
    return {}
  end
  return self.source:get_completion_options()
end

---Completion (textDocument/completion).
---@param context cmp-core.LineContext
---@return cmp-core.kit.Async.AsyncTask cmp-core.kit.LSP.CompletionList
function CompletionProvider:complete(context)
  self.context = context
  return self.source
    :complete()
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
  if not self.source.resolve then
    return AsyncTask.resolve(item)
  end
  return self.source:resolve(item)
end

---Execute command (workspace/executeCommand).
---@param command cmp-core.kit.LSP.Command
---@return cmp-core.kit.Async.AsyncTask
function CompletionProvider:execute(command)
  if not self.source.resolve then
    return AsyncTask.resolve()
  end
  return self.source:execute(command)
end

---TODO: We should decide how to get the default keyword pattern here.
---@return string
function CompletionProvider:get_keyword_pattern()
  if self.source.get_keyword_pattern then
    return self.source:get_keyword_pattern()
  end
  return [[\%(-\?\d\+\%(\.\d\+\)\?\|\h\w*\%(-\w*\)*\)]]
end

---Return default offest position.
---@return integer 1-origin utf8 byte index
function CompletionProvider:get_default_offset()
  if not self.context then
    error('The CompletionProvider: can only be called after completion has been called.')
  end

  return (extract_keyword_range(self.context, self:get_keyword_pattern()))
end

---Create default insert range from keyword pattern.
---NOTE: This method returns the range that always specifies to 0-line.
---@return cmp-core.kit.LSP.Range utf8 byte index
function CompletionProvider:get_default_insert_range()
  if not self.context then
    error('The CompletionProvider: can only be called after completion has been called.')
  end

  local keyword_pattern = self:get_keyword_pattern()
  return self.context.cache:ensure('CompletionProvider:get_default_replace_range:' .. keyword_pattern, function()
    local s = extract_keyword_range(self.context, keyword_pattern)
    return {
      start = {
        line = 0,
        character = s - 1,
      },
      ['end'] = {
        line = 0,
        character = self.context.character,
      },
    }
  end)
end

---Create default replace range from keyword pattern.
---NOTE: This method returns the range that always specifies to 0-line.
---@return cmp-core.kit.LSP.Range utf8 byte index
function CompletionProvider:get_default_replace_range()
  if not self.context then
    error('The CompletionProvider: can only be called after completion has been called.')
  end

  local keyword_pattern = self:get_keyword_pattern()
  return self.context.cache:ensure('CompletionProvider:get_default_replace_range:' .. keyword_pattern, function()
    local s, e = extract_keyword_range(self.context, keyword_pattern)
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

return CompletionProvider
