---@class cmp-core.CompletionSource
---@field public get_all_commit_characters fun(): string[]
---@field public is_resolve_supported fun(): boolean
---@field public is_label_detail_supported fun(): boolean
---@field public get_trigger_characters fun(): cmp-core.kit.LSP.CompletionOptions
---@field public get_position_encoding_kind fun(): cmp-core.kit.LSP.PositionEncodingKind
---@field public complete fun(): cmp-core.kit.Async.AsyncTask
---@field public resolve fun(self, item: cmp-core.kit.LSP.CompletionItem): cmp-core.kit.Async.AsyncTask
---@field public execute fun(self, item: cmp-core.kit.LSP.CompletionItem): cmp-core.kit.Async.AsyncTask

---@class cmp-core.CompletionProvider
---@field public name string
---@field public source cmp-core.CompletionSource
local CompletionProvider = {}
CompletionProvider.__index = CompletionProvider

---Create new CompletionProvider.
---@param source cmp-core.CompletionSource
---@return cmp-core.CompletionProvider
function CompletionProvider.new(name, source)
  local self = setmetatable({}, CompletionProvider)
  self.name = name
  self.source = source
  return self
end

---Return LSP.PositionEncodingKind.
---@NOTE: The default value is UTF8.
function CompletionProvider:get_position_encoding_kind()
  return self.source.get_position_encoding_kind()
end

function CompletionProvider:complete()
end

---@param item cmp-core.kit.LSP.CompletionItem
function CompletionProvider:resolve(item)
  return self.source:resolve(item)
end

---@param item cmp-core.kit.LSP.CompletionItem
function CompletionProvider:execute(item)
  return self.source:execute(item)
end

---@return cmp-core.kit.LSP.Range
function CompletionProvider:get_default_insert_range()
end

---@return cmp-core.kit.LSP.Range
function CompletionProvider:get_default_replace_range()
end

return CompletionProvider

