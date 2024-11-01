local Character = require('complete.core.Character')

local SelectText = {}

---@type table<integer, boolean>
SelectText.StopCharacters = {
  [string.byte("'")] = true,
  [string.byte('"')] = true,
  [string.byte('=')] = true,
  [string.byte('$')] = true,
  [string.byte('(')] = true,
  [string.byte(')')] = true,
  [string.byte('[')] = true,
  [string.byte(']')] = true,
  [string.byte('<')] = true,
  [string.byte('>')] = true,
  [string.byte('{')] = true,
  [string.byte('}')] = true,
  [string.byte(' ')] = true,
  [string.byte('\t')] = true,
  [string.byte('\n')] = true,
  [string.byte('\r')] = true,
}

---@type table<integer, integer>
SelectText.Pairs = {
  [string.byte('(')] = string.byte(')'),
  [string.byte('[')] = string.byte(']'),
  [string.byte('{')] = string.byte('}'),
  [string.byte('"')] = string.byte('"'),
  [string.byte("'")] = string.byte("'"),
  [string.byte('<')] = string.byte('>'),
}

---Create select text.
---@param insert_text string
---@return string
function SelectText.create(insert_text)
  insert_text = (insert_text:gsub('%s*$', ''):gsub('^%s*', ''))

  local is_alnum_consumed = false
  local pairs_stack = {}
  for i = 1, #insert_text do
    local byte = insert_text:byte(i)
    local alnum = Character.is_alnum(byte)

    if byte == pairs_stack[#pairs_stack] then
      table.remove(pairs_stack, #pairs_stack)
    else
      if not is_alnum_consumed and SelectText.Pairs[byte] then
        table.insert(pairs_stack, SelectText.Pairs[byte])
      end
      if is_alnum_consumed and not alnum and #pairs_stack == 0 then
        if SelectText.StopCharacters[byte] then
          return insert_text:sub(1, i - 1)
        end
      else
        is_alnum_consumed = is_alnum_consumed or alnum
      end
    end
  end
  return insert_text
end

return SelectText
