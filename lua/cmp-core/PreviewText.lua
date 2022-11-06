local Character = require('cmp-core.Character')

local PreviewText = {}

PreviewText.Pairs = {
  [string.byte('(')] = string.byte(')'),
  [string.byte('[')] = string.byte(']'),
  [string.byte('{')] = string.byte('}'),
  [string.byte('"')] = string.byte('"'),
  [string.byte("'")] = string.byte("'"),
  [string.byte('<')] = string.byte('>'),
}

---Create preview text.
---@param _ cmp-core.Context
---@param insert_text string
---@return string
function PreviewText.create(_, insert_text)
  local state = {
    alnum = false,
    pairs = {}
  } --[[@as { alnum: boolean, pairs: string[] }]]
  for i = 1, #insert_text do
    local byte = insert_text:byte(i)
    local alnum = Character.is_alnum(byte)

    -- まだ単語類が見つかっていないかつ、単語類ではない
    if not state.alnum and not alnum then
      if PreviewText.Pairs[byte] then
        table.insert(state.pairs, string.char(byte))
      elseif PreviewText.Pairs[byte] == state.pairs[#state.pairs] then
        table.remove(state.pairs)
      end

    -- 単語類が既に見つかっているか、今回の単語が単語類である
    else
      if alnum then
        state.alnum = true
      elseif #state.pairs == 0 and state.alnum and not alnum then
        return insert_text:sub(1, i - 1)
      end
    end
  end
  return insert_text
end

return PreviewText

