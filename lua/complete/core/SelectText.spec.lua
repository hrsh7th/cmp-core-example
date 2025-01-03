local SelectText = require('complete.core.SelectText')

describe('complete.core', function()
  describe('SelectText', function()
    describe('.create', function()
      it('should return select text', function()
        assert.equals('#[test]', SelectText.create('#[test]'))
        assert.equals('#[[test]]', SelectText.create('#[[test]]'))
        assert.equals('insert', SelectText.create('insert()'))
        assert.equals('insert_text', SelectText.create('insert_text'))
        assert.equals('(insert)', SelectText.create('(insert))'))
        assert.equals('"true"', SelectText.create('"true"'))
      end)
    end)
  end)
end)
