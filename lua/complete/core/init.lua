---@class complete.core.MatchPosition { start_index: integer, end_index: integer, hl_group?: string }

---@class complete.core.Match
---@field provider complete.core.CompletionProvider
---@field item complete.core.CompletionItem
---@field score integer
---@field match_positions complete.core.MatchPosition[]

---@alias complete.core.Matcher fun(query: string, input: string): integer, complete.core.MatchPosition[]
---@alias complete.core.Sorter fun(matches: complete.core.Match[]): complete.core.Match[]

---@class complete.core.CompletionSource.Configuration
---@field public keyword_pattern? string
---@field public position_encoding_kind? complete.kit.LSP.PositionEncodingKind
---@field public completion_options? complete.kit.LSP.CompletionRegistrationOptions

---@class complete.core.CompletionSource
---@field public initialize? fun(self: unknown, params: { configure: fun(configuration: complete.core.CompletionSource.Configuration) })
---@field public resolve? fun(self: unknown, item: complete.kit.LSP.CompletionItem): complete.kit.Async.AsyncTask
---@field public execute? fun(self: unknown, command: complete.kit.LSP.Command): complete.kit.Async.AsyncTask
---@field public complete fun(self: unknown, completion_context: complete.kit.LSP.CompletionContext): complete.kit.Async.AsyncTask
