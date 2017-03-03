async = require 'async'
util = require 'util'
logger = require 'winston'
settings = require '../settings'
eventModule = require './event'
Subscriber = require('./subscriber').Subscriber
fs = require('fs');

filterFields = (params) ->
	fields = {}
	fields[key] = val for own key, val of params when key in ['proto', 'token', 'lang', 'badge', 'version', 'category', 'contentAvailable']
	return fields

# appId, appDebug, os, appHash, appUsername
exports.setupRestApi = (redis, app, createSubscriber, getEventFromId, authorize, testSubscriber, eventPublisher, checkStatus) ->    
	authorize ?= (realm) ->

	app.post '/apps/register', (req, res) ->
		
		console.log("======================================")
		console.log("============== body = #{JSON.stringify(req.body)}")
		console.log("======================================")


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
			res.json error: "server name not found to appId #{appid}", 500
			return

		if !channels_sufix
			res.json error: "channels not found to appId #{appid}", 500
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
		}

		console.log("####################### data")
		console.log(JSON.stringify(data))
		console.log("####################### data")

		queryArgs = {}

		if data.deviceId && data.deviceId.trim().length > 0			
			queryArgs = { app_debug: appDebug, deviceId: data.deviceId }
		else
			queryArgs = { app_hash: data.app_hash, app_debug: appDebug }

		console.log("####################### find by ")
		console.log(JSON.stringify(queryArgs))
		console.log("####################### find by ")

		settings.AppConfig.findOne queryArgs, (err, appConfig) ->					

			if err
				res.json error: err.message, 500
				return

			if appConfig

				subscriber_update_func = (do_subscription) ->
					settings.AppConfig.update {_id: appConfig._id, app_debug: appDebug, updatedAt: new Date()}, data, (err, numAffected) ->
						if err
							console.log("#### update err=#{err}")
							res.json error: err.message, 500
						else
							console.log("#### update sucesso")
							
							if !appConfig.subscrible_id || appConfig.subscrible_id == "" || do_subscription
								console.log("#### subscription need.. go to on_subscribe")
								on_subscribe(appConfig, req, res)
							else							
								console.log("#### subscrible_id already exists")
								res.json status: 200 
				
				if appConfig.app_hash != data.app_hash
					# gera novo subscriber_id para novo hash
					new Subscriber(redis, appConfig.subscrible_id).get (subscriber) ->

						if subscriber
				
							subscriber.delete (deleted) ->
								console.log("delete subscriber #{appConfig.subscrible_id}. status #{deleted}")
								if deleted
									subscriber_update_func(true)
						else
							# gera novo subscriber_id para nao existente
							console.log("subscriber #{appConfig.subscrible_id} not found")
							subscriber_update_func(true)
				
				else
					# atualiza informações sem gerar novo subscriber_id
					subscriber_update_func()				

			else
				data.subscrible_id = ""
				appConfig = new settings.AppConfig(data)
				appConfig.createdAt = new Date()
				appConfig.updatedAt = new Date()
				appConfig.save (err)-> # create new app client
					if err
						console.log("#### save err=#{err}")
						res.json error: err.message, 500
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
			doneCallback = (j) ->
				res.json(j)

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

	app.get '/apps/index', (req, res) ->
		res.render('index', {})

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
						
						message.server_name = appConfig.server_name
						message.subscrible_channels = appConfig.subscrible_channels
						message.app_id = appConfig.app_id
						message.app_user_name = appConfig.app_user_name
						message.app_user_email = appConfig.app_user_email
						message.app_debug = appConfig.app_debug
						message.subscriber_id = appConfig.subscrible_id

						messages.push message

						for_each idx++, items, callback, done

				for_each idx++, items, callback, done

	app.get '/apps/remove/empty', (req, res) ->

		settings.AppConfig.find (err, items) ->
			if err
				res.json error: err
			else                
				for it in items
					if !it.subscrible_id || it.subscrible_id == ""
						settings.AppConfig.remove {_id: it._id}, (errr) ->
							if errr
								console.log("##### error = #{errr}")
								res.json error: errr.message, 500                         

			
				setTimeout(() ->
					res.redirect('/apps/users')
				, 500)
				
	app.get '/apps/show/all', (req, res) ->

		settings.AppConfig.find (err, items) ->
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
					message.subscriber_id = appConfig.subscrible_id
					messages.push message

				res.json(messages)                    

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
						subscriber_id: it.subscrible_id,
						
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
							console.log("##### error = #{errr}")
							res.json error: errr.message, 500                      

			
				setTimeout(() ->
					res.redirect('/apps/users') 
				, 500)

	app.get '/apps/remove/:subscriber_id', (req, res) ->    

		subscriber_deleted = false
		mongo_deleted = false

		console.log("remove subscriber_id=#{req.params.subscriber_id}")
		
		subscriber_remove_func = () ->
			settings.AppConfig.findOne { 'subscrible_id': req.params.subscriber_id }, (err, it) ->
				if err
					res.json error: err
				else                                    
					if it
						settings.AppConfig.remove {_id: it._id}, (errr) ->
							if errr
								console.log("##### error = #{errr}")
								res.json error: errr.message, 500								
							else
								mongo_deleted = true
								res.json 'redis-deleted': subscriber_deleted, 'mongo-deleted': mongo_deleted            
					else
						logger.error "No subscriber found #{req.params.subscriber_id} on mongo"
						res.json 'redis-deleted': subscriber_deleted, 'mongo-deleted': mongo_deleted


		req.subscriber.get (sub) ->

			if sub
				req.subscriber.delete (deleted) ->

					if not deleted
						logger.error "No subscriber #{req.subscriber.id} on redis"
					else
						subscriber_deleted = true

					subscriber_remove_func()

			else
				logger.error "No subscriber found #{req.params.subscriber_id} on redis"
				subscriber_remove_func()
																							 
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
					subscriber_id: it.subscrible_id
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
		console.log("message = #{JSON.stringify(req.body)}")
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
	