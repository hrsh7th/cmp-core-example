local SnippetText = require('complete.core.SnippetText')

describe('complete.core', function()
  describe('SnippetText', function()
    describe('.parse', function()
      it('should return snippet text', function()
        assert.equals('a b c', tostring(SnippetText.parse('a ${1:b} c')))
      end)
    end)
  end)
end)

