// Ruby appelle ce nom fixe avec une chaîne JSON ; le texte passe par textContent.
function archgenShow(json) {
  var data = JSON.parse(json);
  var list = document.getElementById('report');
  list.textContent = '';
  Object.keys(data).forEach(function (key) {
    var term = document.createElement('dt');
    term.textContent = key;
    var value = document.createElement('dd');
    value.textContent = String(data[key]);
    list.appendChild(term);
    list.appendChild(value);
  });
}

if (window.sketchup) {
  window.sketchup.archgen_ready();
}
