# Mysti.co: Chat with your facebook friends, anonymously

## Concept
Mysti.co is a platform that allows facebook users to talk to each other anonymosly on a an environment that implements chatting features on a facebook wall-like environment. After a user connects with facebook, their wall is created, on which their friends can post messages anonymously. The user can then reply to the posts on their wall with their real name. The user who created the original post can continue posting replies while preserving his anonymity. Only posts and replies posted by someone other than the owner of a wall are anonymous. To post to a wall, the owner of the wall and the user must be friends on facebook. If the owner of a wall wishes to do so, he can hide a post and all its replies from his wall, making it visible and accessible to only himself and the anonymous friend. In this case, the wall post would essentially become a chat between two users, with the anonymous friend of course preserving his anonymity. The wall owner only can also delete a post permanently. No posts or replies can be edited. Replies can only be deleted by deleting the parent post (along with the sibling replies).

On Mysti.co, anonymity means that the identity of a user is not revealed to other users of the platform. There is no anonymity between a user and the mysti.co platform. In other words, Mysti.co knows who created an anonymous post but will not share the identity of the poster with other users. Also, a Mysti.co wall is completely independant from the user's facebook wall, as the Mysti.co wall is internal to the Mysti.co platform.

The core of Mysti.co are the walls of their users. Essentially, a wall is collection of chat discussions that are publicly available to all the wall owner's friends. A wall post with its replies should be thought of as a chat conversation.

The most similar service to Mysti.co the author of this document is aware of is Ask.fm. Mysti.co and Ask.fm have some key differences:
* Mysti.co only allows a user's facebook friends to contact them. This creates a safer environemtand and has some interesting results§, for example if a friend shares information on a user's wall, the user knows that information originates from someone in a specific circle of people, but can't know from whom.
* A wall post on Mysti.co can have more than one replies by both the poster of the original post and the owner of the wall. This feature essentially transforms posts into chat conversations.
* A wall post on Mysti.co can be made private by the wall owner, transforming the publically readable chat into a private conversation with the anonymous user preserving their anonymity.

## Architecture
Mysti.co is a node.js web application that uses express 4 and socket.io, with mongo-db for permanent storage. The express acts a traditional web application backend: it handles the serving of dynamic pages, authenticates with the facebook platform and acts as an intermediary between the client and the mongoDB database (making database queries, validations and authentication before serving data etc).

The socket.io backend lives in the same process as the express backend and offers live broadcasts of notifications, posts and replies to clients. A client that is logged in can optionally authenticate with the socket.io service by passing the user id of the user they would like to authenticate as along with a random server-generated token that is passed in the view template of a logged in user.


