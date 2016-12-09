async = require 'async'
util = require 'util'
logger = require 'winston'
settings = require '../settings'
eventModule = require './event'

filterFields = (params) ->
    fields = {}
    fields[key] = val for own key, val of params when key in ['proto', 'token', 'lang', 'badge', 'version', 'category', 'contentAvailable']
    return fields

# appId, appDebug, os, appHash, appUsername
exports.setupRestApi = (redis, app, createSubscriber, getEventFromId, authorize, testSubscriber, eventPublisher, checkStatus) ->    
    authorize ?= (realm) ->

    app.post '/apps/register', (req, res) ->
        
        appId = req.body.appId
        appUserEmail = req.body.appUserEmail || ""
        appUserName = req.body.appUserName || ""
        appHash = req.body.appHash
        appDebug = if req.body.appDebug == true || req.body.appDebug == 'S' then true else false
        server_name = "nenhum"
        apn_name_general = "nenhum"
        apn_name_mobilemind = "nenhum"
        app_type = req.body.os || 'ios'
        channels = ""                 
        channels_default = ['mobilemind']        

        if appId == 'com.sigturismo.atuaserra'
            server_name_sufix = 'sigturismo-9'
            channels_sufix = ['sigturismo', 'sigturismo-9']
        
        else if appId == 'br.com.mobilemind.mybookapp'
            server_name_sufix = 'my-book-app'
            channels_sufix = ['my-book-app']

        else if appId == 'br.com.mobilemind.gym'
            server_name_sufix = '4gym'
            channels_sufix = ['4gym']
        
        else if appId == 'br.com.mobilemind.gym.college'
            server_name_sufix = '4gym-college'
            channels_sufix = ['4gym-college', '4gym']
        
        else if appId == 'br.com.mobilemind.gym.jinseon'
            server_name_sufix = '4gym-jinseon'
            channels_sufix = ['4gym-jinseon', '4gym']

        else if appId == 'br.com.mobilemind.gym.bodysul'
            server_name_sufix = '4gym-bodysull'
            channels_sufix = ['4gym-bodysull', '4gym']

        else if appId == 'org.nativescript.PushApp'
            server_name_sufix = 'push-app'
            channels_sufix = ['push-app']            
            
        
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

            if appDebug
                server_name = "apns-#{server_name_sufix}-dev"
            else
                server_name = "apns-#{server_name_sufix}"        

        else if app_type == 'android'
            if appDebug
                server_name = "gcm-#{server_name_sufix}-dev"
            else
                server_name = "gcm-#{server_name_sufix}"



        data = {
            server_name: server_name,
            
            subscrible_id: "",
            
            subscrible_channels: channels,

            app_id: appId,
            app_hash: appHash,
            app_user_email: appUserEmail,
            app_debug: appDebug,
            app_user_name: appUserName
        }

        console.log("####################### data")
        console.log(JSON.stringify(data))
        console.log("####################### data")

        settings.AppConfig.findOne { app_hash: data.app_hash, app_debug: appDebug }, (err, appConfig) ->

            if err
                res.json status: 500
                return

            if appConfig
                settings.AppConfig.update {_id: appConfig._id, app_debug: appDebug}, data, (err, numAffected) ->
                    if err
                        console.log("#### update err=#{err}")
                        res.json status: 500, message: "#### update err=#{err}"
                    else
                        console.log("#### update sucesso")
                        #res.json status: 200 

                        on_subscribe(appConfig, req, res)
            else
                appConfig = new settings.AppConfig(data)
                appConfig.save (err)-> # create new app client
                    if err
                        console.log("#### save err=#{err}")
                        res.json status: 500, message: "#### save err=#{err}"
                    else
                        console.log("#### save sucesso")

                        on_subscribe(appConfig, req, res)


    on_subscribe = (appConfig, req, res, doneCallback) ->

        body = {
            proto: appConfig.server_name
            token: appConfig.app_hash
            lang: "fr"
            badge: 0
            category: "show"
            contentAvailable: true                            
        }  

        if !doneCallback
            doneCallback = res.json

        # create app subscriber
        subscribers body, res, (subscriber) ->

            if !subscriber
                doneCallback status: 500, message: 'not create subscriber'
                return

            console.log("### subscriber.id=#{subscriber.id}")
            settings.AppConfig.update {_id: appConfig._id}, {subscrible_id: subscriber.id}, (erre, numAffected) ->
                if erre
                    console.log("### error on get subscriber id from appConfig.apn_name=#{body.proto}")
                    doneCallback status: 301, message: "### error on get subscriber id from appConfig.apn_name=#{body.proto}"
                else
                    doneCallback status: 200
            
            events = appConfig.subscrible_channels.split(",")

            for eventName in events
                
                eventName = eventName.trim()
                if eventName == ""
                    continue

                console.log("## eventName=#{eventName}")

                event = new eventModule.Event(redis, eventName)

                # create subscriber subscription
                subscriber.addSubscription event, 0, (added) ->
                    if added? # added is null if subscriber doesn't exist
                        if added    
                            console.log "# subscription created to event #{eventName}"
                        else
                            console.log "# subscription not created to event #{eventName}"
                    else
                        logger.error "No subscriber #{subscriber.id}"
                        console.log "# No subscriber #{subscriber.id}"    

    app.get '/apps/register/all', (req, res) ->

        for_each = (idx, list, callback, done) ->
            if idx >= list.length 
                done()
            else
                callback(list[idx])

        settings.AppConfig.find (err, items) ->
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
                        messages.push message
                        for_each idx++, items, callback, done

                for_each idx++, items, callback, done

                

    app.get '/apps/users', (req, res) ->    

        settings.AppConfig.find (err, items) ->
            if err
                res.json error: err
            else
                list = []
                for it in items
                    list.push({
                        server_name: it.server_name,
                        
                        subscrible_id: it.subscrible_id,
                        
                        subscrible_channels: it.subscrible_channels,

                        app_id: it.app_id,
                        app_hash: it.app_hash,
                        app_user_email: it.app_user_email,
                        app_debug: it.app_debug,
                        app_user_name: it.app_user_name

                    })
                res.render('users', {items: list})
        
    app.get '/apps/delete/all', (req, res) ->    

        settings.AppConfig.find (err, items) ->
            if err
                res.json error: err
            else                
                for it in items
                    settings.AppConfig.remove {_id: it._id}, (errr) ->
                        if errr
                            res.json status: 'error'                            
                            console.log("##### error = #{errr}")

            
                setTimeout(() ->
                    res.redirect('/apps/users')
                , 500)


    app.get '/apps/message', (req, res) ->
        
        channels = []

        settings.AppConfig.find (err, items) ->
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

    app.get '/apps/users-by-channel', (req, res) ->
                
        channel = req.query.channel

        if !channel
            res.json({error: true, message: 'channel param is require'})
            return

        settings.AppConfig.find({subscrible_channels: {$regex : ".*#{channel},.*"} }).exec (err, items) ->
            if err
                res.json error: err
            
            users = []
            accounts = {}

            for it in items            
                
                if !accounts[it.app_user_email]
                    accounts[it.app_user_email] = []

                user = {                        
                    subscrible_id: it.subscrible_id
                    name: it.app_user_name
                    email: it.app_user_email
                    production: !it.app_debug
                    ios: it.server_name.indexOf('apns-') > -1
                    android: it.server_name.indexOf('gcm-') > -1
                }

                accounts[it.app_user_email].push(user)


            res.json(accounts)


    # subscriber registration

    subscribers = (body, res, end) ->

        logger.verbose "Registering subscriber: " + JSON.stringify body
        try
            fields = filterFields(body)
            createSubscriber fields, (subscriber, created) ->
                subscriber.get (info) ->
                    info.id = subscriber

                    console.log("### subscriber.id=#{subscriber.id}")

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
    