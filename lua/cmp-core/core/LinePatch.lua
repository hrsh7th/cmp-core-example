local Async = require('cmp-core.kit.Async')
local LSP = require('cmp-core.kit.LSP')
local Position = require('cmp-core.kit.LSP.Position')
local Keymap = require('cmp-core.kit.Vim.Keymap')

---@param position cmp-core.kit.LSP.Position
---@param delta integer
---@return cmp-core.kit.LSP.Position
local function shift_position(position, delta)
  local new_character = position.character + delta
  if new_character < 0 then
    if position.line == 0 then
      error('can not shift to the new position.')
    end
    local above_text = vim.api.nvim_buf_get_lines(0, position.line - 1, position.line, false)[1]
    return shift_position({
      line = position.line - 1,
      character = #above_text,
    }, new_character + 1)
  end
  local curr_text = vim.api.nvim_buf_get_lines(0, 0, -1, false)[position.line + 1] or ''
  if #curr_text < new_character then
    return shift_position({
      line = position.line + 1,
      character = 0,
    }, new_character - #curr_text - 1)
  end
  return {
    line = position.line,
    character = new_character,
  }
end

local LinePatch = {}

---Apply oneline text patch by func (without dot-repeat).
---@param before integer 0-origin utf8 byte count
---@param after integer 0-origin utf8 byte count
---@param insert_text string
function LinePatch.apply_by_func(before, after, insert_text)
  local mode = vim.api.nvim_get_mode().mode
  if mode == 'i' then
    local text_edit = {
      range = {
        start = shift_position(Position.cursor(LSP.PositionEncodingKind.UTF8), -before),
        ['end'] = shift_position(Position.cursor(LSP.PositionEncodingKind.UTF8), after),
      },
      newText = insert_text,
    }
    vim.lsp.util.apply_text_edits({ text_edit }, 0, LSP.PositionEncodingKind.UTF8)

    local insert_lines = vim.split(insert_text, '\n', { plain = true })
    if #insert_lines == 1 then
      vim.api.nvim_win_set_cursor(0, {
        (text_edit.range.start.line + 1),
        text_edit.range.start.character + #insert_lines[1],
      })
    else
      vim.api.nvim_win_set_cursor(0, {
        (text_edit.range.start.line + 1) + (#insert_lines - 1),
        #insert_lines[#insert_lines],
      })
    end
  elseif mode == 'c' then
    local cursor_col = vim.fn.getcmdpos() - 1
    local cmdline = vim.fn.getcmdline()
    local before_text = string.sub(cmdline, 1, cursor_col - before)
    local after_text = string.sub(cmdline, cursor_col + after + 1)
    vim.fn.setcmdline(before_text .. insert_text .. after_text, #before_text + #insert_text + 1)
  end
  return Async.resolve()
end

---Apply oneline text patch by keys (with dot-repeat).
---@param before integer 0-origin utf8 byte count
---@param after integer 0-origin utf8 byte count
---@param insert_text string
function LinePatch.apply_by_keys(before, after, insert_text)
  local mode = vim.api.nvim_get_mode().mode
  if mode == 'c' then
    return LinePatch.apply_by_func(before, after, insert_text)
  end

  local text = vim.api.nvim_get_current_line()
  local character = Position.cursor(LSP.PositionEncodingKind.UTF8).character
  local before_text = text:sub(1 + character - before, character)
  local after_text = text:sub(character + 1, character + after)

  return Keymap.send(
    table.concat({
      Keymap.termcodes('<Cmd>setlocal backspace=2<CR>'),
      Keymap.termcodes('<Cmd>setlocal textwidth=0<CR>'),
      Keymap.termcodes('<Cmd>setlocal lazyredraw<CR>'),
      Keymap.termcodes('<C-g>u<Left><Del>'):rep(vim.fn.strchars(before_text, true)),
      Keymap.termcodes('<Del>'):rep(vim.fn.strchars(after_text, true)),
      insert_text,
      Keymap.termcodes(('<Cmd>setlocal backspace=%s<CR>'):format(vim.go.backspace or 2)),
      Keymap.termcodes(('<Cmd>setlocal textwidth=%s<CR>'):format(vim.bo.textwidth or 0)),
      Keymap.termcodes(('<Cmd>setlocal %slazyredraw<CR>'):format(vim.o.lazyredraw and '' or 'no')),
    }, ''),
    'in'
  )
end

return LinePatch
