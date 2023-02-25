local Character = require('cmp-core.core.Character')

---@class cmp-core.Matcher.Match
---@field public kind cmp-core.Matcher.MatchKind
---@field public query_index_s integer
---@field public query_index_e integer
---@field public text_index_s integer
---@field public text_index_e integer
---@field public strict_count integer

---@class cmp-core.Matcher.State
---@field public query string
---@field public matches cmp-core.Matcher.Match[]

---@param text string
---@param index integer
local function get_next_semantic_index(text, index)
  for i = index + 1, #text do
    local prev, curr = text:byte(i - 1, i)
    if Character.is_symbol(curr) or Character.is_white(curr) then
      return i
    end
    if not Character.is_alpha(prev) and Character.is_alpha(curr) then
      return i
    end
    if not Character.is_upper(prev) and Character.is_upper(curr) then
      return i
    end
    if not Character.is_digit(prev) and Character.is_digit(curr) then
      return i
    end
  end
  return #text + 1
end

---@class cmp-core.Matcher
---@field public text_cache table<string, cmp-core.Matcher.State>
local Matcher = {}
Matcher.__index = Matcher

---@enum cmp-core.Matcher.MatchKind
Matcher.MatchKind = {
  Prefix = 'prefix',
  Boundaly = 'boundaly',
  Fuzzy = 'fuzzy',
  Pending = 'pending',
}

---@return cmp-core.Matcher
function Matcher.new()
  local self = setmetatable({}, Matcher)
  self.text_cache = {}
  return self
end

---@param query string
---@param text string
---@return number, cmp-core.Matcher.Match[]
function Matcher:match(query, text)
  if not self.text_cache[text] then
    self.text_cache[text] = {
      query = '',
      matches = {
        {
          kind = Matcher.MatchKind.Pending,
          query_index_s = 1,
          query_index_e = 1,
          text_index_s = 1,
          text_index_e = 1,
          strict_count = 0,
        }
      }
    }
  end

  -- Continue matching if possible.
  local state = self.text_cache[text]
  local found = false
  for i = #query, 1, -1 do
    if state.query == query:sub(1, i) then
      found = true
      break
    end
  end
  if not found then
    state.matches = {
      {
        kind = Matcher.MatchKind.Pending,
        query_index_s = 1,
        query_index_e = 1,
        text_index_s = 1,
        text_index_e = 1,
        strict_count = 0,
      }
    }
  end
  state.query = query

  local current = state.matches[#state.matches]
  while current.query_index_e <= #query and current.text_index_e <= #text do
    local query_byte = query:byte(current.query_index_e)
    local text_byte = text:byte(current.text_index_e)
    if Character.match(query_byte, text_byte) then
      -- Update `*_index_s` on first match.
      if current.kind == Matcher.MatchKind.Pending then
        current.kind = current.query_index_e == 1 and Matcher.MatchKind.Prefix or Matcher.MatchKind.Boundaly
        current.query_index_s = current.query_index_e
        current.text_index_s = current.text_index_e
      end
      -- Update `*index_e` on every match.
      current.query_index_e = current.query_index_e + 1
      current.text_index_e = current.text_index_e + 1
      current.strict_count = current.strict_count + (query_byte == text_byte and 1 or 0)
    else
      if current.kind ~= Matcher.MatchKind.Pending then
        current.query_index_e = current.query_index_e - 1
        current.text_index_e = current.text_index_e - 1
      end

      -- Search next match index (limited backtrack).
      local next_query_index = current.query_index_e + 1
      local next_text_index = get_next_semantic_index(text, current.text_index_e)
      while next_text_index <= #text do
        local next_text_byte = text:byte(next_text_index)
        while current.query_index_s < next_query_index do
          if Character.match(query:byte(next_query_index), next_text_byte) then
            break
          end
          next_query_index = next_query_index - 1
        end
        if current.query_index_s ~= next_query_index then
          break
        end
        next_query_index = current.query_index_e + 1
        next_text_index = get_next_semantic_index(text, next_text_index)
      end

      -- Break matching.
      if next_text_index > #text then
        break
      end

      -- Prepare next match.
      current = {
        kind = Matcher.MatchKind.Pending,
        query_index_s = next_query_index,
        query_index_e = next_query_index,
        text_index_s = next_text_index,
        text_index_e = next_text_index,
        strict_count = 0,
      }
      state.matches[#state.matches + 1] = current
    end
  end

  -- No match if the query remains.
  if current.query_index_e < #query then
    return 0, {}
  end

  -- Fixup last match data.
  current.kind = current.query_index_s == 1 and Matcher.MatchKind.Prefix or Matcher.MatchKind.Boundaly
  current.query_index_e = current.query_index_e - 1
  current.text_index_e = current.text_index_e - 1

  -- Calculate scores.
  local score = 0
  for i = 1, #state.matches do
    local match = state.matches[i]
    if match.kind == Matcher.MatchKind.Prefix then
      score = score + 100
    end
    score = score + (match.query_index_e - match.query_index_s + 1) + (match.strict_count * 0.01)
  end
  return score, state.matches
end

return Matcher
