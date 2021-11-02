'use strict';

require('./assets/tree-view.css')
require('./index.html');
var elm = require('./Main.elm');

var app = elm.Elm.Main.init({
  node: document.getElementById('main')
});