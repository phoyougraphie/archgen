// Compose dans la vraie page une coupe qui porte chaque variante de chaque élément du catalogue,
// par les contrôles du panneau (clics, saisies), une action toutes les 250 ms. Durée : environ 12 s.
// Chargé par test/host/h19.rb et par le banc local ; la mesure se fait ensuite avec road_scale_probe.js.
(function () {
  'use strict';
  function q(sel) { return document.querySelector(sel); }
  function fire(el, value) {
    el.value = value;
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
  }
  function width(band, value) { return function () { fire(q('[aria-label="Largeur de la bande ' + band + ', en mètres"]'), value); }; }
  function pick(band) { return function () { q('#bands > li[data-i="' + (band - 1) + '"]').click(); }; }
  function add(band, kind) {
    return function () {
      fire(q('[aria-label="Élément à ajouter sur la bande ' + band + '"]'), kind);
      q('[aria-label="Ajouter cet élément sur la bande ' + band + '"]').click();
    };
  }
  function variant(label, index, value) { return function () { fire(q('[aria-label="' + label + ' ' + index + ', variante"]'), value); }; }
  function height(label, index, value) { return function () { fire(q('[aria-label="' + label + ' ' + index + ', hauteur en mètres"]'), value); }; }
  var steps = [
    function () { q('[data-preset="ville"]').click(); },
    // Rue de ville : trottoir, stationnement, voie, voie, trottoir. Voies à 3,5 m pour voir un bus.
    width(1, '12'), width(2, '5,5'), width(3, '3,5'), width(4, '3,5'), width(5, '12'),
    pick(1), add(1, 'lamp'), add(1, 'lamp'), add(1, 'lamp'), add(1, 'lamp'),
    variant('Lampadaire', 1, 'single'), variant('Lampadaire', 2, 'double'), variant('Lampadaire', 3, 'ped'), variant('Lampadaire', 4, 'heritage'), variant('Lampadaire', 5, 'high'),
    height('Lampadaire', 3, '4'), height('Lampadaire', 4, '5'), height('Lampadaire', 5, '20'),
    pick(2), add(2, 'hedge'), add(2, 'fence'), add(2, 'fence'), add(2, 'guard'), add(2, 'guard'),
    variant('Barrière', 2, 'mesh'), variant('Glissière', 4, 'guard'), variant('Glissière', 5, 'concrete'),
    pick(5), add(5, 'tree'), add(5, 'tree'), add(5, 'tree'), add(5, 'bollard'), add(5, 'pole'),
    variant('Arbre', 2, 'columnar'), variant('Arbre', 3, 'wide'), variant('Arbre', 4, 'conifer'),
    height('Arbre', 2, '14'), height('Arbre', 3, '16'), height('Arbre', 4, '11')
  ];
  var i = 0;
  (function next() {
    if (i >= steps.length) { window.archgenCatalogueReady = true; return; }
    try { steps[i](); } catch (e) { window.archgenCatalogueError = 'étape ' + i + ' : ' + e.message; }
    i += 1;
    setTimeout(next, 250);
  }());
  window.archgenCatalogueReady = false;
  return steps.length;
}());
