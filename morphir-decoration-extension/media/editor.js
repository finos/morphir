import '../../cli/web/editor-custom-element.js'

const customEdit = document.querySelector('#value-editor');
const valueEditor = document.createElement("value-editor");

customEdit?.appendChild(valueEditor)