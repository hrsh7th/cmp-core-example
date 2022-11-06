local LSP = require('cmp-core.kit.LSP')
local Cache = require('cmp-core.kit.App.Cache')
local Position = require('cmp-core.kit.LSP.Position')
local Character = require('cmp-core.Character')
local PreviewText = require('cmp-core.PreviewText')

---@class cmp-core.CompletionItem
---@field public context cmp-core.Context
---@field public provider cmp-core.CompletionProvider
---@field public list cmp-core.kit.LSP.CompletionList
---@field public item cmp-core.kit.LSP.CompletionItem
---@field public resolved_item? cmp-core.kit.LSP.CompletionItem
---@field public cache cmp-core.kit.App.Cache
local CompletionItem = {}
CompletionItem.__index = CompletionItem

---Create new CompletionItem.
---@param context cmp-core.Context
---@param provider cmp-core.CompletionProvider
---@param list cmp-core.kit.LSP.CompletionList
---@param item cmp-core.kit.LSP.CompletionItem
function CompletionItem.new(context, provider, list, item)
  local self = setmetatable({}, CompletionItem)
  self.context = context
  self.provider = provider
  self.list = list
  self.item = item
  self.resolved_item = nil
  self.cache = Cache.new()
  return self
end

---Get sugest offset position 1-origin utf-8 byte index.
---NOTE: This is not part of LSP spec.
---@return number
function CompletionItem:get_offset()
  local insert_range = self:get_insert_range()
  return self.context.cache:ensure('get_offset:' .. insert_range.start.character, function()
    local offset = insert_range.start.character + 1
    for i = offset, #self.context.text do
      if not Character.is_white(self.context.text:byte(i)) then
        break
      end
      offset = i
    end
    return offset
  end)
end

---Get the text that will be inserted if the item is selected.
---NOTE: This is not part of LSP spec.
---@reutrn string
function CompletionItem:get_preview_text()
  return self.cache:ensure('get_preview_text', function()
    local insert_text = self:get_insert_text()
    if self:get_insert_text_format() == LSP.InsertTextFormat.Snippet then
      insert_text = vim.lsp.util.parse_snippet(insert_text) --[[@as string]]
    end
    return PreviewText.create(self.context, insert_text)
  end)
end

---Get the text that will be inserted if the item is confirmed.
---@return string
function CompletionItem:get_insert_text()
  if self.item.textEditText then
    return self.item.textEditText
  elseif self.item.textEdit and self.item.textEdit.newText then
    return self.item.textEdit.newText
  elseif self.item.insertText then
    return self.item.insertText
  end
  return self.item.label
end

---Return insertTextFormat.
---@return cmp-core.kit.LSP.InsertTextFormat
function CompletionItem:get_insert_text_format()
  if self.item.insertTextFormat then
    return self.item.insertTextFormat
  end
  if self.list.itemDefaults and self.list.itemDefaults.insertTextFormat then
    return self.list.itemDefaults.insertTextFormat
  end
  return LSP.InsertTextFormat.PlainText
end

---Return insertTextMode.
---@return cmp-core.kit.LSP.InsertTextMode
function CompletionItem:get_insert_text_mode()
  if self.item.insertTextMode then
    return self.item.insertTextMode
  end
  if self.list.itemDefaults and self.list.itemDefaults.insertTextMode then
    return self.list.itemDefaults.insertTextMode
  end
  return LSP.InsertTextMode.asIs
end

---Return insert range.
---NOTE: The caching is correct because the spec defines that the textEdit range can't be updated via completionItem/resolve.
---@return cmp-core.kit.LSP.Range
function CompletionItem:get_insert_range()
  return self.cache:ensure('get_insert_range', function()
    local range --[[@as cmp-core.kit.LSP.Range]]
    if self.item.textEdit then
      if self.item.textEdit.insert then
        range = self.item.textEdit.insert
      else
        range = self.item.textEdit.range
      end
    elseif self.list.itemDefaults and self.list.itemDefaults.editRange then
      if self.list.itemDefaults.editRange.insert then
        range = self.list.itemDefaults.editRange.insert
      else
        range = self.list.itemDefaults.editRange
      end
    end
    if not range then
      range = self.provider:get_default_insert_range()
    end
    return self:_convert_range_encoding(range)
  end)
end

---Return replace range.
---NOTE: The caching is correct because the spec defines that the textEdit range can't be updated via completionItem/resolve.
---@return cmp-core.kit.LSP.Range
function CompletionItem:get_replace_range()
  return self.cache:ensure('get_replace_range', function()
    local range --[[@as cmp-core.kit.LSP.Range]]
    if self.item.textEdit then
      if self.item.textEdit.replace then
        range = self.item.textEdit.replace
      end
    elseif self.list.itemDefaults and self.list.itemDefaults.editRange then
      if self.list.itemDefaults.editRange.replace then
        range = self.list.itemDefaults.editRange.replace
      end
    end
    if not range then
      range = self.provider:get_default_replace_range()
    end
    return self:_convert_range_encoding(range)
  end)
end

---Resolve completion item (completionItem/resolve).
---@return cmp-core.kit.Async.AsyncTask
function CompletionItem:resolve()
  return self.cache:ensure('resolve', function()
    return self.provider:resolve(self.item):next(function(item)
      self.resolved_item = item
    end)
  end)
end

---Execute command (workspace/executeCommand).
---@return cmp-core.kit.Async.AsyncTask
function CompletionItem:execute()
  return self.provider:execute(self.item.command)
end

---Convert range encoding to LSP.PositionEncodingKind.UTF8.
---@param range cmp-core.kit.LSP.Range
---@return cmp-core.kit.LSP.Range
function CompletionItem:_convert_range_encoding(range)
  local from_encoding = self.provider:get_position_encoding_kind()
  return {
    start = self.context.cache:ensure(
      '_convert_range_encoding:start:' .. range.start .. ':' .. from_encoding,
      function()
        return Position.to_utf8(self.context.text, range.start, from_encoding)
      end
    ),
    ['end'] = self.context.cache:ensure(
      '_convert_range_encoding:end:' .. range['end'] .. ':' .. from_encoding,
      function()
        return Position.to_utf8(self.context.text, range['end'], from_encoding)
      end
    ),
  }
end

return CompletionItem
