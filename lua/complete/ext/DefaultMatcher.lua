local Character = require('complete.core.Character')

local DefaultMatcher = {}

local BOUNDALY_ORDER_FACTOR = 10
local PREFIX_FACTOR = 8
local NOT_FUZZY_FACTOR = 6

---convert_matches
---@param matches complete.ext.DefaultMatcher.MatchData[]
---@return complete.core.MatchPosition[]
local function convert_matches(matches)
  for _, match in ipairs(matches) do
    ---@diagnostic disable-next-line: inject-field
    match.start_index = match.label_match_start
    ---@diagnostic disable-next-line: inject-field
    match.end_index = match.label_match_end
    match.index = nil
    match.query_match_start = nil
    match.query_match_end = nil
    match.label_match_start = nil
    match.label_match_end = nil
    match.strict_ratio = nil
    match.fuzzy = nil
  end
  return matches
end

---@class complete.ext.DefaultMatcher.MatchData
---@field index? integer
---@field query_match_start integer
---@field query_match_end integer
---@field label_match_start integer
---@field label_match_end integer
---@field strict_ratio integer
---@field fuzzy boolean

---fuzzy
---@param query string
---@param label string
---@param matches complete.ext.DefaultMatcher.MatchData[]
---@return complete.ext.DefaultMatcher.MatchData[] | nil
local function fuzzy(query, label, matches)
  local query_index = matches[#matches] and (matches[#matches].query_match_end + 1) or 1

  -- lately specified middle of text.
  for i = 1, #matches - 1 do
    local curr_match = matches[i]
    local next_match = matches[i + 1]
    local label_offset = 0
    local label_index = Character.get_next_semantic_index(label, curr_match.label_match_end)
    while label_offset + label_index < next_match.label_match_start and query_index <= #query do
      if Character.match_ignorecase(string.byte(label, label_index + label_offset), string.byte(query, query_index)) then
        query_index = query_index + 1
        label_offset = label_offset + 1
      else
        label_index = Character.get_next_semantic_index(label, label_index + label_offset)
        label_offset = 0
      end
    end
  end

  local matched = false
  local label_offset = 0
  local label_index = matches[#matches] and (matches[#matches].label_match_end + 1) or 1
  local query_match_start = -1
  local query_match_end = -1
  local label_match_start = -1
  local strict_count = 0
  local match_count = 0
  while label_offset + label_index <= #label and query_index <= #query do
    local c1, c2 = string.byte(label, label_index + label_offset), string.byte(query, query_index)
    if Character.match_ignorecase(c1, c2) then
      if not matched then
        query_match_start = query_index
        label_match_start = label_index + label_offset
      end
      matched = true
      query_index = query_index + 1
      strict_count = strict_count + (c1 == c2 and 1 or 0)
      match_count = match_count + 1
    else
      if matched then
        matches[#matches + 1] = {
          query_match_start = query_match_start,
          query_match_end = query_index - 1,
          label_match_start = label_match_start,
          label_match_end = label_index + label_offset - 1,
          strict_ratio = strict_count / match_count,
          fuzzy = true,
        }
      end
      matched = false
    end
    label_offset = label_offset + 1
  end

  if matched and query_index > #query then
    matches[#matches + 1] = {
      query_match_start = query_match_start,
      query_match_end = query_match_end,
      label_match_start = label_match_start,
      label_match_end = label_index + label_offset - 1,
      strict_ratio = strict_count / match_count,
      fuzzy = true,
    }
    return matches
  end
  return nil
end

---find_match_region
---@param query string
---@param query_start_index integer
---@param query_end_index integer
---@param label string
---@param label_index integer
---@return complete.ext.DefaultMatcher.MatchData | nil
local function find_match_region(query, query_start_index, query_end_index, label, label_index)
  -- determine query position ( woroff -> label_offset )
  while query_start_index < query_end_index do
    if Character.match_ignorecase(string.byte(query, query_end_index), string.byte(label, label_index)) then
      break
    end
    query_end_index = query_end_index - 1
  end

  -- can't determine query position
  if query_end_index < query_start_index then
    return nil
  end

  local query_match_start = -1
  local query_index = query_end_index
  local label_offset = 0
  local strict_count = 0
  local match_count = 0
  while query_index <= #query and label_index + label_offset <= #label do
    local c1 = string.byte(query, query_index)
    local c2 = string.byte(label, label_index + label_offset)
    if Character.match_ignorecase(c1, c2) then
      -- start.
      if query_match_start == -1 then
        query_match_start = query_index
      end

      strict_count = strict_count + (c1 == c2 and 1 or 0)
      match_count = match_count + 1
      label_offset = label_offset + 1
    else
      -- end (partial region)
      if query_match_start ~= -1 then
        return {
          query_match_start = query_match_start,
          query_match_end = query_index - 1,
          label_match_start = label_index,
          label_match_end = label_index + label_offset - 1,
          strict_ratio = strict_count / match_count,
          fuzzy = false,
        }
      else
        return nil
      end
    end
    query_index = query_index + 1
  end

  -- end (last region)
  if query_match_start ~= -1 then
    return {
      query_match_start = query_match_start,
      query_match_end = query_index - 1,
      label_match_start = label_index,
      label_match_end = label_index + label_offset - 1,
      strict_ratio = strict_count / match_count,
      fuzzy = false,
    }
  end

  return nil
end

---Match via pure lua code.
---@param query string
---@param label string
---@return integer, complete.core.MatchPosition[]
function DefaultMatcher.matcher(query, label)
  -- empty input
  if #query == 0 then
    return PREFIX_FACTOR + NOT_FUZZY_FACTOR, {}
  end

  -- query is too long.
  if #query > #label then
    return 0, {}
  end

  -- gather matched regions
  local matches = {}
  local query_start_index = 1
  local query_end_index = 1
  local label_index = 1
  local label_bound_index = 1
  while query_end_index <= #query and label_index <= #label do
    local match = find_match_region(query, query_start_index, query_end_index, label, label_index)
    if match and query_end_index <= match.query_match_end then
      match.index = label_bound_index
      query_start_index = match.query_match_start + 1
      query_end_index = match.query_match_end + 1
      label_index = Character.get_next_semantic_index(label, match.label_match_end)
      matches[#matches + 1] = match
    else
      label_index = Character.get_next_semantic_index(label, label_index)
    end
    label_bound_index = label_bound_index + 1
  end

  -- full fuzzy matching.
  if #matches == 0 then
    if fuzzy(query, label, matches) then
      return 1, convert_matches(matches)
    end
    return 0, {}
  end

  -- check prefix match
  local prefix = false
  if matches[1].query_match_start == 1 and matches[1].label_match_start == 1 then
    prefix = true
  end

  -- compute match score
  local score = prefix and PREFIX_FACTOR or 0
  local offset = prefix and matches[1].index - 1 or 0
  local idx = 1
  for _, match in ipairs(matches) do
    local s = 0
    for i = math.max(idx, match.query_match_start), match.query_match_end do
      s = s + 1
      idx = i
    end
    idx = idx + 1
    if s > 0 then
      s = s * (1 + match.strict_ratio)
      s = s * (1 + math.max(0, BOUNDALY_ORDER_FACTOR - (match.index - offset)) / BOUNDALY_ORDER_FACTOR)
      score = score + s
    end
  end

  -- remaining fuzzy matching.
  if matches[#matches].query_match_end < #query then
    if fuzzy(query, label, matches) then
      return score, convert_matches(matches)
    end
    return 0, {}
  end

  return score + NOT_FUZZY_FACTOR, convert_matches(matches)
end

return DefaultMatcher
