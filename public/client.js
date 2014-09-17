function Post(data) {
  self = this;
  this.load(data);
}

Post.prototype.expand = function(event, scope) {
  scope.post.expanded = !scope.post.expanded;
}

Post.prototype.load = function(data) {
  $.each(data, function(attr, val) {
    self[attr] = val;
  });
}

Post.prototype.submitReply = function(event, scope) {
  parent = scope.post.id;
  body = $(this).parent().children("textarea").val();
  $(this).parent().children("textarea").val('');
  $(this).parent().children("textarea").focus();

  localPost = new Post({body: body, parent: parent, createdAt: Date.now(), local: true, replies: []})
  scope.post.replies.push(localPost);

  window.waitingPostReplies += 1;
  $.post("/u/" + profile, {body: body, parent: parent}, function(post) {
     localPost.load(post)
     localPost.local = false;
     window.waitingPostReplies -= 1;
     postsRendered[post.id] = true;
     
     if(window.waitingPostReplies == 0) {
       runWaitingList();
     }
  }, 'json');
}

runWaitingList = function() {
  for(var i=0;i<window.waitingList.length;i++) {
    window.waitingList[i]();
  }
}

waitForPostReplies = function(callback) {
  if(window.waitingPostReplies == 0) {
    callback();
  } else {
    window.waitingList.push(callback);
  }
}

$(document).ready(function() {
  $("#connect").click(function() {
    window.location.replace("/connect")
  });

  $("#create-post-body").focus(function() {
    $("#create-post").addClass("open");
  });

  window.profile = $("#profile-id").val();
  window.postsRendered = {}
  window.waitingPostReplies = 0
  window.waitingList = []

  rivets.formatters.length = function(value) {
    var _ref;
    if ((_ref = typeof value !== "undefined" && value !== null ? value.length : void 0) != null) {
        return _ref;
    } else {
        return 0;
    };
  }

  rivets.formatters.exists = function(thing) {
    return (thing!=null && thing!=undefined);
  }

  rivets.formatters.unixTime = function(time) {
    return parseInt(time)/1000;
  }

  rivets.formatters.hasNone = function(array) {
    return !(array && array.length > 0)
  }

  rivets.formatters.profileLink = function(user) {
    if(user) {
      return "/u/" + user.id;
    } else return null;
  }

  var wall = {posts: [], loaded: false};
  rivets.bind($("#wall"), {
    profile: wall
  });

  loadWall = function() {
    $.getJSON("/u/" + profile + "/wall", function(data) {
      wall.loaded = true;
      posts = []
      for(var i=0;i<data.length;i++) {
        posts.push(new Post(data[i]));
      }
      wall.posts = posts;
    });
  }

  loadWall();

  $("#submit-post").click(function() {
    var body = $("#create-post-body").val();
    $("#create-post-body").val('');
    $("#create-post").removeClass('open');
    $.post("/u/" + profile, {body: body})
  });

  window.submitOnEnter = function() {
    e = window.event;
    console.log(e.keyCode);
    if(e.keyCode == 13) {
      $(e.target).parent().children("button").click();
      e.preventDefault();
      return false;
    }
  }

  socket = io.connect('http://localhost:1337')
  socket.on('connect', function() {
    socket.emit('join room', profile);
  });

  socket.on('post', function(post) {
    console.log('Got post ' + post);
    waitForPostReplies(function() {
      if(postsRendered[post.id]) {
        console.log("Post is already rendered, ignoring");
        return;
      }

      if(post.parent == 0) {
        wall.posts.unshift(new Post(post))
        console.log("Rendered post");
      } else {
        //Post is a reply, find the parent post first
        for(var i=0;i<wall.posts.length;i++) {
          if(wall.posts[i].id == post.parent) {
            wall.posts[i].replies.push(new Post(post));
          }
        }
      }

      postsRendered[post.id] = true;
    });
  });
});
