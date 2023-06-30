local kit = require('cmp-core.kit')
local LSP = require('cmp-core.kit.LSP')
local Cache = require('cmp-core.kit.App.Cache')
local Async = require('cmp-core.kit.Async')
local Position = require('cmp-core.kit.LSP.Position')
local LinePatch = require('cmp-core.core.LinePatch')
local LineContext = require('cmp-core.core.LineContext')
local Character = require('cmp-core.core.Character')
local SelectText = require('cmp-core.core.SelectText')

---@alias cmp-core.core.ExpandSnippet fun(s: string, option: {})

---@class cmp-core.core.CompletionItem
---@field private _context cmp-core.core.LineContext
---@field private _provider cmp-core.core.CompletionProvider
---@field private _list cmp-core.kit.LSP.CompletionList
---@field private _cache cmp-core.kit.App.Cache
---@field private _item cmp-core.kit.LSP.CompletionItem
---@field private _resolving cmp-core.kit.Async.AsyncTask
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
  self._cache = Cache.new()
  self._item = item
  self._resolving = nil
  return self
end

---Get sugest offset position 1-origin utf-8 byte index.
---NOTE: VSCode always shows the completion menu relative to the cursor position. This is vim specific implementation.
---@return number
function CompletionItem:get_offset()
  local default_offset = self._provider:get_default_offset()
  if not self:has_text_edit() then
    return default_offset
  end

  local insert_range = self:get_insert_range()
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
---NOTE: VSCode doesn't have the text inserted when item was selected. This is vim specific implementation.
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


    -- Fix filter_text for non-VSCode compliant servers such as clangd.
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
  if not self._provider.resolve then
    return Async.resolve()
  end

  return Async.run(function()
    self._resolving = self._resolving or (function()
      local item = kit.merge({}, self._item)
      for k, v in pairs(self._list.itemDefaults or {}) do
        if not item[k] and k ~= 'editRange' then
          item[k] = v
        end
      end
      return self._provider:resolve(item)
    end)()

    local resolved_item = self._resolving:await()
    if resolved_item then
      self._item = kit.merge(self._item, resolved_item)
      self._cache = Cache.new()
    else
      self._resolving = nil
    end
  end)
end

---Execute command (workspace/executeCommand).
---@return cmp-core.kit.Async.AsyncTask
function CompletionItem:execute()
  if self._provider.execute then
    return self._provider:execute(self._item.command)
  end
  return Async.resolve()
end

---Confirm item.
---@param option? { replace?: boolean, expand_snippet?: cmp-core.core.ExpandSnippet }
---@return cmp-core.kit.Async.AsyncTask
function CompletionItem:confirm(option)
  option = option or {}
  option.replace = option.replace or false

  return Async.run(function()
    -- Try resolve item.
    Async.race({ self:resolve(), Async.timeout(200) }):await()

    local current_context --[[@as cmp-core.core.LineContext]]

    -- Set dot-repeat register.
    current_context = LineContext.create()
    LinePatch.apply_by_keys(current_context.character - (self:get_offset() - 1), 0, self:get_select_text()):await()

    -- Save undopoint.
    vim.o.undolevels = vim.o.undolevels

    -- Restore the requested state.
    current_context = LineContext.create()
    LinePatch.apply_by_func(current_context.character - (self:get_offset() - 1), 0, self._context.text:sub(self:get_offset(), self._context.character)):await()

    -- Make overwrite information.
    local range = option.replace and self:get_replace_range() or self:get_insert_range()
    local before = self._context.character - range.start.character
    local after = range['end'].character - self._context.character

    -- Apply sync additionalTextEdits if provied.
    if self._item.additionalTextEdits then
      vim.lsp.util.apply_text_edits(kit.map(self._item.additionalTextEdits, function(text_edit)
        return kit.merge({
          range = self:_convert_range_encoding(text_edit.range)
        }, text_edit)
      end), 0, LSP.PositionEncodingKind.UTF8)
    end

    -- Expansion.
    if self:get_insert_text_format() == LSP.InsertTextFormat.Snippet and option.expand_snippet then
      -- remove range of text and expand snippet.
      LinePatch.apply_by_func(before, after, ''):await()
      option.expand_snippet(self:get_insert_text(), {})
    else
      -- insert text to range.
      LinePatch.apply_by_func(before, after, self:get_insert_text()):await()
    end

    -- Apply async additionalTextEdits if provided.
    if not self._item.additionalTextEdits then
      do
        local prev_context = LineContext.create()
        self:resolve():next(function()
          if self._item.additionalTextEdits then
            local next_context = LineContext.create()
            local is_skipped = false
            is_skipped = is_skipped or (prev_context.line ~= next_context.line)
            is_skipped = is_skipped or #vim.iter(self._item.additionalTextEdits):filter(function(text_edit)
              return text_edit.range.start.line >= next_context.line
            end) > 0
            if not is_skipped then
              vim.lsp.util.apply_text_edits(kit.map(self._item.additionalTextEdits, function(text_edit)
                return kit.merge({
                  range = self:_convert_range_encoding(text_edit.range)
                }, text_edit)
              end), 0, LSP.PositionEncodingKind.UTF8)
            end
          end
        end)
      end
    end

    -- Execute command.
    self:execute():await()
  end)
end

---Return this has textEdit or not.
---@return boolean
function CompletionItem:has_text_edit()
  return not not (
    self._item.textEdit or
    (self._list.itemDefaults and self._list.itemDefaults.editRange)
  )
end

---Return insert range.
---NOTE: The line property can't be used. This is usually 0.
---NOTE: This range is utf-8 byte length based.
---@return cmp-core.kit.LSP.Range
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
  if not range then
    range = self._provider:get_default_insert_range()
  end
  return self:_convert_range_encoding(range)
end

---Return replace range.
---NOTE: The line property can't be used. This is usually 0.
---NOTE: This range is utf-8 byte length based.
---@return cmp-core.kit.LSP.Range
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
  if not range then
    range = self:_max_range(self._provider:get_default_replace_range(), self:get_insert_range())
  end
  return self:_convert_range_encoding(range)
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
---@param range_ cmp-core.kit.LSP.Range
---@param ... cmp-core.kit.LSP.Range
---@return cmp-core.kit.LSP.Range
function CompletionItem:_max_range(range_, ...)
  local max --[[@as cmp-core.kit.LSP.Range]]
  for _, range in ipairs({ range_, ... }) do
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
