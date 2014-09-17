function Post(data) {
  self = this;
  $.each(data, function(attr, val) {
    self[attr] = val;
  });
}

Post.prototype.expand = function(event, scope) {
  scope.post.expanded = !scope.post.expanded;
}

Post.prototype.submitReply = function(event, scope) {
  parent = scope.post.id;
  body = $(this).parent().children("textarea").val();
  $.post("/u/" + profile, {body: body, parent: parent});

  scope.post.replies.push(new Post({body: body, parent: parent, createdAt: Date.now(), local: true}));
}

$(document).ready(function() {
  $("#connect").click(function() {
    window.location.replace("/connect")
  });

  $("#post-body").focus(function() {
    $("#create-post").addClass("open");
  });

  window.profile = $("#profile-id").val();

  // Mysterious thing copied from the internet. Makes array | length work in rv-if statements.
  rivets.formatters.length = function(value) {
    var _ref;
    if ((_ref = typeof value !== "undefined" && value !== null ? value.length : void 0) != null) {
        return _ref;
    } else {
        return 0;
    };
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

  window.wall = wall

  loadWall();

  $("#submit-post").click(function() {
    var body = $("#post-body").val();
    wall.posts.push(new Post({body: body, createdAt: Date.now(), local: true}))
    $.post("/u/" + profile, {body: body})
  });
});
