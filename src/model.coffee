inflector = require './inflector'
async = require 'async'
Query = require './query'

##
# Base class for models
class Model
  ##
  # Returns a new model class extending Model
  # @param {Connection} connection
  # @param {String} name
  # @param {Object} schema
  # @return {Class<Model>}
  @newModel: (connection, name, schema) ->
    class NewModel extends Model
    NewModel.connection connection, name
    for name, property of schema
      NewModel.column name, property
    return NewModel

  ##
  # Sets a connection of this model
  # @param {Connection} connection
  # @param {String} [name]
  @connection: (connection, name) ->
    name = @name if not name
    connection.models[name] = @

    Object.defineProperty @, '_connection', value: connection
    Object.defineProperty @, '_adapter', value: connection._adapter
    Object.defineProperty @, '_associations', value: {}
    Object.defineProperty @, '_validators', value: []
    Object.defineProperty @, '_name', configurable: true, value: name
    Object.defineProperty @, '_schema', configurable: true, value: {}

  ##
  # Adds a column to this model
  # @param {String} name
  # @param {String|Object} property
  @column: (name, property) ->
    # convert simple type to object
    if typeof property is 'function' or typeof property is 'string'
      property = type: property

    # convert javascript built-in class
    type = property.type
    switch type
      when String then type = Model.String
      when Number then type = Model.Number
      when Boolean then type = Model.Boolean
      when Date then type = Model.Date
    if typeof type isnt 'string'
      throw new Error 'unknown type : ' + type
    property.type = type.toLowerCase()

    # check supports of GeoPoint
    if type is Model.GeoPoint and not @_adapter.support_geopoint
      throw new Error 'this adapter does not support GeoPoint'

    @_schema[name] = property

  @_waitingForConnection: (object, method, args) ->
    return true if @_connection._waitingForApplyingSchemas object, method, args
    return @_connection._waitingForConnection object, method, args

  ##
  # Creates a record
  # @param {Object} [data={}]
  constructor: (data) ->
    data = data or {}
    id = arguments[1]
    schema = @constructor._schema
    Object.keys(schema).forEach (column) =>
      if data[column]?
        @[column] = data[column]

    Object.defineProperty @, 'id', configurable: not id?, enumerable: true, writable: false, value: id

    if id?
      @_runCallbacks 'find', 'after'
    @_runCallbacks 'initialize', 'after'

  ##
  # Creates a record.
  # 'Model.build(data)' is the same as 'new Model(data)'
  # @param {Object} [data={}]
  # @return {Model}
  @build: (data) ->
    return new @ data

  ##
  # Creates a record and saves it to the database
  # 'Model.create(data, callback)' is the same as 'Model.build(data).save(callback)'
  # @param {Object} [data={}]
  # @param {Function} callback
  # @param {Error} callback.error
  # @param {Model} callback.record created record
  @create: (data, callback) ->
    if typeof data is 'function'
      callback = data
      data = {}
    @build(data).save callback

  ##
  # Validates data
  # @param {Function} [callback]
  # @param {Error} callback.error
  # @return {Boolean}
  validate: (callback) ->
    @_runCallbacks 'validate', 'before'

    errors = []

    schema = @constructor._schema
    Object.keys(schema).forEach (column) =>
      property = schema[column]
      if @[column]?
        switch property.type
          when Model.Number
            value = Number @[column]
            if isNaN value
              errors.push "'#{column}' is not a number"
            else
              @[column] = value
          when Model.Boolean
            if typeof @[column] isnt 'boolean'
              errors.push "'#{column}' is not a boolean"
          when Model.Integer
            value = Number @[column]
            # value>>0 checkes integer and 32bit
            if isNaN(value) or (value>>0) isnt value
              errors.push "'#{column}' is not an integer"
            else
              @[column] = value
          when Model.GeoPoint
            value = @[column]
            if not ( Array.isArray(value) and value.length is 2 )
              errors.push "'#{column}' is not a geo point"
            else
              value[0] = Number value[0]
              value[1] = Number value[1]
          when Model.Date
            value = @[column]
            value = new Date value
            if isNaN value.getTime()
              errors.push "'#{column}' is not a date"
            else
              @[column] = value
      else
        if property.required
          errors.push "'#{column}' is required"

    @constructor._validators.forEach (validator) =>
      try
        r = validator @
        if r is false
          errors.push 'validation failed'
        else if typeof r is 'string'
          errors.push r
      catch e
        errors.push e.message
    if errors.length > 0
      @_runCallbacks 'validate', 'after'
      callback? new Error errors.join ','
      return false
    else
      @_runCallbacks 'validate', 'after'
      callback? null
      return true

  _buildSaveData: ->
    data = {}
    schema = @constructor._schema
    Object.keys(schema).forEach (column) =>
      if @[column]?
        data[column] = @[column]
      else
        data[column] = null
    return data

  _create: (callback) ->
    return if @constructor._waitingForConnection @, @_create, arguments

    ctor = @constructor
    data = @_buildSaveData()
    if Object.keys(data).length is 0
      return callback new Error 'empty data', @

    ctor._adapter.create ctor._name, data, (error, id) =>
      return callback error, @ if error
      Object.defineProperty @, 'id', configurable: false, enumerable: true, writable: false, value: id
      # save sub objects of each association
      foreign_key = inflector.foreign_key ctor._name
      async.forEach Object.keys(ctor._associations), (column, callback) =>
          async.forEach @['__cache_' + column] or [], (sub, callback) ->
              sub[foreign_key] = id
              sub.save (error) ->
                callback error
            , (error) ->
              callback error
        , (error) =>
          callback null, @

  _update: (callback) ->
    return if @constructor._waitingForConnection @, @_update, arguments

    ctor = @constructor
    data = @_buildSaveData()
    data.id = @id

    ctor._adapter.update ctor._name, data, (error) =>
      return callback error, @ if error
      callback null, @

  ##
  # Saves data to the database
  # @param {Object} [options]
  # @param {Boolean} [options.validate=true]
  # @param {Function} [callback]
  # @param {Error} callback.error
  # @param {Model} callback.record this
  save: (options, callback) ->
    if typeof options is 'function'
      callback = options
      options = {}
    callback = (->) if typeof callback isnt 'function'

    if options?.validate isnt false
      @validate (error) =>
        return callback error if error
        @save validate: false, callback
      return

    @_runCallbacks 'save', 'before'

    if @id
      @_runCallbacks 'update', 'before'
      @_update (error, record) =>
        @_runCallbacks 'update', 'after'
        @_runCallbacks 'save', 'after'
        callback error, record
    else
      @_runCallbacks 'create', 'before'
      @_create (error, record) =>
        @_runCallbacks 'create', 'after'
        @_runCallbacks 'save', 'after'
        callback error, record

  ##
  # Destroys this record (remove from the database)
  # @param {Function} callback
  # @param {Error} callback.error
  destroy: (callback) ->
    callback = (->) if typeof callback isnt 'function'
    @_runCallbacks 'destroy', 'before'
    if @id
      @constructor.delete { id: @id }, (error, count) =>
        @_runCallbacks 'destroy', 'after'
        callback error
    else
      @_runCallbacks 'destroy', 'after'
      callback null
    return

  ##
  # Finds a record by id
  # @param {RecordID|Array<RecordID>} id
  # @param {Function} [callback]
  # @param {Error} callback.error
  # @param {Model|Array<Model>} callback.record
  # @return {Query}
  # @throws Error('not found')
  @find: (id, callback) ->
    return if @_waitingForConnection @, @find, arguments

    query = new Query @
    query.find id
    if typeof callback is 'function'
      query.exec callback
    return query

  ##
  # Finds records by conditions
  # @param {Object} [condition]
  # @param {Function} [callback]
  # @param {Error} callback.error
  # @param {Array<Model>} callback.records
  # @return {Query}
  @where: (condition, callback) ->
    return if @_waitingForConnection @, @where, arguments

    if typeof condition is 'function'
      callback = condition
      condition = null
    query = new Query @
    query.where condition
    if typeof callback is 'function'
      query.exec callback
    return query

  ##
  # Selects columns for result
  # @param {Object} [columns]
  # @param {Function} [callback]
  # @param {Error} callback.error
  # @param {Array<Model>} callback.records
  # @return {Query}
  @select: (columns, callback) ->
    return if @_waitingForConnection @, @select, arguments

    if typeof columns is 'function'
      callback = columns
      columns = null
    query = new Query @
    query.select columns
    if typeof callback is 'function'
      query.exec callback
    return query

  ##
  # Counts records by conditions
  # @param {Object} [condition]
  # @param {Function} [callback]
  # @param {Error} callback.error
  # @param {Number} callback.count
  # @return {Query}
  @count: (condition, callback) ->
    return if @_waitingForConnection @, @count, arguments

    if typeof condition is 'function'
      callback = condition
      condition = null
    query = new Query @
    query.where condition
    if typeof callback is 'function'
      query.count callback
    return query

  ##
  # Deletes records by conditions
  # @param {Object} [condition]
  # @param {Function} [callback]
  # @param {Error} callback.error
  # @param {Number} callback.count
  # @return {Query}
  @delete: (condition, callback) ->
    return if @_waitingForConnection @, @delete, arguments

    if typeof condition is 'function'
      callback = condition
      condition = null
    query = new Query @
    query.where condition
    if typeof callback is 'function'
      query.delete callback
    return query

  ##
  # Adds a has-many association
  # @param {Class<Model>|String} target_model_or_column
  # @param {Object} [options]
  # @param {String} [options.type]
  # @param {String} [options.as]
  # @param {String} [options.foreign_key]
  @hasMany: (target_model_or_column, options) ->
    @_connection._pending_associations.push
      type: 'hasMany'
      this_model: @
      target_model_or_column: target_model_or_column
      options: options

  ##
  # Adds a belongs-to association
  # @param {Class<Model>|String} target_model_or_column
  # @param {Object} [options]
  # @param {String} [options.type]
  # @param {String} [options.as]
  # @param {String} [options.foreign_key]
  @belongsTo: (target_model_or_column, options) ->
    @_connection._pending_associations.push
      type: 'belongsTo'
      this_model: @
      target_model_or_column: target_model_or_column
      options: options

  ##
  # Adds a validator
  #
  # A validator must return false(boolean) or error message(string), or throw an Error exception if invalid
  # @param {Function} validator
  # @param {Model} validator.record
  @addValidator: (validator) ->
    @_validators.push validator

  ##
  # Drops this model from the database
  # @param {Function} callback
  # @param {Error} callback.error
  @drop: (callback) ->
    return if @_waitingForConnection @, @drop, arguments

    @_adapter.drop @_name, callback

  ##
  # Deletes all records from the database
  # @param {Function} callback
  # @param {Error} callback.error
  @deleteAll: (callback) ->
    callback = (->) if typeof callback isnt 'function'
    @delete callback
    return

  @_addForeignKey: (column, target_adapter) ->
    return if @_schema.hasOwnProperty column

    if @_adapter is target_adapter and target_adapter.key_type_internal
      type = target_adapter.key_type_internal
    else
      type = target_adapter.key_type

    @_schema[column] = { type: type }

  ##
  # Adds a callback of after initializing
  # @param {Function|String} method
  @afterInitialize: (method) ->
    @addCallback 'after', 'initialize', method

  ##
  # Adds a callback of after finding
  # @param {Function|String} method
  @afterFind: (method) ->
    @addCallback 'after', 'find', method

  ##
  # Adds a callback of before saving
  # @param {Function|String} method
  @beforeSave: (method) ->
    @addCallback 'before', 'save', method

  ##
  # Adds a callback of after saving
  # @param {Function|String} method
  @afterSave: (method) ->
    @addCallback 'after', 'save', method

  ##
  # Adds a callback of before creating
  # @param {Function|String} method
  @beforeCreate: (method) ->
    @addCallback 'before', 'create', method

  ##
  # Adds a callback of after creating
  # @param {Function|String} method
  @afterCreate: (method) ->
    @addCallback 'after', 'create', method

  ##
  # Adds a callback of before updating
  # @param {Function|String} method
  @beforeUpdate: (method) ->
    @addCallback 'before', 'update', method

  ##
  # Adds a callback of after updating
  # @param {Function|String} method
  @afterUpdate: (method) ->
    @addCallback 'after', 'update', method

  ##
  # Adds a callback of before destroying
  # @param {Function|String} method
  @beforeDestroy: (method) ->
    @addCallback 'before', 'destroy', method

  ##
  # Adds a callback of after destroying
  # @param {Function|String} method
  @afterDestroy: (method) ->
    @addCallback 'after', 'destroy', method

  ##
  # Adds a callback of before validating
  # @param {Function|String} method
  @beforeValidate: (method) ->
    @addCallback 'before', 'validate', method

  ##
  # Adds a callback of after validating
  # @param {Function|String} method
  @afterValidate: (method) ->
    @addCallback 'after', 'validate', method

  ##
  # Adds a callback
  # @param {String} type
  # @param {String} name
  # @param {Function|String} method
  @addCallback: (type, name, method) ->
    return if not (type is 'before' or type is 'after') or not name
    callbacks_map = @_callbacks_map ||= {}
    callbacks = callbacks_map[name] ||= []
    callbacks.push type: type, method: method

  _runCallbacks: (name, type) ->
    callbacks = @constructor._callbacks_map?[name]
    callbacks = callbacks?.filter (callback) -> callback.type is type
    callbacks?.forEach (callback) =>
      method = callback.method
      if typeof method is 'string'
        throw new Error("The method '#{method}' doesn't exist") unless @[method]
        method = @[method]
      throw new Error("Cannot execute method") if typeof method isnt 'function'
      method.call @

for type, value of require './types'
  Model[type] = value
  Model::[type] = value

module.exports = Model
