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
bodyParser = require 'body-parser'

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
app.use bodyParser.urlencoded extended: true

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

sync ->
  class global.User extends Model
    @collection 'users'

    constructor: (args...) ->
      @postsCount = 0
      super args...

    posts: ->
      console.log "Looking for posts to user #{@id}"
      (Post.find profile_ref: @id, parent_ref: 0).all()

  class global.Post extends Model
    @collection 'posts'

    constructor: (args...) ->
      @repliesCount = 0
      super args...

    replies: ->
      console.log "Looking for replies to post #{@_id}"
      (Post.find parent_ref: @_id).all()

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

# Post to a user's wall
app.post '/u/:id', (req, res) ->
  user = req.session.user
  unless user
    res.status 401
    res.send "HTTP 401 - You are not logged in"
    return

  profile_id = req.params.id
  sync ->
    post = new Post
      body: req.body.body
      parent_ref: req.body.parent || 0
      profile_ref: profile_id
      user_ref: user.id
      created_at: Date.now()
      anonymous: true

    unless User.exists(id: profile_id)
      res.status 404
      res.send "User profile not found"
    else
      post.save()
      console.log "Wall post from user #{user.id} to #{post.profile_ref}, parent #{post.parent_ref} saved"

anonymizePosts = (posts) ->
  res = []
  for post in posts
    res.push
      id: post._id
      body: post.body
      createdAt: parseInt(post.created_at)/1000
      replies: post.replies()
  return res

app.get '/u/:id/wall', (req, res) ->
  id = req.params.id
  sync ->
    u = User.first id: id
    if u
      res.send JSON.stringify(anonymizePosts(u.posts()))
    else
      res.status 404
      res.send "HTTP 404 - User not found"

server = app.listen 1337
