
# Base class for models used by Rivets.js
class ClientModel
  constructor: (data) ->
    @load data

  load: (data) ->
    self = this
    console.log data
    $.each data, (attr, val) ->
      self[attr] = val
      return true

class Post extends ClientModel
  constructor: (data) ->
    @visibility = "public"
    super data

  # TODO: There must be a way to pass arguments to rivets event handlers, so the next three functions are not required and setVisibility could be called directly
  setVisibilityPublic: (event, scope) ->
    scope.post.setVisibility "public"

  setVisibilityFriends: (event, scope) ->
    scope.post.setVisibility "friends"

  setVisibilityPrivate :(event, scope) ->
    scope.post.setVisibility "private"

  setVisibility: (visibility) ->
    @visibility = visibility
  
    #TODO: Handle errors
    $.post "/posts/" + @id + "/update",
      post:
        visibility: @visibility

  expand: (event, scope) ->
    scope.post.expanded = not scope.post.expanded

  toggleVisibilitySettings: (event, scope) ->
    scope.post.showVisibilitySettings = not scope.post.showVisibilitySettings

  submitReply: (event, scope) ->
    parent = scope.post.id
    body = $(this).parent().children("textarea").val()
    $(this).parent().children("textarea").val ""
    $(this).parent().children("textarea").focus()
    sendAndRenderPost
      body: body
      parent: parent

  delete: (event, scope) ->
    post = scope.post
    displayDialog 'Θέλεις σίγουρα να διαγράψεις αυτό το post;', 'Διαγραφή', 'Όχι', 'dangerous', ->
      console.log("Deleting post #{post.id}")
      posts = window.wall.posts

      # Delete locally
      for i in [0...posts.length]
        if(posts[i].id == post.id)
          posts.splice i, 1
    
      $.post("/posts/#{post.id}/delete")
    , ->

class Notification extends ClientModel
  constructor: (data) ->
    super data

  markAsRead: ->
    console.log "Marking as read: " + @id
    if window.user.id
      window.socket.emit "consume notification",
        user: window.user.id
        token: window.user.token
        notification: @id

sendAndRenderPost = (data) ->
  localPost = new Post(data)
  localPost.local = true
  localPost.createdAt = Date.now()
  localPost.replies = []
  if localPost.parent
    i = 0

    while i < window.wall.posts.length
      p = window.wall.posts[i]
      if localPost.parent is p.id
        p.replies.push localPost
      i++
  else
    window.wall.posts.unshift localPost

  window.waitingPostReplies += 1
  $.post "/u/" + profile,
    body: localPost.body
    parent: localPost.parent
  , ((post) ->
    localPost.load post
    localPost.poster = post.poster
    localPost.local = false
    window.waitingPostReplies -= 1
    postsRendered[post.id] = true
    runWaitingList() if window.waitingPostReplies is 0
  ), "json"

runWaitingList = ->
  i = 0
  while i < window.waitingList.length
    window.waitingList[i]()
    i++
  window.waitingList = []

waitForPostReplies = (callback) ->
  if window.waitingPostReplies is 0
    callback()
  else
    window.waitingList.push callback
  return

# TODO: Rewrite this function
displayDialog = (body, acceptText, declineText, cl, acceptCallback, declineCallback) ->
  $("#dialog-body").html body
  $("#dialog button#accept").html acceptText
  $("#dialog button#decline").html declineText
  $("#dialog").addClass cl
  $("#dialog").show 200
  $("#dialog button#accept").click ->
    $("#dialog button").off()
    $("#dialog").hide 200, ->
      $("#dialog").removeClass cl

    acceptCallback()

  $("#dialog button#decline").click ->
    $("#dialog button").off()
    $("#dialog").hide 200, ->
      $("#dialog").removeClass cl

    declineCallback()

# A few handy rivets formatters
rivets.formatters.length = (value) ->
  value?.length ? 0

rivets.formatters.eq = (x, y) ->
  x is y

rivets.formatters.exists = (thing) ->
  thing? and thing?

rivets.formatters.unixTime = (time) ->
  parseInt(time) / 1000

rivets.formatters.hasNone = (array) ->
  not (array and array.length > 0)

rivets.formatters.profileLink = (user) ->
  if user
    "/u/" + user.id
  else
    null

# Loads wall posts and notifications
load = ->
  if window.profile
    $.getJSON "/u/" + window.profile + "/wall", (data) ->
      wall.loaded = true
      posts = []
      i = 0

      while i < data.length
        posts.push new Post(data[i])
        i++
      window.wall.posts = posts

  if window.user.id
    $.getJSON "/u/" + window.user.id + "/notifications", (data) ->
      for notification in data
        window.user.notifications.push new Notification(notification)
        window.user.unreadNotifications += 1 unless notification.read

$(document).ready ->
  # The ID of the profile to be rendered, if we're in the profile page
  window.profile = $("#profile-id").val()

  # A hash used for quick lookups, to see if a post is already rendered or not:
  window.postsRendered = {}

  # How many server confirmations of post creates we are waiting for
  window.waitingPostReplies = 0

  # A list of functions to be executed after all server confirmations have been received and we know the post IDs of all the post rendered locally
  window.waitingList = []

  window.user =
    notifications: []
    unreadNotifications: 0
    toggleNotifications: (event, scope) ->
      console.log "toggle"
      scope.user.showNotifications = not scope.user.showNotifications

      i = 0
      while i < scope.user.notifications.length
        notification = scope.user.notifications[i]
        notification.markAsRead()
        i++
      scope.user.unreadNotifications = 0

  window.wall =
    posts: []
    loaded: false

  if $("#user-id").length
    window.user.id = $("#user-id").val()
    window.user.token = $("#token").val()
    console.log "Logged in as " + user.id + ", token " + user.token
  else
    console.log "Not logged in"

  # Rivets data bindings
  window.tryThis = rivets.bind $("#wall"),
    profile: wall

  rivets.bind $("#notifications"),
    user: window.user

  # Landing page button
  $("#connect").click ->
    window.location.replace "/connect"

  $("#create-post-body").focus ->
    $("#create-post").addClass "open"

  $("#submit-post").click ->
    body = $("#create-post-body").val()
    $("#create-post-body").val ""
    $("#create-post").removeClass "open"
    sendAndRenderPost
      body: body
      parent: null


  window.submitOnEnter = ->
    e = window.event
    if e.keyCode is 13
      $(e.target).parent().children("button").click()
      e.preventDefault()
      false

  # Load wall and notifications
  load()

  # Socket.io stuff

  # TODO: Figure out the address to connect to somehow
  window.socket = io.connect("http://178.62.129.206:1337")

  socket.on "connect", ->
    data = profile: profile
    if window.user.id
      data.user = user.id
      data.token = user.token
    socket.emit "join wall room", data
    socket.emit "join notifications room", {user: user.id, token: user.token}

  socket.on "post", (post) ->
    waitForPostReplies ->
      return  if postsRendered[post.id]
      if post.parent is 0
        wall.posts.unshift new Post(post)
      else
        
        #Post is a reply, find the parent post first
        i = 0

        while i < wall.posts.length
          wall.posts[i].replies.push new Post(post)  if wall.posts[i].id is post.parent
          i++
      postsRendered[post.id] = true

  socket.on "notification", (data) ->
    console.log "New notification:"
    console.log data
    window.user.notifications.unshift new Notification(data)
    window.user.unreadNotifications += 1 unless data.read

  socket.on "welcome room", (data) ->
    console.log "Joined room " + data.room

  socket.on "auth error", (data) ->
    console.log "Socket.io authentication error: " + data.message

