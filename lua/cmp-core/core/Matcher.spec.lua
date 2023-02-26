local Matcher = require('cmp-core.core.Matcher')

local function bench(name, func, count)
  count = count or 2000000

  collectgarbage('collect')
  local s = os.clock()
  for _ = 1, count do
    func()
  end
  local e = os.clock()

  print(('[%s] time taken: %sms, %skb memory usage.'):format(
    name,
    (e - s) * 1000,
    collectgarbage('count')
  ))
end

describe('cmp-core.core', function()
  describe('Matcher', function()
    it('should performant', function()
      local matcher = Matcher.new()
      bench('matcher:match incremental', function()
        matcher:match('f', 'foo_bar_baz')
        matcher:match('fo', 'foo_bar_baz')
        matcher:match('foo', 'foo_bar_baz')
        matcher:match('fooaaz', 'foo_bar_baz')
      end)
    end)

    it('should match words incrementaly', function()
      local matcher = Matcher.new()

      -- incremental match.
      local score1, matches1 = matcher:match('f', 'foo_bar_baz')
      local score2, matches2 = matcher:match('fb', 'foo_bar_baz')
      assert.is_truthy(score1 > 0)
      assert.is_truthy(score2 > 0)
      assert.is_truthy(score2 > score1)
      assert.equals(matches1, matches2)

      -- reset incremental state.
      local score3, matches3 = matcher:match('f', 'foo_bar_baz')
      assert.is_truthy(score2 > 0)
      assert.is_truthy(score3 > 0)
      assert.is_truthy(score2 > score3)
      assert.are_not.equals(matches2, matches3)
    end)

    it('should match various words', function()
      local matcher, score, matches = Matcher.new()

      assert.equals(matcher:match('f*', 'foo'), 0)
      assert.equals(matcher:match('fo*', 'foo'), 0)
      assert.equals(matcher:match('foo*', 'foo'), 0)

      score, matches = matcher:match('foo', 'foo')
      assert.is_truthy(score > 0)
      assert.are.same({
        {
          kind = Matcher.MatchKind.Prefix,
          query_index_s = 1,
          query_index_e = 3,
          text_index_s = 1,
          text_index_e = 3,
        }
      }, matches)

      score, matches = matcher:match('ab', 'a_b_b')
      assert.is_truthy(score > 0)
      assert.are.same({
        {
          kind = Matcher.MatchKind.Prefix,
          query_index_s = 1,
          query_index_e = 1,
          text_index_s = 1,
          text_index_e = 1,
        }, {
        kind = Matcher.MatchKind.Boundaly,
        query_index_s = 2,
        query_index_e = 2,
        text_index_s = 3,
        text_index_e = 3,
      }
      }, matches)

      score, matches = matcher:match('ac', 'a_b_c')
      assert.is_truthy(score > 0)
      assert.are.same({
        {
          kind = Matcher.MatchKind.Prefix,
          query_index_s = 1,
          query_index_e = 1,
          text_index_s = 1,
          text_index_e = 1,
        }, {
        kind = Matcher.MatchKind.Boundaly,
        query_index_s = 2,
        query_index_e = 2,
        text_index_s = 5,
        text_index_e = 5,
      }
      }, matches)

      score, matches = matcher:match('bora', 'border-radius')
      assert.is_truthy(score > 0)
      assert.are.same({
        {
          kind = Matcher.MatchKind.Prefix,
          query_index_s = 1,
          query_index_e = 3,
          text_index_s = 1,
          text_index_e = 3,
        }, {
        kind = Matcher.MatchKind.Boundaly,
        query_index_s = 3,
        query_index_e = 4,
        text_index_s = 8,
        text_index_e = 9,
      }
      }, matches)
    end)
  end)
end)
