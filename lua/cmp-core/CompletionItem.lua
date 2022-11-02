local LSP = require('cmp-core.kit.LSP')
local Range = require('cmp-core.kit.LSP.Range')
local Cache = require('cmp-core.kit.App.Cache')

---@class cmp-core.CompletionItem
---@field public context cmp-core.CompletionContext
---@field public provider cmp-core.CompletionProvider
---@field public list cmp-core.kit.LSP.CompletionList
---@field public item cmp-core.kit.LSP.CompletionItem
---@field public cache cmp-core.kit.App.Cache
local CompletionItem = {}
CompletionItem.__index = CompletionItem

---Create new CompletionItem.
---@param context cmp-core.CompletionContext
---@param provider cmp-core.CompletionProvider
---@param list cmp-core.kit.LSP.CompletionList
---@param item cmp-core.kit.LSP.CompletionItem
function CompletionItem.new(context, provider, list, item)
  local self = setmetatable({}, CompletionItem)
  self.context = context
  self.provider = provider
  self.list = list
  self.item = item
  self.cache = Cache.new()
  return self
end

---Return insert range.
---@param to_encoding? cmp-core.kit.LSP.PositionEncodingKind default is UTF8.
---@return cmp-core.kit.LSP.Range
function CompletionItem:get_insert_range(to_encoding)
  to_encoding = to_encoding or LSP.PositionEncodingKind.UTF8

  -- This cache is correct because the spec defines that the textEdit range can't be updated via completionItem/resolve.
  return self.cache:ensure('get_insert_range:' .. to_encoding, function()
    local range ---[[@as cmp-core.kit.LSP.Range]]
    if self.item.textEdit then
      if self.item.textEdit.insert then
        range = self.item.textEdit.insert
      else
        range = self.item.textEdit.range
      end
    elseif self.list.itemDefaults.editRange then
      if self.list.itemDefaults.editRange.insert then
        range = self.list.itemDefaults.editRange.insert
      else
        range = self.list.itemDefaults.editRange
      end
    end
    if not range then
      range = self.provider:get_default_insert_range()
    end
    return self:_convert_range_encoding(range, to_encoding)
  end)
end

---Return replace range.
---@param to_encoding? cmp-core.kit.LSP.PositionEncodingKind default is UTF8.
---@return cmp-core.kit.LSP.Range
function CompletionItem:get_replace_range(to_encoding)
  to_encoding = to_encoding or LSP.PositionEncodingKind.UTF8

  -- This cache is correct because the spec defines that the textEdit range can't be updated via completionItem/resolve.
  return self.cache:ensure('get_replace_range:' .. to_encoding, function()
    local range ---[[@as cmp-core.kit.LSP.Range]]
    if self.item.textEdit then
      if self.item.textEdit.replace then
        range = self.item.textEdit.replace
      end
    elseif self.list.itemDefaults.editRange then
      if self.list.itemDefaults.editRange.replace then
        range = self.list.itemDefaults.editRange.replace
      end
    end
    if not range then
      range = self.provider:get_default_replace_range()
    end
    return self:_convert_range_encoding(range, to_encoding)
  end)
end

function CompletionItem:resolve()
end

function CompletionItem:execute()
end

---Convert textEdit range to specified encoding.
---@NOTE: The textEdit range must be oneline range.
---@param range cmp-core.kit.LSP.Range
---@param to_encoding cmp-core.kit.LSP.PositionEncodingKind default is UTF8.
---@return cmp-core.kit.LSP.Range
function CompletionItem:_convert_range_encoding(range, to_encoding)
  if to_encoding == LSP.PositionEncodingKind.UTF8 then
    return Range.to_utf8(self.context.text, self.context.text, range, self.provider:get_position_encoding_kind())
  elseif to_encoding == LSP.PositionEncodingKind.UTF16 then
    return Range.to_utf16(self.context.text, self.context.text, range, self.provider:get_position_encoding_kind())
  elseif to_encoding == LSP.PositionEncodingKind.UTF32 then
    return Range.to_utf32(self.context.text, self.context.text, range, self.provider:get_position_encoding_kind())
  end
  return range
end

return CompletionItem

