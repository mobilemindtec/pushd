fs = require('fs');


if !fs.existsSync('./configs.json')
	console.log("***************************************")
	console.log("***************************************")
	console.log("***************************************")    
	console.log("****** CONFIGURATION FILE NOT FOUND!!!!")
	console.log("***************************************")
	console.log("***************************************")
	console.log("***************************************")

file_content = fs.readFileSync('./configs.json', 'utf8')
configs = JSON.parse(file_content);

exports.configs = configs

#console.log("*****************************")
#console.log("configs: #{JSON.stringify(configs)}")
#console.log("*****************************")

exports.server =
	redis_port: 6379
	redis_host: 'localhost'
	# redis_socket: '/var/run/redis/redis.sock'
	# redis_auth: 'password'
	# redis_db_number: 2
	listen_ip: configs.listen_ip
	tcp_port: 3000
	udp_port: 3000
	access_log: yes
	acl: undefined
		# restrict publish access to private networks
		# publish: configs.publish
	auth: configs.auth
		# require HTTP basic authentication, username is 'admin' and
		# password is 'password'
		#
		# HTTP basic authentication overrides IP-based authentication
		# if both acl and auth are defined.
		#admin:
		#    password: 'password'
		#    realms: ['register', 'publish', 'admin']

exports['event-source'] = 
	enabled: yes 

default_apns_config_development =
	enabled: yes
	class: require('./lib/pushservices/apns').PushServiceAPNS
	cacheLength: 100
	payloadFilter: ['messageFrom']
	gateway: 'gateway.sandbox.push.apple.com'
	address: 'feedback.sandbox.push.apple.com'

default_apns_config_production =
	enabled: yes
	class: require('./lib/pushservices/apns').PushServiceAPNS
	cacheLength: 100
	payloadFilter: ['messageFrom']
	gateway: 'gateway.push.apple.com'
	address: 'feedback.push.apple.com'

certificados_development = configs.apps.apns.development
certificados_production = configs.apps.apns.production

console.log("***************************")

for cert_sufix in certificados_development
	console.log "create APNS development to #{cert_sufix}-dev"
	exports["apns-#{cert_sufix}-dev"] = {}

	for key, value of default_apns_config_development
		exports["apns-#{cert_sufix}-dev"][key] = value
	
	exports["apns-#{cert_sufix}-dev"].cert = "#{configs.apps.apns.development_certs_path}/apns-cert-#{cert_sufix}.pem"
	exports["apns-#{cert_sufix}-dev"].key = "#{configs.apps.apns.development_certs_path}/apns-key-#{cert_sufix}.pem"


console.log("---------------------------")

for cert_sufix in certificados_production
	console.log "create APNS production to #{cert_sufix}"
	exports["apns-#{cert_sufix}"] = {}

	for key, value of default_apns_config_production
		exports["apns-#{cert_sufix}"][key] = value

	exports["apns-#{cert_sufix}"].cert = "#{configs.apps.apns.production_certs_path}/apns-cert-#{cert_sufix}.pem"
	exports["apns-#{cert_sufix}"].key = "#{configs.apps.apns.production_certs_path}/apns-key-#{cert_sufix}.pem"


# # Uncomment to use same host for prod and dev
# exports['apns-dev'] =
#     enabled: yes
#     class: require('./lib/pushservices/apns').PushServiceAPNS
#     # Your dev certificats
#     cert: 'apns-cert.pem'
#     key: 'apns-key.pem'
#     cacheLength: 100
#     gateway: 'gateway.sandbox.push.apple.com'
#	  # Uncomment to set the default value for parameter.
#     # This setting not overrides the value for the parameter that is set in the payload fot event request.
#     # category: 'show'
#     # contentAvailable: true

exports["wns-toast"] =
	enabled: yes
	client_id: 'ms-app://SID-from-developer-console'
	client_secret: 'client-secret-from-developer-console'
	class: require('./lib/pushservices/wns').PushServiceWNS
	type: 'toast'
	# Any parameters used here must be present in each push event.
	launchTemplate: '/Page.xaml?foo=${data.foo}'


console.log("---------------------------")

default_gcm_apps = configs.apps.gcm

for it in default_gcm_apps
	#for sufix in ["-dev", ""]
	for sufix in [""]
		console.log("create GCM to gcm-#{it.name}#{sufix}")
		exports["gcm-#{it.name}#{sufix}"] = 
			enabled: yes
			class: require('./lib/pushservices/gcm').PushServiceGCM
			key: it["key#{sufix}"]            


console.log("---------------------------")

default_fcm_apps = configs.apps.fcm

for it in default_fcm_apps
	#for sufix in ["-dev", ""]
	for sufix in [""]
		console.log("create FCM to fcm-#{it.name}#{sufix}")
		exports["fcm-#{it.name}#{sufix}"] = 
			enabled: yes
			class: require('./lib/pushservices/fcm').PushServiceFCM
			key: it["key#{sufix}"]            


console.log("***************************")

#exports['gcm'] =
#    enabled: yes
#    class: require('./lib/pushservices/gcm').PushServiceGCM
#    key: 'AIzaSyBIxPTLLfk129mQziCGgYDTaKcERb2P-9M'
	 #options:
	   #proxy: 'PROXY SERVER HERE'



# # Legacy Android Push Service
# exports['c2dm'] =
#     enabled: yes
#     class: require('./lib/pushservices/c2dm').PushServiceC2DM
#     # App credentials
#     user: 'app-owner@gmail.com'
#     password: 'something complicated and secret'
#     source: 'com.yourcompany.app-name'
#     # How many concurrent requests to perform
#     concurrency: 10

exports['http'] =
	enabled: yes
	class: require('./lib/pushservices/http').PushServiceHTTP

exports['mpns-toast'] =
	enabled: yes
	class: require('./lib/pushservices/mpns').PushServiceMPNS
	type: 'toast'
	# Used for WP7.5+ to handle deep linking
	paramTemplate: '/Page.xaml?object=${data.object_id}'

exports['mpns-tile'] =
	enabled: yes
	class: require('./lib/pushservices/mpns').PushServiceMPNS
	type: 'tile'
	# Mapping defines where - in the payload - to get the value of each required properties
	tileMapping:
		# Used for WP7.5+ to push to secondary tiles
		# id: "/SecondaryTile.xaml?DefaultTitle=${event.name}"
		# count: "${data.count}"
		title: "${data.title}"
		backgroundImage: "${data.background_image_url}"
		backBackgroundImage: "#005e8a"
		backTitle: "${data.back_title}"
		backContent: "${data.message}"
		# param for WP8 flip tile (sent when subscriber declare a minimum OS version of 8.0)
		smallBackgroundImage: "${data.small_background_image_url}"
		wideBackgroundImage: "${data.wide_background_image_url}"
		wideBackContent: "${data.message}"
		wideBackBackgroundImage: "#005e8a"

exports['mpns-raw'] =
	enabled: yes
	class: require('./lib/pushservices/mpns').PushServiceMPNS
	type: 'raw'

# Transports: Console, File, Http
#
# Common options:
# level:
#   error: log errors only
#   warn: log also warnings
#   info: log status messages
#   verbose: log event and subscriber creation and deletion
#   silly: log submitted message content
#
# See https://github.com/flatiron/winston#working-with-transports for
# other transport-specific options.
exports['logging'] = [
		transport: 'Console'
		options:
			level: 'verbose'
	]


mongoose = require 'mongoose'
mongoose.connect(configs.mongo.connection_string, { user: configs.mongo.user, pass: configs.mongo.password }, (err) ->

	if err
		console.log("error on mongoose connect: #{err}")
	else
		console.log("mongoose connection succefull")
)

exports.AppConfig = mongoose.model('AppConfig', mongoose.Schema({
	
	server_name: String,
	subscrible_id: String,

	subscrible_channels: String,

	app_id: String,
	app_hash: String,    
	app_user_name: String,
	app_user_email: String,
	app_debug: Boolean,

	createdAt: Date,
	updatedAt: Date,

	deviceId: String

}))