async = require 'async'
util = require 'util'
logger = require 'winston'
settings = require '../settings'
eventModule = require './event'
Subscriber = require('./subscriber').Subscriber
fs = require('fs');

AppConfig = settings.AppConfig
Message = settings.Message

filterFields = (params) ->
  fields = {}
  fields[key] = val for own key, val of params when key in ['proto', 'token', 'lang', 'badge', 'version', 'category', 'contentAvailable']
  return fields

# appId, appDebug, os, appHash, appUsername
exports.setupRestApi = (redis, app, createSubscriber, getEventFromId, authorize, testSubscriber, eventPublisher, checkStatus) ->    
  
  authorize ?= (realm) ->

  app.post '/apps/register', authorize('anonymous'), (req, res) ->
    
    logger.info("======================================")
    logger.info("============== body = #{JSON.stringify(req.body)}")
    logger.info("======================================")


    configs = settings.configs


    appId = req.body.appId
    appUserEmail = req.body.appUserEmail || ""
    appUserName = req.body.appUserName || ""
    proto = req.body.proto || ""
    appHash = req.body.appHash
    appDebug = if req.body.appDebug == true || req.body.appDebug == 'S' then true else false
    server_name = "nenhum"
    apn_name_general = "nenhum"
    apn_name_mobilemind = "nenhum"
    app_type = req.body.os || 'ios'
    channels = ""                 
    channels_default = configs.apps.defaults_channels
    deviceId = req.body.deviceId || ""

    if !appUserEmail || appUserEmail.trim().length == 0
      res.json error: "user name is required", 500
      return

    if !appUserName || appUserName.trim().length == 0
      res.json error: "user name is required", 500
      return

    server_name_sufix = undefined
    channels_sufix = undefined

    for it in configs.apps.channels
      if it.appid == appId
        server_name_sufix = it.server_name
        channels_sufix = it.channels

     
    if !server_name_sufix
      res.json error: "server name not found to appId #{appId}", 500
      return

    if !channels_sufix
      res.json error: "channels not found to appId #{appId}", 500
      return


    if appDebug            
      for sufix in channels_sufix
        channels += "#{sufix}-dev,"

      for channel in channels_default
        channels += "#{channel}-dev,"
    else            
      for sufix in channels_sufix
        channels += "#{sufix},"

      for channel in channels_default
        channels += "#{channel},"

    if app_type == 'ios'

      proto = "apns"

      if appDebug
        server_name = "apns-#{server_name_sufix}-dev"
      else
        server_name = "apns-#{server_name_sufix}"        

    else if app_type == 'android'

      if !proto || proto == ""
        proto = "gcm"

      if appDebug
        server_name = "#{proto}-#{server_name_sufix}-dev"
      else
        server_name = "#{proto}-#{server_name_sufix}"

    data = {
      server_name: server_name,                        
      subscrible_channels: channels,
      app_id: appId,
      app_hash: appHash,
      app_user_email: appUserEmail,
      app_debug: appDebug,
      app_user_name: appUserName
      deviceId: deviceId
      updatedAt: new Date()
    }

    logger.info("*************** data app config")
    logger.info(JSON.stringify(data))
    logger.info("*************** data app config")

    queryArgs = {}

    if data.deviceId && data.deviceId.trim().length > 0     
      queryArgs = { app_debug: appDebug, deviceId: data.deviceId, app_id: appId }
    else
      queryArgs = { app_hash: data.app_hash, app_debug: appDebug, app_id: appId  }

    logger.info("*************** find by app config")
    logger.info(JSON.stringify(queryArgs))
    logger.info("*************** find by app config")

    AppConfig.findOne queryArgs, (err, appConfig) ->          

      if err
        res.json error: err.message, 500
        return

      if appConfig

        subscriber_update_func = (do_subscription) ->
          AppConfig.update {_id: appConfig._id, app_debug: appDebug }, data, (err, numAffected) ->
            if err              
              res.json error: err.message, 500
            else
              logger.info("** update config sucesso = #{numAffected}")
              
              if !appConfig.subscrible_id || appConfig.subscrible_id == "" || do_subscription
                logger.info("** subscription need.. go to on_subscribe")
                AppConfig.findOne { _id: appConfig._id }, (err, appConfig) ->
                  on_subscribe(appConfig, req, res)
              else              
                logger.info("** subscrible_id already exists")
                res.json status: 200 
        
        if appConfig.app_hash != data.app_hash
          logger.info("** subscriber #{appConfig.subscrible_id} with different hash ")
          # gera novo subscriber_id para novo hash

          subscriber = new Subscriber(redis, appConfig.subscrible_id)
          subscriber.get (subscriber_found) ->

            if subscriber_found

              logger.info("** subscriber found id #{subscriber.id}")
          
              subscriber.delete (deleted) ->
                logger.info("** delete subscriber #{appConfig.subscrible_id}. status #{deleted}")
                if deleted
                  subscriber_update_func(true)
            else
              # gera novo subscriber_id para nao existente
              logger.info("** subscriber #{appConfig.subscrible_id} not found")
              subscriber_update_func(true)
        
        else
          # atualiza informações sem gerar novo subscriber_id
          subscriber_update_func()        

      else
        data.subscrible_id = ""
        appConfig = new AppConfig(data)
        appConfig.createdAt = new Date()
        appConfig.updatedAt = new Date()
        appConfig.save (err)-> # create new app client
          if err
            res.json error: err.message, 500
          else
            logger.info("** save new app config sucesso")
            on_subscribe(appConfig, req, res)


  on_subscribe = (appConfig, req, res, callback) ->

    body = {
      proto: appConfig.server_name
      token: appConfig.app_hash
      lang: "fr"
      badge: 0
      category: "show"
      contentAvailable: true                            
    }  

    if !callback
      callback = (j) ->
        res.json(j)

    # create app subscriber
    subscribers body, res, (subscriber) ->

      if !subscriber
        callback status: 500, message: 'subscriber not created'
        return

      logger.info("subscriber created id #{subscriber.id}")

      AppConfig.update {_id: appConfig._id}, {subscrible_id: subscriber.id}, (erre, numAffected) ->
        if erre
          logger.error("error on update subscriber to set id: #{body}")
          callback status: 301, message: "error on update subscriber to set id"
        else
          callback status: 200
      
      events = appConfig.subscrible_channels.split(",")

      for eventName in events
        
        eventName = eventName.trim()
        if eventName == ""
          continue

        logger.info("register subscriber #{subscriber.id} on event #{eventName}")

        event = new eventModule.Event(redis, eventName)

        # create subscriber subscription
        subscriber.addSubscription event, 0, (added) ->
          if added? # added is null if subscriber doesn't exist
            if added    
              logger.info "subscription event #{eventName} created to subscriber #{subscriber.id}"
            else
              logger.error "subscription event #{eventName} not created to subscriber #{subscriber.id}"
          else
            logger.error "subscription event #{eventName} not created to subscriber #{subscriber.id}"

  app.get '/', authorize('admin'), (req, res) ->
    res.render('index', {})

  app.get '/logout', authorize('admin'), (req, res) ->
    res.set("WWW-Authenticate", "Basic realm=\"Authorization Required\"")
    res.status(401).send("Authorization Required")

  app.get '/apps/register/all', authorize('admin'), (req, res) ->

    for_each = (idx, list, callback, done) ->
      if idx >= list.length 
        done()
      else
        callback(list[idx])

    AppConfig.find (err, items) ->
      if err
        res.json error: err
      else
        idx = 0

        messages = []

        done = () ->
          res.json({
            count: items.length
            messages: messages
          })

        callback = (appConfig) ->
          on_subscribe appConfig, req, res, (message) ->
            
            message.server_name = appConfig.server_name
            message.subscrible_channels = appConfig.subscrible_channels
            message.app_id = appConfig.app_id
            message.app_user_name = appConfig.app_user_name
            message.app_user_email = appConfig.app_user_email
            message.app_debug = appConfig.app_debug


            subscrible_id = appConfig.subscrible_id

            if not subscrible_id or subscrible_id.trim() is ""
              subscrible_id = appConfig.subscriber_id

            message.subscrible_id = subscrible_id

            messages.push message

            for_each idx++, items, callback, done

        for_each idx++, items, callback, done
        
  app.get '/apps/show/all', authorize('admin'), (req, res) ->

    AppConfig.find (err, items) ->
      if err
        res.json error: err
      else
        messages = []

        for appConfig in items
          message = {}
          message.server_name = appConfig.server_name
          message.subscrible_channels = appConfig.subscrible_channels
          message.app_id = appConfig.app_id
          message.app_user_name = appConfig.app_user_name
          message.app_user_email = appConfig.app_user_email
          message.app_debug = appConfig.app_debug
          
          subscrible_id = appConfig.subscrible_id

          if not subscrible_id or subscrible_id.trim() is ""
            subscrible_id = appConfig.subscriber_id

          message.subscrible_id = subscrible_id

          messages.push message

        res.json(messages)                    

  app.get '/apps/configurations', authorize('admin'), (req, res) ->
    res.json(settings.configs)

  app.get '/apps/settings', authorize('admin'), (req, res) ->
    res.json(settings)

  app.get '/apps/logs', authorize('admin'), (req, res) ->

    if fs.existsSync("/home/ubuntu/.forever/pushd.log")
      res.download("/home/ubuntu/.forever/pushd.log")
    else
      res.json(404, "No logs at /home/ubuntu/.forever/pushd.log")

  app.get '/apps/users', authorize('admin'), (req, res) ->
    res.render('users')

  app.post '/apps/users', authorize('admin'), (req, res) ->    

    page = {
      limit: req.body.max || 25
      skip: req.body.offset || 0
      sort: {
        
      }
    }

    page.sort[req.body.order_column] = if req.body.order_sort == 'desc' then -1 else 1

    args = {}

    console.log "req.body.search = #{req.body.search}"
    if req.body.search and req.body.search.trim() isnt ""
      args.$or = [
        { app_id: new RegExp(req.body.search, 'i') }
        { subscrible_id: new RegExp(req.body.search, 'i') }
        { app_user_email: new RegExp(req.body.search, 'i') }
        { app_user_name: new RegExp(req.body.search, 'i') }
      ]

    AppConfig.find(args, null, page).exec (err, results) ->

      if err
        res.json({error: true, message: err})
      else

        items = []

        for it in results
          item = it.toJSON()
          if not it.app_hash
            item.app_hash = ""
          items.push(item)

        AppConfig.countDocuments = AppConfig.countDocuments || AppConfig.count
        AppConfig.countDocuments args, (err, count) ->
          if err
            res.json({error: true, message: err})
          else
            res.json({results: items, totalCount: count})      
    
  app.get '/apps/remove/:subscriber_id', authorize('admin'), (req, res) ->    

    subscriber_deleted = false
    mongo_deleted = false

    logger.info("trying remove subscriber #{req.params.subscriber_id}")
    
    subscriber_remove_func = () ->
      AppConfig.findOne { 'subscrible_id': req.params.subscriber_id }, (err, it) ->
        if err
          res.json error: err
        else                                    
          if it
            AppConfig.remove {_id: it._id}, (errr) ->
              if errr
                logger.info("remove subscriber error: #{errr}")
                res.json error: errr.message, 500               
              else
                mongo_deleted = true
                res.json 'redis-deleted': subscriber_deleted, 'mongo-deleted': mongo_deleted            
          else
            logger.error "No subscriber #{req.params.subscriber_id} found to mongo remove"
            res.json 'redis-deleted': subscriber_deleted, 'mongo-deleted': mongo_deleted


    req.subscriber.get (sub) ->

      if sub
        req.subscriber.delete (deleted) ->

          if not deleted
            logger.error "No subscriber #{req.subscriber.id} remove. Not deleted"
          else
            subscriber_deleted = true

          subscriber_remove_func()

      else
        logger.error "No subscriber #{req.subscriber.id} found to redis remove"
        subscriber_remove_func()
  

  app.get '/apps/messages', authorize('admin'), (req, res) ->
    res.render('messages')

  app.post '/apps/messages', authorize('admin'), (req, res) ->

    page = {
      limit: req.body.max || 25
      skip: req.body.offset || 0
      sort: {
        
      }
    }

    page.sort[req.body.order_column] = if req.body.order_sort == 'desc' then -1 else 1

    args = {}

    console.log "req.body.search = #{req.body.search}"
    if req.body.search and req.body.search.trim() isnt ""
      args.$or = [
        { sender: new RegExp(req.body.search, 'i') }
        { eventName: new RegExp(req.body.search, 'i') }
        { content: new RegExp(req.body.search, 'i') }
      ]

    Message.find(args, null, page).exec (err, results) ->

      if err
        res.json({error: true, message: err})
      else
        Message.countDocuments = Message.countDocuments || Message.count
        Message.countDocuments args, (err, count) ->
          if err
            res.json({error: true, message: err})
          else
            res.json({results: results, totalCount: count})

  app.get '/apps/message', authorize('admin'), (req, res) ->
    
    channels = []

    AppConfig.find (err, items) ->
      if err
        res.json error: err
        return

      for it in items
        cls = it.subscrible_channels.split(',')
        for c in cls
          c = c.trim()
          if c and c not in channels
            channels.push(c)

      res.render('message', {channels: channels})

  app.get '/apps/users-by-channel', authorize('publish'), (req, res) ->
        
    channel = req.query.channel

    if !channel
      res.json error: "channels param is required", 500
      return

    AppConfig.find({subscrible_channels: {$regex : ".*#{channel},.*"} }).exec (err, items) ->
      
      if err
        res.json error: err
        return
      
      users = []
      accounts = {}

      for it in items            
        
        if !accounts[it.app_user_email]
          accounts[it.app_user_email] = []


        subscrible_id = it.subscrible_id

        if not subscrible_id or subscrible_id.trim() is ""
          subscrible_id = it.subscriber_id

        if not subscrible_id or subscrible_id.trim() is "" 
          logger.info("not subscrible_id valid to user #{it.app_user_name} - #{it.it.app_user_email}")
          continue

        user = {                        
          subscrible_id: subscrible_id
          name: it.app_user_name
          email: it.app_user_email
          production: !it.app_debug
          ios: it.server_name.indexOf('apns-') > -1
          android: it.server_name.indexOf('gcm-') > -1 || it.server_name.indexOf('fcm-') > -1
          deviceId: it.deviceId
        }

        if it.createdAt
          user.createdAt = it.createdAt.toISOString().slice(0, 10)

        if it.updatedAt
          user.updatedAt = it.updatedAt.toISOString().slice(0, 10)

        accounts[it.app_user_email].push(user)

      res.json(accounts)

  app.get '/apps/:channel', authorize('publish'), (req, res) ->
        
    channel = req.params.channel

    if !channel || channel.trim().length == 0
      res.json error: "channels param is required", 500
      return
      
    AppConfig.find({subscrible_channels: {$regex : ".*#{channel},.*"} }).exec (err, items) ->
      if err
        res.json error: err
        return
      
      users = []
      accounts = {}

      for it in items            
        
        subscrible_id = it.subscrible_id

        if not subscrible_id or subscrible_id.trim() is "" 
          subscrible_id = it.subscriber_id

        if not subscrible_id or subscrible_id.trim() is "" 
          logger.info("not subscrible_id valid to user #{it.app_user_name} - #{it.it.app_user_email}")
          continue
        

        if !accounts[it.app_user_email]
          accounts[it.app_user_email] = []

        user = {                        
          subscrible_id: subscrible_id
          name: it.app_user_name
          email: it.app_user_email
          production: !it.app_debug
          ios: it.server_name.indexOf('apns-') > -1
          android: it.server_name.indexOf('gcm-') > -1 || it.server_name.indexOf('fcm-') > -1
          deviceId: it.deviceId
        }

        if it.createdAt
          user.createdAt = it.createdAt.toISOString().slice(0, 10)

        if it.updatedAt
          user.updatedAt = it.updatedAt.toISOString().slice(0, 10)

        accounts[it.app_user_email].push(user)


      res.json(accounts)

  # subscriber registration

  subscribers = (body, res, end) ->

    logger.verbose "Registering subscriber: #{JSON.stringify(body)}"

    try
      fields = filterFields(body)
      createSubscriber fields, (subscriber, created) ->
        subscriber.get (info) ->
          info.id = subscriber

          logger.info("subscriber #{subscriber.id} register created: #{created}")

          if end
            end(subscriber)
            return

          res.header 'Location', "/subscriber/#{subscriber.id}"                    
          res.json {}, if created then 201 else 200
    catch error

      logger.error "Creating subscriber failed: #{error.message}"

      if end
        end()
        return

      res.json error: error.message, 400

  app.post '/subscribers', authorize('register'), (req, res) ->
    subscribers(req.body, res)

  # Get subscriber info
  app.get '/subscriber/:subscriber_id', authorize('register'), (req, res) ->
    req.subscriber.get (fields) ->
      if not fields?
        logger.error "No subscriber #{req.subscriber.id}"
      else
        logger.verbose "Subscriber #{req.subscriber.id} info: " + JSON.stringify(fields)
      res.json fields, if fields? then 200 else 404

  # Edit subscriber info
  app.post '/subscriber/:subscriber_id', authorize('register'), (req, res) ->
    logger.verbose "Setting new properties for #{req.subscriber.id}: " + JSON.stringify(req.body)
    fields = filterFields(req.body)
    req.subscriber.set fields, (edited) ->
      if not edited
        logger.error "No subscriber #{req.subscriber.id}"
      res.send if edited then 204 else 404

  # Unregister subscriber
  app.delete '/subscriber/:subscriber_id', authorize('register'), (req, res) ->
    req.subscriber.delete (deleted) ->
      if not deleted
        logger.error "No subscriber #{req.subscriber.id}"
      res.send if deleted then 204 else 404

  app.post '/subscriber/:subscriber_id/test', authorize('register'), (req, res) ->
    testSubscriber(req.subscriber)
    res.send 201

  # Get subscriber subscriptions
  app.get '/subscriber/:subscriber_id/subscriptions', authorize('register'), (req, res) ->
    req.subscriber.getSubscriptions (subs) ->
      if subs?
        subsAndOptions = {}
        for sub in subs
          subsAndOptions[sub.event.name] = {ignore_message: (sub.options & sub.event.OPTION_IGNORE_MESSAGE) isnt 0}
        logger.verbose "Status of #{req.subscriber.id}: " + JSON.stringify(subsAndOptions)
        res.json subsAndOptions
      else
        logger.error "No subscriber #{req.subscriber.id}"
        res.send 404

  # Set subscriber subscriptions
  app.post '/subscriber/:subscriber_id/subscriptions', authorize('register'), (req, res) ->
    subsToAdd = req.body
    logger.verbose "Setting subscriptions for #{req.subscriber.id}: " + JSON.stringify(req.body)
    for eventId, optionsDict of req.body
      try
        event = getEventFromId(eventId)
        options = 0
        if optionsDict? and typeof(optionsDict) is 'object' and optionsDict.ignore_message
          options |= event.OPTION_IGNORE_MESSAGE
        subsToAdd[event.name] = event: event, options: options
      catch error
        logger.error "Failed to set subscriptions for #{req.subscriber.id}: #{error.message}"
        res.json error: error.message, 400
        return

    req.subscriber.getSubscriptions (subs) ->
      if not subs?
        logger.error "No subscriber #{req.subscriber.id}"
        res.send 404
        return

      tasks = []

      for sub in subs
        if sub.event.name of subsToAdd
          subToAdd = subsToAdd[sub.event.name]
          if subToAdd.options != sub.options
            tasks.push ['set', subToAdd.event, subToAdd.options]
          delete subsToAdd[sub.event.name]
        else
          tasks.push ['del', sub.event, 0]

      for eventName, sub of subsToAdd
        tasks.push ['add', sub.event, sub.options]

      async.every tasks, (task, callback) ->
        [action, event, options] = task
        if action == 'add'
          req.subscriber.addSubscription event, options, (added) ->
            callback(added)
        else if action == 'del'
          req.subscriber.removeSubscription event, (deleted) ->
            callback(deleted)
        else if action == 'set'
          req.subscriber.addSubscription event, options, (added) ->
            callback(!added) # should return false
      , (result) ->
        if not result
          logger.error "Failed to set properties for #{req.subscriber.id}"
        res.send if result then 204 else 400

  # Get subscriber subscription options
  app.get '/subscriber/:subscriber_id/subscriptions/:event_id', authorize('register'), (req, res) ->
    req.subscriber.getSubscription req.event, (options) ->
      if options?
        res.json {ignore_message: (options & req.event.OPTION_IGNORE_MESSAGE) isnt 0}
      else
        logger.error "No subscriber #{req.subscriber.id}"
        res.send 404

  # Subscribe a subscriber to an event
  app.post '/subscriber/:subscriber_id/subscriptions/:event_id', authorize('register'), (req, res) ->
    options = 0
    if parseInt req.body.ignore_message
      options |= req.event.OPTION_IGNORE_MESSAGE
    req.subscriber.addSubscription req.event, options, (added) ->
      if added? # added is null if subscriber doesn't exist
        res.send if added then 201 else 204
      else
        logger.error "No subscriber #{req.subscriber.id}"
        res.send 404

  # Unsubscribe a subscriber from an event
  app.delete '/subscriber/:subscriber_id/subscriptions/:event_id', authorize('register'), (req, res) ->
    req.subscriber.removeSubscription req.event, (deleted) ->
      if not deleted?
        logger.error "No subscriber #{req.subscriber.id}"
      else if not deleted
        logger.error "Subscriber #{req.subscriber.id} was not subscribed to #{req.event.name}"
      res.send if deleted then 204 else 404

  # Event stats
  app.get '/event/:event_id', authorize('register'), (req, res) ->
    req.event.info (info) ->
      if not info?
        logger.error "No event #{req.event.name}"
      else
        logger.verbose "Event #{req.event.name} info: " + JSON.stringify info
      res.json info, if info? then 200 else 404

  # Publish an event
  app.post '/event/:event_id', authorize('publish'), (req, res) ->
    res.send 204
    logger.info("********************* new event publish ***********************")
    logger.info("#{JSON.stringify(req.body)}")
    logger.info("********************* new event publish ***********************")

    message = new Message({
      sender: req.user
      eventName: req.params.event_id
      content: JSON.stringify(req.body)
      createdAt: new Date()
    })

    message.save (error) ->
      if error
        logger.error "error save event message: #{error} "

    eventPublisher.publish(req.event, req.body)

  # Delete an event
  app.delete '/event/:event_id', authorize('publish'), (req, res) ->
    req.event.delete (deleted) ->
      if not deleted
        logger.error "No event #{req.event.name}"
      if deleted
        res.send 204
      else
        res.send 404
  # Server status
  app.get '/status', authorize('register'), (req, res) ->
    if checkStatus()
      res.send 204
    else
      res.send 503
  