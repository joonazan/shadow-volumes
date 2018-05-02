'use strict';

require('./index.html');

var Elm = require('./src/Main.elm');

var app = Elm.Main.embed(document.getElementById("main"));
