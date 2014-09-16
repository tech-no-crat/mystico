express = require('express')
app = express()
sass = require('node-sass')
session = require('cookie-session')
http = require('http')
request = require('request')
Model = require 'mongo-model'
require 'mongo-model/lib/sync'
Driver = require 'mongo-model/lib/driver'
config = require './config.json'

# Configuration
app.set 'view engine', 'jade'
app.use sass.middleware({
  src: __dirname + '/styles',
  dest: __dirname + '/public',
  debug: false,
  outputStyle: 'compressed'
})
app.use express.static('public')
app.use session keys: ['test key']

Driver.configure
  databses:
    dev:
      name: 'dev'
      host: 'localhost'

# Call sync with a function of stuff you want to do synchronously. Intended for mongo-model operations.
sync = (func) ->
  Fiber ->
    func()
  .run()

class global.User extends Model
  @collection 'users'

app.get '/', (req, res) ->
  if req.session.user
    res.render 'dashboard', {user: req.session.user}
  else
    res.render 'landing'

app.get '/connect', (req, res) ->
  console.log "Redirecting to facebook for authorization code"
  res.redirect "https://www.facebook.com/dialog/oauth?client_id=#{config.fbAppId}&redirect_uri=#{config.fbRedirect}"

app.get '/connect/callback', (req, res) ->
  code = req.query.code
  console.log "Got code #{code}, swapping for token"
  request "https://graph.facebook.com/oauth/access_token?client_id=#{config.fbAppId}&redirect_uri=#{config.fbRedirect}&client_secret=#{config.fbAppSecret}&code=#{code}", (err, resp, body) ->
    try
      # TODO: find a better way to do this
      regexp = /\=([^&]+)/
      match = regexp.exec(body)
      token = match[1]
    catch error
      console.log "Unable to parse token, response was #{body}"
      res.status(500)
      res.send('HTTP 500 - Error parsing facebook token')
      return
    console.log "Got token #{token}, getting user info"
    request "https://graph.facebook.com/me?access_token=#{token}", (err, resp, body) ->
      info = JSON.parse(body)

      # Find or create user
      sync ->
        console.log "Got info for user #{info.id}, finding or creating"
        user = User.first {id: info.id}
        unless user
          user = new User
            id: info.id
            name: info.name
          user.save()
          console.log "User #{info.id} created"
        else
          console.log "User #{info.id} already existed"
        req.session.user = user
        res.redirect '/'

# TODO: When exactly is this route invoked? How should the app behave?
app.get '/connect/failure', (req, res) ->
  res.send('Facebook connect failure')

app.get '/logout', (req, res) ->
  req.session.user = null
  res.redirect '/'

# User profile page
app.get '/u/:id', (req, res) ->
  id = req.params.id
  console.log "Profile for user #{id} requested, looking user id up"
  sync ->
    u = User.first id: id
    console.log "User found"
    if u
      res.render('user', {user: req.session.user, profile: u})
    else
      console.log "User not found (404)"
      res.status(404)
      res.send('User not found')

server = app.listen 1337
