local Character = require('cmp-core.core.Character')

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
  local state = {
    alnum = false,
    pairs = {},
  } --[[@as { alnum: boolean, pairs: string[] }]]

  for i = 1, #insert_text do
    local byte = insert_text:byte(i)
    local alnum = Character.is_alnum(byte)

    if not state.alnum and SelectText.Pairs[byte] then
      table.insert(state.pairs, SelectText.Pairs[byte])
    end
    if state.alnum and not alnum and #state.pairs == 0 then
      if SelectText.StopCharacters[byte] then
        return insert_text:sub(1, i - 1)
      end
    else
      state.alnum = state.alnum or alnum
    end

    if byte == state.pairs[#state.pairs] then
      table.remove(state.pairs, #state.pairs)
    end
  end
  return insert_text
end

return SelectText
