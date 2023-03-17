local LSP = require('cmp-core.kit.LSP')
local Cache = require('cmp-core.kit.App.Cache')
local Async = require('cmp-core.kit.Async')
local Position = require('cmp-core.kit.LSP.Position')
local LinePatch = require('cmp-core.core.LinePatch')
local LineContext = require('cmp-core.core.LineContext')
local Character = require('cmp-core.core.Character')
local SelectText = require('cmp-core.core.SelectText')

---@class cmp-core.core.CompletionItem
---@field private _context cmp-core.core.LineContext
---@field private _provider cmp-core.core.CompletionProvider
---@field private _list cmp-core.kit.LSP.CompletionList
---@field private _item cmp-core.kit.LSP.CompletionItem
---@field private _resolved_item? cmp-core.kit.LSP.CompletionItem
---@field private _cache cmp-core.kit.App.Cache
local CompletionItem = {}
CompletionItem.__index = CompletionItem

---Create new CompletionItem.
---@param context cmp-core.core.LineContext
---@param provider cmp-core.core.CompletionProvider
---@param list cmp-core.kit.LSP.CompletionList
---@param item cmp-core.kit.LSP.CompletionItem
function CompletionItem.new(context, provider, list, item)
  local self = setmetatable({}, CompletionItem)
  self._context = context
  self._provider = provider
  self._list = list
  self._item = item
  self._resolved_item = nil
  self._cache = Cache.new()
  return self
end

---Get sugest offset position 1-origin utf-8 byte index.
---NOTE: This is not part of LSP spec.
---TODO: We should support sementic offset calculation (nvim-cmp did it).
---@return number
function CompletionItem:get_offset()
  local default_offset = self._provider:get_default_offset()

  local insert_range = self:get_insert_range()
  if not insert_range then
    return default_offset
  end
  return self._context.cache:ensure('get_offset:' .. insert_range.start.character, function()
    local offset = insert_range.start.character + 1
    for i = offset, default_offset do
      offset = i
      if not Character.is_white(self._context.text:byte(i)) then
        break
      end
    end
    return math.min(offset, default_offset)
  end)
end

---Return select text that will be inserted if the item is selected.
---NOTE: This is not part of LSP spec.
---@reutrn string
function CompletionItem:get_select_text()
  return self._cache:ensure('get_select_text', function()
    local text = self:get_insert_text()
    if self:get_insert_text_format() == LSP.InsertTextFormat.Snippet then
      text = vim.lsp.util.parse_snippet(text) --[[@as string]]
    end
    return SelectText.create(text)
  end)
end

---Return filter text that will be used for matching.
function CompletionItem:get_filter_text()
  return self._cache:ensure('get_filter_text', function()
    local text = self._item.filterText
    if not text then
      text = self._item.label
    end
    text = text:gsub('^%s+', ''):gsub('%s+$', '')

    local delta = self._provider:get_default_offset() - self:get_offset()
    if delta > 0 then
      local prefix = self._context.text:sub(self:get_offset(), self._provider:get_default_offset() - 1)
      if text:sub(1, #prefix) ~= prefix then
        text = prefix .. text
      end
    end
    return text
  end)
end

---Return insert text that will be inserted if the item is confirmed.
---@return string
function CompletionItem:get_insert_text()
  if self._item.textEditText then
    return self._item.textEditText
  elseif self._item.textEdit and self._item.textEdit.newText then
    return self._item.textEdit.newText
  elseif self._item.insertText then
    return self._item.insertText
  end
  return self._item.label
end

---Return insertTextFormat.
---@return cmp-core.kit.LSP.InsertTextFormat
function CompletionItem:get_insert_text_format()
  if self._item.insertTextFormat then
    return self._item.insertTextFormat
  end
  if self._list.itemDefaults and self._list.itemDefaults.insertTextFormat then
    return self._list.itemDefaults.insertTextFormat
  end
  return LSP.InsertTextFormat.PlainText
end

---Return insertTextMode.
---@return cmp-core.kit.LSP.InsertTextMode
function CompletionItem:get_insert_text_mode()
  if self._item.insertTextMode then
    return self._item.insertTextMode
  end
  if self._list.itemDefaults and self._list.itemDefaults.insertTextMode then
    return self._list.itemDefaults.insertTextMode
  end
  return LSP.InsertTextMode.asIs
end

---Resolve completion item (completionItem/resolve).
---@return cmp-core.kit.Async.AsyncTask
function CompletionItem:resolve()
  return Async.run(function()
    local resolved_item = self._cache
        :ensure('resolve', function()
          if self._provider.resolve then
            return self._provider:resolve(self._item)
          end
          return Async.resolve(self._item)
        end)
        :await()
    if not resolved_item then
      self._cache:del('resolve')
    end
    return resolved_item or self._item
  end)
end

---Execute command (workspace/executeCommand).
---@return cmp-core.kit.Async.AsyncTask
function CompletionItem:execute()
  return self._provider:execute(self._item.command)
end

---Confirm item.
---@param option? { replace?: boolean }
---@return cmp-core.kit.Async.AsyncTask
function CompletionItem:confirm(option)
  option = option or {}
  option.replace = option.replace or false

  return Async.run(function()
    local context --[[@as cmp-core.core.LineContext]]

    -- Set dot-repeat register.
    context = LineContext.create()
    LinePatch.apply_by_keys(context.character - (self:get_offset() - 1), 0, self:get_select_text()):await()

    -- Restore the requested state.
    context = LineContext.create()
    LinePatch.apply_by_func(context.character - (self:get_offset() - 1), 0, self._context.text:sub(self:get_offset(), self._context.character)):await()

    -- Make overwrite information.
    local before, after
    if option.replace then
      local range = self:get_replace_range() or self:_max_range(self._provider:get_default_replace_range(), self:get_insert_range()) --[[@as cmp-core.kit.LSP.Range]]
      before = self._context.character - range.start.character
      after = range['end'].character - self._context.character
    else
      local range = (self:get_insert_range() or self._provider:get_default_insert_range())
      before = self._context.character - range.start.character
      after = range['end'].character - self._context.character
    end

    -- Apply sync additionalTextEdits if provied.
    if self._item.additionalTextEdits then
      vim.lsp.util.apply_text_edits(self._item.additionalTextEdits, 0, LSP.PositionEncodingKind.UTF8)
    end

    -- TODO: should accept snippet expansion function.
    LinePatch.apply_by_func(before, after, self:get_insert_text()):await()

    -- Apply async additionalTextEdits if provided.
    if not self._item.additionalTextEdits then
      local resolved_item = self:resolve():await()
      if resolved_item.additionalTextEdits then
        vim.lsp.util.apply_text_edits(resolved_item.additionalTextEdits, 0, LSP.PositionEncodingKind.UTF8)
      end
    end
  end)
end

---Return insert range.
---NOTE: The line property can't be used. This is usually 0.
---NOTE: This range is utf-8 byte length based.
---@return cmp-core.kit.LSP.Range?
function CompletionItem:get_insert_range()
  local range --[[@as cmp-core.kit.LSP.Range]]
  if self._item.textEdit then
    if self._item.textEdit.insert then
      range = self._item.textEdit.insert
    else
      range = self._item.textEdit.range
    end
  elseif self._list.itemDefaults and self._list.itemDefaults.editRange then
    if self._list.itemDefaults.editRange.insert then
      range = self._list.itemDefaults.editRange.insert
    else
      range = self._list.itemDefaults.editRange
    end
  end
  if range then
    return self:_convert_range_encoding(range)
  end
end

---Return replace range.
---NOTE: The line property can't be used. This is usually 0.
---NOTE: This range is utf-8 byte length based.
---@return cmp-core.kit.LSP.Range?
function CompletionItem:get_replace_range()
  local range --[[@as cmp-core.kit.LSP.Range]]
  if self._item.textEdit then
    if self._item.textEdit.replace then
      range = self._item.textEdit.replace
    end
  elseif self._list.itemDefaults and self._list.itemDefaults.editRange then
    if self._list.itemDefaults.editRange.replace then
      range = self._list.itemDefaults.editRange.replace
    end
  end
  if range then
    return self:_convert_range_encoding(range)
  end
end

---Convert range encoding to LSP.PositionEncodingKind.UTF8.
---@param range cmp-core.kit.LSP.Range
---@return cmp-core.kit.LSP.Range
function CompletionItem:_convert_range_encoding(range)
  local from_encoding = self._provider:get_position_encoding_kind()
  if from_encoding == LSP.PositionEncodingKind.UTF8 then
    return range
  end
  return {
    start = self._context.cache:ensure('CompletionItem:_convert_range_encoding:start:' .. range.start.character .. ':' .. from_encoding, function()
      return Position.to_utf8(self._context.text, range.start, from_encoding)
    end),
    ['end'] = self._context.cache:ensure('CompletionItem:_convert_range_encoding:end:' .. range['end'].character .. ':' .. from_encoding, function()
      return Position.to_utf8(self._context.text, range['end'], from_encoding)
    end),
  }
end

---Get expanded range.
---@param ... cmp-core.kit.LSP.Range?
---@return cmp-core.kit.LSP.Range?
function CompletionItem:_max_range(...)
  local max --[[@as cmp-core.kit.LSP.Range]]
  for _, range in ipairs({ ... }) do
    if range then
      if not max then
        max = range
      else
        if range.start.character < max.start.character then
          max.start.character = range.start.character
        end
        if max['end'].character < range['end'].character then
          max['end'].character = range['end'].character
        end
      end
    end
  end
  return max
end

return CompletionItem
