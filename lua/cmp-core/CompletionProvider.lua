local LSP = require('cmp-core.kit.LSP')
local AsyncTask = require('cmp-core.kit.Async.AsyncTask')

---@class cmp-core.CompletionSource
---@field public get_position_encoding_kind fun(self: unknown): cmp-core.kit.LSP.PositionEncodingKind
---@field public get_keyword_pattern fun(self: unknown): string
---@field public get_completion_options fun(self: unknown): cmp-core.kit.LSP.CompletionOptions
---@field public complete fun(self: unknown): cmp-core.kit.Async.AsyncTask
---@field public resolve fun(self: unknown, item: cmp-core.kit.LSP.CompletionItem): cmp-core.kit.Async.AsyncTask
---@field public execute fun(self: unknown, command: cmp-core.kit.LSP.Command): cmp-core.kit.Async.AsyncTask

---@class cmp-core.CompletionProvider
---@field public source cmp-core.CompletionSource
---@field public context cmp-core.Context
local CompletionProvider = {}
CompletionProvider.__index = CompletionProvider

---Create new CompletionProvider.
---@param source cmp-core.CompletionSource
---@return cmp-core.CompletionProvider
function CompletionProvider.new(source)
  local self = setmetatable({}, CompletionProvider)
  self.source = source
  self.context = nil
  return self
end

---Return LSP.PositionEncodingKind.
function CompletionProvider:get_position_encoding_kind()
  if not self.source.get_position_encoding_kind then
    return LSP.PositionEncodingKind.UTF16
  end
  return self.source:get_position_encoding_kind()
end

---Completion (textDocument/completion).
---@param context cmp-core.Context
---@return cmp-core.kit.Async.AsyncTask
function CompletionProvider:complete(context)
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
  return self.source:execute(command)
end

---Create default insert range from keyword pattern.
---@return cmp-core.kit.LSP.Range
function CompletionProvider:get_default_insert_range()
end

---Create default replace range from keyword pattern.
---@return cmp-core.kit.LSP.Range
function CompletionProvider:get_default_replace_range()
end

return CompletionProvider

