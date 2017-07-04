FCM = require 'fcm-node'

class PushServiceFCM
    validateToken: (token) ->
        return token

    constructor: (conf, @logger, tokenResolver) ->
        conf.concurrency ?= 10
        @driver = new FCM(conf.key, conf.options)

    push: (subscriber, subOptions, payload) ->
        subscriber.get (info) =>
            
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

            message = {tokens: [info.token], subscribers: [subscriber], note: note}

            #console.log("-------------------------------")
            #console.log("message=" + JSON.stringify(message.note))
            #console.log("-------------------------------")

            @.send message

    send: (message) ->

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
