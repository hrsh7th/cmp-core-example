local Character = require('cmp-core.core.Character')

---@class cmp-core.Matcher.Match
---@field public kind cmp-core.Matcher.MatchKind
---@field public query_index_s integer
---@field public query_index_e integer
---@field public text_index_s integer
---@field public text_index_e integer

---@class cmp-core.Matcher.State
---@field public query string
---@field public score integer
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
  Prefix = 'Prefix',
  Boundaly = 'Boundaly',
  Fuzzy = 'Fuzzy',
  Pending = 'Pending',
}

---@type table<cmp-core.Matcher.MatchKind, integer>
Matcher.MatchBonus = {
  [Matcher.MatchKind.Prefix] = 25,
  [Matcher.MatchKind.Boundaly] = 5,
  [Matcher.MatchKind.Fuzzy] = 0,
  [Matcher.MatchKind.Pending] = 0,
}

---@return cmp-core.Matcher
function Matcher.new()
  local self = setmetatable({}, Matcher)
  self.text_cache = {}
  return self
end

---@param query string
---@param text string
---@return integer, cmp-core.Matcher.Match[]
function Matcher:match(query, text)
  if #query > #text then
    return 0, {}
  end

  local state = self.text_cache[text]
  if not state then
    state = {
      score = 0,
      query = query,
      matches = {
        {
          kind = Matcher.MatchKind.Pending,
          query_index_s = 0,
          query_index_e = 0,
          text_index_s = 0,
          text_index_e = 0,
        }
      }
    }
    self.text_cache[text] = state
  else
    if query:sub(1, #state.query) ~= state.query then
      state.score = 0
      state.matches = {
        {
          kind = Matcher.MatchKind.Pending,
          query_index_s = 0,
          query_index_e = 0,
          text_index_s = 0,
          text_index_e = 0,
        }
      }
    end
    state.query = query
  end

  local current = state.matches[#state.matches]
  current.query_index_e = current.query_index_e + 1
  current.text_index_e = current.text_index_e + 1
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
      state.score = state.score + 1 + (query_byte == text_byte and 0.01 or 0) + Matcher.MatchBonus[current.kind]
    else
      if current.kind ~= Matcher.MatchKind.Pending then
        current.query_index_e = current.query_index_e - 1
        current.text_index_e = current.text_index_e - 1
      end

      -- Search next match index (limited backtrack).
      local is_strict_match = false
      local next_query_index = current.query_index_e + 1
      local next_text_index = get_next_semantic_index(text, current.text_index_e)
      while next_text_index <= #text do
        local next_text_byte = text:byte(next_text_index)
        while current.query_index_s < next_query_index do
          if Character.match(query:byte(next_query_index), next_text_byte) then
            is_strict_match = query:byte(next_query_index) == next_text_byte
            break
          end
          next_query_index = next_query_index - 1
        end
        if current.query_index_s < next_query_index then
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
        kind = Matcher.MatchKind.Boundaly,
        query_index_s = next_query_index,
        query_index_e = next_query_index + 1,
        text_index_s = next_text_index,
        text_index_e = next_text_index + 1,
      }
      state.matches[#state.matches + 1] = current
      state.score = state.score + 1 + (is_strict_match and 0.01 or 0) + Matcher.MatchBonus[current.kind]
    end
  end

  -- No match if the query remains.
  if current.query_index_e > #query then
    current.query_index_e = current.query_index_e - 1
    current.text_index_e = current.text_index_e - 1
  else
    -- TODO: fuzzy matching
    return 0, {}
  end

  return state.score, state.matches
end

return Matcher
