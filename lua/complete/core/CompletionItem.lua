local kit = require('complete.kit')
local LSP = require('complete.kit.LSP')
local Cache = require('complete.kit.App.Cache')
local Async = require('complete.kit.Async')
local Position = require('complete.kit.LSP.Position')
local LinePatch = require('complete.core.LinePatch')
local TriggerContext = require('complete.core.TriggerContext')
local Character = require('complete.core.Character')
local SelectText = require('complete.core.SelectText')
local SnippetText = require('complete.core.SnippetText')

---@alias complete.core.ExpandSnippet fun(s: string, option: {})

---@class complete.core.CompletionItem
---@field private _trigger_context complete.core.TriggerContext
---@field private _provider complete.core.CompletionProvider
---@field private _completion_list complete.kit.LSP.CompletionList
---@field private _cache complete.kit.App.Cache
---@field private _item complete.kit.LSP.CompletionItem
---@field private _resolving complete.kit.Async.AsyncTask
local CompletionItem = {}
CompletionItem.__index = CompletionItem

---Create new CompletionItem.
---@param trigger_context complete.core.TriggerContext
---@param provider complete.core.CompletionProvider
---@param list complete.kit.LSP.CompletionList
---@param item complete.kit.LSP.CompletionItem
function CompletionItem.new(trigger_context, provider, list, item)
  local self = setmetatable({}, CompletionItem)
  self._trigger_context = trigger_context
  self._provider = provider
  self._completion_list = list
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
  return self._trigger_context.cache:ensure('get_offset:' .. insert_range.start.character, function()
    local offset = insert_range.start.character + 1
    for i = offset, default_offset do
      offset = i
      if not Character.is_white(self._trigger_context.text:byte(i)) then
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
      text = tostring(SnippetText.parse(text)) --[[@as string]]
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
      local prefix = self._trigger_context.text:sub(self:get_offset(), self._provider:get_default_offset() - 1)
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
---@return complete.kit.LSP.InsertTextFormat
function CompletionItem:get_insert_text_format()
  if self._item.insertTextFormat then
    return self._item.insertTextFormat
  end
  if self._completion_list.itemDefaults and self._completion_list.itemDefaults.insertTextFormat then
    return self._completion_list.itemDefaults.insertTextFormat
  end
  return LSP.InsertTextFormat.PlainText
end

---Return insertTextMode.
---@return complete.kit.LSP.InsertTextMode
function CompletionItem:get_insert_text_mode()
  if self._item.insertTextMode then
    return self._item.insertTextMode
  end
  if self._completion_list.itemDefaults and self._completion_list.itemDefaults.insertTextMode then
    return self._completion_list.itemDefaults.insertTextMode
  end
  return LSP.InsertTextMode.asIs
end

---Resolve completion item (completionItem/resolve).
---@return complete.kit.Async.AsyncTask
function CompletionItem:resolve()
  if not self._provider.resolve then
    return Async.resolve()
  end

  return Async.run(function()
    self._resolving = self._resolving or (function()
      local item = kit.merge({}, self._item)
      for k, v in pairs(self._completion_list.itemDefaults or {}) do
        if not item[k] and k ~= 'editRange' then
          item[k] = v
        end
      end
      return self._provider:resolve(item)
    end)()

    local resolved_item = self._resolving:await()
    if resolved_item then
      self._item = kit.merge(self._item, resolved_item)
      self._cache = Cache.new() -- clear all caches for new item.
    else
      self._resolving = nil
    end
  end)
end

---Execute command (workspace/executeCommand).
---@return complete.kit.Async.AsyncTask
function CompletionItem:execute()
  if self._provider.execute then
    return self._provider:execute(self._item.command)
  end
  return Async.resolve()
end

---Commit item.
---@param option? { replace?: boolean, expand_snippet?: complete.core.ExpandSnippet }
---@return complete.kit.Async.AsyncTask
function CompletionItem:commit(option)
  option = option or {}
  option.replace = option.replace or false

  local bufnr = vim.api.nvim_get_current_buf()
  return Async.run(function()
    -- Try resolve item.
    Async.race({ self:resolve(), Async.timeout(200) }):await()

    local trigger_context --[[@as complete.core.TriggerContext]]

    -- Restore the the buffer content to the state it was in when the request was sent.
    trigger_context = TriggerContext.create()
    LinePatch.apply_by_func(
      bufnr,
      trigger_context.character - (self:get_offset() - 1),
      0,
      self._trigger_context.text:sub(self:get_offset(), self._trigger_context.character)
    ):await()

    -- Make overwrite information.
    local range = option.replace and self:get_replace_range() or self:get_insert_range()
    local before = self._trigger_context.character - range.start.character
    local after = range['end'].character - self._trigger_context.character

    -- Apply sync additionalTextEdits if provied.
    if self._item.additionalTextEdits then
      vim.lsp.util.apply_text_edits(kit.map(self._item.additionalTextEdits, function(text_edit)
        return {
          range = self:_convert_range_encoding(text_edit.range),
          newText = text_edit.newText,
        }
      end), bufnr, LSP.PositionEncodingKind.UTF8)
    end

    -- Expansion.
    if self:get_insert_text_format() == LSP.InsertTextFormat.Snippet and option.expand_snippet then
      -- remove range of text and expand snippet.
      LinePatch.apply_by_func(bufnr, before, after, ''):await()
      option.expand_snippet(self:get_insert_text(), {})
    else
      -- insert text.
      LinePatch.apply_by_func(bufnr, before, after, self:get_insert_text()):await()
    end

    -- Apply async additionalTextEdits if provided.
    if not self._item.additionalTextEdits then
      do
        local prev_trigger_context = TriggerContext.create()
        self:resolve():next(function()
          if self._item.additionalTextEdits then
            -- Check cursor is moved during resolve request proceeding.
            local next_trigger_context = TriggerContext.create()
            local should_skip = false
            should_skip = should_skip or (prev_trigger_context.line ~= next_trigger_context.line)
            should_skip = should_skip or #vim.iter(self._item.additionalTextEdits):filter(function(text_edit)
              return text_edit.range.start.line >= next_trigger_context.line
            end) > 0
            if not should_skip then
              vim.lsp.util.apply_text_edits(kit.map(self._item.additionalTextEdits, function(text_edit)
                return {
                  range = self:_convert_range_encoding(text_edit.range),
                  newText = text_edit.newText,
                }
              end), bufnr, LSP.PositionEncodingKind.UTF8)
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
    (self._completion_list.itemDefaults and self._completion_list.itemDefaults.editRange)
  )
end

---Return insert range.
---NOTE: The line property can't be used. This is usually 0.
---NOTE: This range is utf-8 byte length based.
---@return complete.kit.LSP.Range
function CompletionItem:get_insert_range()
  local range --[[@as complete.kit.LSP.Range]]
  if self._item.textEdit then
    if self._item.textEdit.insert then
      range = self._item.textEdit.insert
    else
      range = self._item.textEdit.range
    end
  elseif self._completion_list.itemDefaults and self._completion_list.itemDefaults.editRange then
    if self._completion_list.itemDefaults.editRange.insert then
      range = self._completion_list.itemDefaults.editRange.insert
    else
      range = self._completion_list.itemDefaults.editRange
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
---@return complete.kit.LSP.Range
function CompletionItem:get_replace_range()
  local range --[[@as complete.kit.LSP.Range]]
  if self._item.textEdit then
    if self._item.textEdit.replace then
      range = self._item.textEdit.replace
    end
  elseif self._completion_list.itemDefaults and self._completion_list.itemDefaults.editRange then
    if self._completion_list.itemDefaults.editRange.replace then
      range = self._completion_list.itemDefaults.editRange.replace
    end
  end
  if not range then
    range = self:_max_range(self._provider:get_default_replace_range(), self:get_insert_range())
  end
  return self:_convert_range_encoding(range)
end

---Convert range encoding to LSP.PositionEncodingKind.UTF8.
---@param range complete.kit.LSP.Range
---@return complete.kit.LSP.Range
function CompletionItem:_convert_range_encoding(range)
  local from_encoding = self._provider:get_position_encoding_kind()
  if from_encoding == LSP.PositionEncodingKind.UTF8 then
    return range
  end
  return {
    start = self._trigger_context.cache:ensure('CompletionItem:_convert_range_encoding:start:' .. range.start.character .. ':' .. from_encoding, function()
      return Position.to_utf8(self._trigger_context.text, range.start, from_encoding)
    end),
    ['end'] = self._trigger_context.cache:ensure('CompletionItem:_convert_range_encoding:end:' .. range['end'].character .. ':' .. from_encoding, function()
      return Position.to_utf8(self._trigger_context.text, range['end'], from_encoding)
    end),
  }
end

---Get expanded range.
---@param range_ complete.kit.LSP.Range
---@param ... complete.kit.LSP.Range
---@return complete.kit.LSP.Range
function CompletionItem:_max_range(range_, ...)
  local max --[[@as complete.kit.LSP.Range]]
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
