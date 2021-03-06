require './common'

_dbs =
  mysql:
    database: 'test'
  mongodb:
    database: 'test'
  sqlite3:
    database: __dirname + '/test.sqlite3'
  sqlite3_memory: {}
  postgresql:
    database: 'test'
  redis:
    database: 1

Object.keys(_dbs).forEach (db) ->
  describe 'basic-' + db, ->
    before (done) ->
      _g.connection = new _g.Connection db, _dbs[db]

      if Math.floor Math.random() * 2
        # using CoffeeScript extends keyword
        class User extends _g.Model
          @column 'name', String
          @column 'age', Number
      else
        # using Connection method
        User = _g.connection.model 'User',
          name: String
          age: Number

      _g.dropModels [User], done

    beforeEach (done) ->
      _g.deleteAllRecords [_g.connection.User], done

    after (done) ->
      _g.dropModels [_g.connection.User], done

    require('./cases/basic')()
