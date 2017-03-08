FCM = require 'fcm-node'

class PushServiceFCM
    validateToken: (token) ->
        return token

    constructor: (conf, @logger, tokenResolver) ->
        conf.concurrency ?= 10
        @driver = new FCM(conf.key, conf.options)
        @multicastQueue = {}

    push: (subscriber, subOptions, payload) ->
        subscriber.get (info) =>
            messageKey = "#{payload.id}-#{info.lang or 'int'}-#{!!subOptions?.ignore_message}"

            # Multicast supports up to 1000 subscribers
            if messageKey of @multicastQueue and @multicastQueue[messageKey].tokens.length >= 1000
                @.send messageKey

            if messageKey of @multicastQueue
                @multicastQueue[messageKey].tokens.push(info.token)
                @multicastQueue[messageKey].subscribers.push(subscriber)
            else
                note = { notification: {}, data: {}, to: info.token }
                note.collapseKey = payload.event?.name
                if subOptions?.ignore_message isnt true
                    if title = payload.localizedTitle(info.lang)
                        note.notification.title = title
                    if message = payload.localizedMessage(info.lang)
                        note.notification.body = message

                    if payload.color
                        note.notification.color = payload.color

                    if payload.icon
                        note.notification.icon = payload.icon

                for key, value of payload.data
                    note.data[key] = value

                @multicastQueue[messageKey] = {tokens: [info.token], subscribers: [subscriber], note: note}

                # Give half a second for tokens to accumulate
                @multicastQueue[messageKey].timeoutId = setTimeout (=> @.send(messageKey)), 500

    send: (messageKey) ->
        message = @multicastQueue[messageKey]
        delete @multicastQueue[messageKey] 
        clearTimeout message.timeoutId

        @driver.send message.note, (err, multicastResult) =>
            
            if not multicastResult?
                @logger?.error("FCM Error: empty response")
            else if 'results' of JSON.parse(multicastResult)                
                multicastResult = JSON.parse(multicastResult)
                for result, i in multicastResult.results
                    @.handleResult result, message.subscribers[i]
            else
                # non multicast result
                @handleResult multicastResult, message.subscribers[0]

    handleResult: (result, subscriber) ->

        console.log(result)
        if result.registration_id?
            # Remove duplicated subscriber for one device
            subscriber.delete() if result.registration_id isnt subscriber.info.token
        else if result.messageId or result.message_id
            # if result.canonicalRegistrationId
                # TODO: update subscriber token
        else
            error = result.error or result.errorCode
            if error is "NotRegistered" or error is "InvalidRegistration"
                @logger?.warn("FCM #{error}")
                @logger?.warn("FCM Automatic unregistration for subscriber #{subscriber.id}")
                subscriber.delete()
            else
                @logger?.error("FCM Error: #{error}")



exports.PushServiceFCM = PushServiceFCM
