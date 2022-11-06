local spec = require("cmp-core.spec")
local PreviewText = require('cmp-core.PreviewText')

describe('cmp-core', function ()
  describe('PreviewText', function ()
    describe('.create', function()
      it('should return preview text', function()
        local context = spec.setup {
          text = {
            '(|)'
          }
        }
        assert.equals('#[test]', PreviewText.create(context, '#[test]'))
        assert.equals('#[[test]]', PreviewText.create(context, '#[[test]]'))
        assert.equals('insert', PreviewText.create(context, 'insert()'))
      end)
    end)
  end)
end)

