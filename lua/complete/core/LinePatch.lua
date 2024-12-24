local LSP = require('complete.kit.LSP')
local Async = require('complete.kit.Async')
local Keymap = require('complete.kit.Vim.Keymap')
local Position = require('complete.kit.LSP.Position')

---Move position by delta with consider buffer text and line changes.
---@param bufnr integer
---@param position complete.kit.LSP.Position
---@param delta integer
---@return complete.kit.LSP.Position
local function shift_position(bufnr, position, delta)
  local new_character = position.character + delta
  if new_character < 0 then
    if position.line == 0 then
      error('can not shift to the new position.')
    end
    local above_line = vim.api.nvim_buf_get_lines(bufnr, position.line - 1, position.line, false)[1]
    return shift_position(bufnr, {
      line = position.line - 1,
      character = #above_line,
    }, new_character + 1)
  end
  local curr_line = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)[position.line + 1] or ''
  if #curr_line < new_character then
    return shift_position(bufnr, {
      line = position.line + 1,
      character = 0,
    }, new_character - #curr_line - 1)
  end
  return {
    line = position.line,
    character = new_character,
  }
end

local LinePatch = {}

---Apply oneline text patch by func (without dot-repeat).
---@param bufnr integer
---@param before integer 0-origin utf8 byte count
---@param after integer 0-origin utf8 byte count
---@param insert_text string
function LinePatch.apply_by_func(bufnr, before, after, insert_text)
  local mode = vim.api.nvim_get_mode().mode --[[@as string]]
  if mode == 'c' then
    local cursor_col = vim.fn.getcmdpos() - 1
    local cmdline = vim.fn.getcmdline()
    local before_text = string.sub(cmdline, 1, cursor_col - before)
    local after_text = string.sub(cmdline, cursor_col + after + 1)
    vim.fn.setcmdline(before_text .. insert_text .. after_text, #before_text + #insert_text + 1)
  else
    local text_edit = {
      range = {
        start = shift_position(bufnr, Position.cursor(LSP.PositionEncodingKind.UTF8), -before),
        ['end'] = shift_position(bufnr, Position.cursor(LSP.PositionEncodingKind.UTF8), after),
      },
      newText = insert_text,
    }
    vim.lsp.util.apply_text_edits({ text_edit }, bufnr, LSP.PositionEncodingKind.UTF8)

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
  end
  return Async.resolve()
end

---Apply oneline text patch by keys (with dot-repeat).
---@param bufnr integer
---@param before integer 0-origin utf8 byte count
---@param after integer 0-origin utf8 byte count
---@param insert_text string
function LinePatch.apply_by_keys(bufnr, before, after, insert_text)
  local mode = vim.api.nvim_get_mode().mode
  if mode == 'c' then
    return LinePatch.apply_by_func(bufnr, before, after, insert_text)
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = vim.api.nvim_buf_get_lines(bufnr, cursor[1] - 1, cursor[1], false)[1]
  local character = Position.cursor(LSP.PositionEncodingKind.UTF8).character
  local before_text = line:sub(1 + character - before, character)
  local after_text = line:sub(character + 1, character + after)

  return Keymap.send({
    Keymap.termcodes('<Cmd>setlocal backspace=2<CR>'),
    Keymap.termcodes('<Cmd>setlocal textwidth=0<CR>'),
    Keymap.termcodes('<Cmd>setlocal lazyredraw<CR>'),
    Keymap.termcodes('<C-g>U<Left><Del>'):rep(vim.fn.strchars(before_text, true)),
    Keymap.termcodes('<Del>'):rep(vim.fn.strchars(after_text, true)),
    insert_text,
    Keymap.termcodes(('<Cmd>setlocal backspace=%s<CR>'):format(vim.go.backspace or 2)),
    Keymap.termcodes(('<Cmd>setlocal textwidth=%s<CR>'):format(vim.bo.textwidth or 0)),
    Keymap.termcodes(('<Cmd>setlocal %slazyredraw<CR>'):format(vim.o.lazyredraw and '' or 'no')),
  })
end

return LinePatch
