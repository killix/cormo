# basic

First, you should create a [[#Connection]] to the database.

```coffeescript
cormo = require 'cormo'
connection = new cormo.Connection 'mysql', database: 'test'
```

Available adapters are 'mysql', 'mongodb', 'postgresql', 'sqlite3', and 'sqlite3_memory'.
See documents for each adapter([[#AdapterBase]]) for detail settings.

Then, you can define [[#Model]]s using the extends keyword.

```coffeescript
# this will create two tables - users, posts - in the database.

class User extends cormo.Model
  @column 'name', type: String
  @column 'age', type: cormo.types.Integer

class Post extends cormo.Model
  @column 'title', String # `String` is the same as `type: String`
  @column 'body', 'string' # you can also use `string` to specify a string type
  @column 'date', Date
```

You can use any of cormo.types.String, 'string', or String
(native JavaScript Function, if exists) to specify a type.

Currently supported [[#types]]:

* [[#types.String]] ('string', String)
* [[#types.Number]] ('number', Number)
* [[#types.Boolean]] ('boolean', Boolean)
* [[#types.Integer]] ('integer')
* [[#types.Date]] ('date', Date)
* [[#types.GeoPoint]] ('geopoint')
    * MySQL, MonogoDB only
* [[#types.Object]] ('object', Object)
    * Objects are stored as a JSON string in SQL adapters.

After defining models, you may call [[#Connection::applySchemas]] to apply schemas to the database.
(It will be called automatically when you run a query.)

# when using JavaScript

If you want to use CORMO in JavaScript, use [[#Connection::model]] instead of the extends keyword.

```javascript
var cormo = require('cormo');
var connection = new cormo.Connection('mysql', { database: 'test' } );

var User = connection.model('User', {
  name: { type: String },
  age: { type: cormo.types.Integer }
});

var Post = connection.model('Post', {
  title: String,
  body: 'string',
  date: Date
});
```

# mixing databases

You can use two or more databases at the same time.

Use [[#Model.connection]] to specify the connection which the model uses

```coffeescript
cormo = require 'cormo'
mysql = new cormo.Connection 'mysql', database: 'test'
mongodb = new cormo.Connection 'mongodb', database: 'test'

class User extends cormo.Model
  @connection mysql
  @column 'name', String
  @column 'age', cormo.types.Integer

class Post extends cormo.Model
  @connection mongodb
  @column 'title', String
  @column 'body', String
  @column 'date', Date
```
