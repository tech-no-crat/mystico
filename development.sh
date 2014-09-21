
coffee -wc *.coffee &
coffee --output public -wc client &
supervisor app.js
