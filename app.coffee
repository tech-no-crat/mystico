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

authTokens = {}

sync ->
  class global.User extends Model
    @collection 'users'

    constructor: (args...) ->
      @postsCount = 0
      super args...

    postsFor: (role, user_id, since = 0) ->
      user_id ||= 0
      if role not in ['owner', 'friend', 'guest']
        role = 'guest'
        console.log "Invalid role, getting posts for guest"

      visibilities = ['public']
      if role == 'friend' or role == 'owner'
        visibilities.push 'friends'
      if role == 'owner'
        visibilities.push 'private'

      console.log "Looking for posts to user #{@id} since #{since}, visibilites: #{visibilities}, user_id: #{user_id}"
      (Post.find profile_ref: @id, parent_ref: 0, $or: [{visibility: {'$in': visibilities}}, {user_ref: user_id}], created_at: {'$gt': parseInt(since)}).sort(created_at: -1).all()

    clientObject: ->
      id: @id
      name: @name
    
    notifications: ->
      (Notification.find user_ref: @id).sort(createdAt: -1).all()

  class global.Post extends Model
    @collection 'posts'

    constructor: (args...) ->
      @repliesCount = 0
      super args...

    replies: ->
      console.log "Looking for replies to post #{@_id}"
      (Post.find parent_ref: @_id).all()

    poster: ->
      User.first id: @user_ref

  class global.Notification extends Model
    @collection 'notifications'

    clientObj: ->
      post = @post()
      post = {} unless post
      obj = {
        id: @_id
        user: @user_ref
        read: @read
        title: post.body
        post: post._id
        createdAt: @createdAt
      }

    post: ->
      Post.first _id: @post_ref

app.get '/', (req, res) ->
  if req.session.user
    # Load user again in case something has changed
    sync ->
      user = User.first id: req.session.user.id
      res.render 'dashboard', {user: req.session.user, token: req.session.token}
  else
    res.render 'landing'

app.get '/connect', (req, res) ->
  console.log "Redirecting to facebook for authorization code"
  res.redirect "https://www.facebook.com/dialog/oauth?client_id=#{config.fbAppId}&redirect_uri=#{config.fbRedirect}&scope=user_friends,email"

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
    request "https://graph.facebook.com/me?access_token=#{token}&fields=id,name,friends,email", (err, resp, body) ->
      info = JSON.parse(body)
      friends = info.friends.data

      # Find or create user
      sync ->
        console.log "Got info for user #{info.id}, finding or creating"
        user = User.first {id: info.id}
        unless user
          user = new User
            id: info.id
            name: info.name
            friends: friends
          user.save()

          # Add user.id to friends' friendlists and (maybe?) send them a notification that their friend has joined
          for friend_id in user.friends
            friend = User.first(id: friend_id)
            if friend and !(user.id in friend.friends)
              friend.friends.push(user.clientObject())
              #TODO: Add a notification here
              friend.save()
              
          console.log "User #{info.id} created"
        else
          user.friends = friends
          user.save()
          console.log "User #{info.id} already existed"
        
        # Generate and remember a random unique auth token
        token = null
        token = Math.random().toString(36).substring(7) while !token or authTokens.token
        authTokens[token] = user.id
        req.session.token = token

        req.session.user = user
        res.redirect '/'

# TODO: When exactly is this route invoked? How should the app behave?
app.get '/connect/failure', (req, res) ->
  res.send('Facebook connect failure')

app.get '/logout', (req, res) ->
  req.session.user = null
  authTokens[req.session.token] = null
  res.redirect '/'

# User profile page
app.get '/u/:id', (req, res) ->
  id = req.params.id
  console.log "Profile for user #{id} requested, looking user id up"
  sync ->
    u = User.first id: id
    if u
      console.log "User found: #{u.name}"
      res.render('user', {user: req.session.user, profile: u, token: req.session.token})
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
    # All posts posted are anonymous for now, except for those posted on one's own wall
    post = new Post
      body: req.body.body
      parent_ref: req.body.parent || 0
      profile_ref: profile_id
      user_ref: user.id
      created_at: Date.now()
      anonymous: (user.id != profile_id)
      visibility: req.body.visibility || 'public'

    if post.profile_ref == user.id and !post.parent_ref
        res.status 403
        res.send "HTTP 403 - You can not post on your own wall"
        return
    if req.body.parent
      parent = Post.first _id: req.body.parent
      unless parent
        res.status 404
        res.send "Parent post not found"
        return
      else
        post.visibility = parent.visibility
    
    if not User.exists(id: profile_id)
      res.status 404
      res.send "User profile not found"
    else
      console.log post
      post.save()
      io.to("#{post.profile_ref}/owners").emit('post', anonymizePost(post, null))
      if post.visbility in ['public', 'friends']
        io.to("#{post.profile_ref}/friends").emit('post', anonymizePost(post, null))
      if post.visibility == 'public'
        io.to("#{post.profile_ref}/guests").emit('post', anonymizePost(post, null))

      if post.profile_ref == user.id
        notification_rec = parent.user_ref
      else
        notification_rec = post.profile_ref

      notification = new Notification
        user_ref: notification_rec
        post_ref: post._id
        read: false
        createdAt: Date.now()
      notification.save()
      io.to("#{notification_rec}/notifications").emit("notification", notification.clientObj())

      console.log "Saved notification for user #{notification.user_ref} and post #{notification.post_ref}"

      console.log "Wall post from user #{user.id} to #{post.profile_ref}, parent #{post.parent_ref} saved"
      res.send anonymizePost(post, user)

# Users should be able to edit the visibility of a post only
app.post '/posts/:id/update', (req, res) ->
  user = req.session.user
  unless user
    res.status 401
    res.send "HTTP 401 - You are not logged in"
    return
  
  sync ->
    post = Post.first _id: req.params.id
    if not post
      res.status 404
      res.send "HTTP 404 - Post not found"
    else if post.parent_ref != 0
      res.status 403
      res.send "HTTP 403 - Can not update post replies. Try updating the original post"
    else if post.profile_ref != user.id
      res.status 401
      res.send "HTTP 401 - Unauthorized"
    else
      post.visibility = req.body.post.visibility
      post.save()
      console.log "Post #{post._id} updated!"
      res.status 200
      res.send "OK"


app.post '/posts/:id/delete', (req, res) ->
  user = req.session.user
  unless user
    res.status 401
    res.send "HTTP 401 - You are not logged in"
    return
  
  sync ->
    post = Post.first _id: req.params.id
    if not post
      res.status 404
      res.send "HTTP 404 - Post not found"
    else if post.parent_ref != 0
      res.status 403
      res.send "HTTP 403 - Can not delete post replies. Try deleting the original post"
    else if post.profile_ref != user.id
      res.status 401
      res.send "HTTP 401 - Unauthorized"
    else
      console.log "Deleting post #{post.id}"
      post.delete()
      res.status 200
      res.send "OK"

anonymizePost = (post, user) ->
  anonymizePosts([post], user)[0]

#TODO: Test this method to ensure the anonymity of users is fully preserved
anonymizePosts = (posts, user) ->
  res = []
  if user
    user_id = user.id
  else
    user_id = null
  for post in posts
    p =
      id: post._id
      parent: post.parent_ref
      body: post.body
      createdAt: post.created_at
      replies: anonymizePosts(post.replies(), user)
      anonymous: post.anonymous
      own: (user_id == post.user_ref)
      visibility: post.visibility
    p.can_administrate = (user_id == post.profile_ref)
    # Only include poster if it's the profile owner, the currently logged in user or if the post is not anonymous
    if post.user_ref == post.profile_ref or (user_id == post.user_ref) or !post.anonymous
      p.poster = post.poster().clientObject()

    res.push p
  return res

app.get '/u/:id/notifications', (req, res) ->
  user = req.session.user
  unless user
    res.status 401
    res.send "HTTP 401 - You are not logged in"
    return
  unless user.id == req.params.id
    res.status 403
    res.send "HTTP 403 - Unauthorized"
    return

  sync ->
    user = User.first id: user.id
    notifications = user.notifications()
    res.send notifications.map((x) -> x.clientObj())

app.get '/u/:id/wall', (req, res) ->
  profile_id = req.params.id
  since = req.query.since || 0
  if req.session.user
    user_id = req.session.user.id
  else
    user_id = null

  sync ->
    if user_id
      user = User.first id: user_id
    else
      user = null
    profile = User.first id: profile_id
    unless profile
      res.status 404
      res.send "HTTP 404 - User not found"
      return

    if user and user.id == profile.id
      role = 'owner'
    else if user and user.id in profile.friends.map((x) -> x.id)
      role = 'friend'
    else
      role = 'guest'

    if profile
      res.send anonymizePosts(profile.postsFor(role, user_id, since), req.session.user)

server = app.listen 1337

authenticateSocket = (socket, user_id, token) ->
  if authTokens[token] != user_id
    socket.emit 'auth error', {message: 'Invalid token'}
    return null

  user = User.first id: user_id
  unless user
    socket.emit 'auth error', {message: 'User not found'}
    return null
  return user


io = require('socket.io')(server)

io.sockets.on 'connection', (socket) ->
  socket.on 'join wall room', (data) ->
    console.log "User wants to join wall room: #{data}"
    sync ->
      profile_id = data.profile
      profile = User.first(id: profile_id)
      #TODO: Emit an error if the profile doesn't exist
      return unless profile

      role = 'guests'
      if data.user
        token = data.token
        user_id = data.user

        user = authenticateSocket(socket, user_id, token)
        return unless user

        if profile.id == user.id
          role = 'owners'
        else if user.id in profile.friends.map((x) -> x.id)
          role = 'friends'

      room = "#{profile.id}/#{role}"
      socket.join room
      socket.emit "welcome room", {room: room}
      console.log "Client joined room #{room}"

  socket.on 'join notifications room', (data) ->
    token = data.token
    user_id = data.user
    sync ->
      user = authenticateSocket(socket, user_id, token)
      return unless user

      room = "#{user.id}/notifications"
      socket.join room
      socket.emit "welcome room", {room: room}
      console.log "Client joined room #{room}"

  socket.on 'consume notification', (data) ->
    user_id = data.user
    token = data.token
    notification_id = data.notification

    sync ->
      user = authenticateSocket(socket, user_id, token)
      return unless user

      notification = Notification.first _id: notification_id
      if user.id == notification.user_ref
        notification.read = true
        notification.save()
        console.log "Notification #{notification._id} read"
      #TODO: else emit error
