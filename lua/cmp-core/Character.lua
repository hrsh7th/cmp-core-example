local Character = {}

---@type table<number, string> Digit characters.
Character.Digit  = {}
do
  ('1234567890'):gsub('.', function(c)
    Character.Digit[string.byte(c)] = c
  end)
end

---@type table<number, string> Alphabet characters.
Character.Alpha = {}
do
  ('abcdefghijklmnopqrstuvwxyz'):gsub('.', function(c)
    Character.Alpha[string.byte(c)] = c
  end)
end

---@type table<number, string> White space characters.
Character.White = {}
do
  (' \t\n'):gsub('.', function(c)
    Character.White[string.byte(c)] = c
  end)
end

---Return true if the character is digit.
---@param byte any
---@return boolean
function Character.is_digit(byte)
  return Character.Digit[byte] ~= nil
end

---Return true if the character is alpha.
---@param byte number
---@return boolean
function Character.is_alpha(byte)
  return Character.Alpha[byte] ~= nil or Character.Alpha[byte - 32] ~= nil
end

---Return true if the character is alpha or digit.
function Character.is_alnum(byte)
  return Character.is_alpha(byte) or Character.is_digit(byte)
end

---Return true if the character is lower.
---@param byte number
---@return boolean
function Character.is_lower(byte)
  return Character.Alpha[byte] ~= nil
end

---Return true if the character is upper.
---@param byte number
---@return boolean
function Character.is_upper(byte)
  return Character.Alpha[byte - 32] ~= nil
end

---Return true if the character is white space.
---@param byte number
---@return boolean
function Character.is_white(byte)
  return Character.White[byte] ~= nil
end

---Return true if the character is symbol.
---@param byte number
---@return boolean
function Character.is_symbol(byte)
  return not Character.is_digit(byte) and not Character.is_alpha(byte) and not Character.is_white(byte)
end

return Character

