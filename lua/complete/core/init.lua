---@class complete.core.MatchPosition { start_index: integer, end_index: integer, hl_group?: string }

---@class complete.core.Match
---@field provider complete.core.CompletionProvider
---@field item complete.core.CompletionItem
---@field score integer
---@field match_positions complete.core.MatchPosition[]

---@alias complete.core.Matcher fun(query: string, input: string): integer, complete.core.MatchPosition[]

