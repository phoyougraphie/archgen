// Mesure de l'échelle de chaque objet de la coupe, indépendante du code de dessin : la taille
// vient de la géométrie SVG rendue (getBBox), le sol de la ligne de surface des bandes et du
// dessus des rails. Retourne un bilan JSON. Chargé par test/host/h19.rb et par le banc local.
(function () {
  'use strict';
  var TOL_M = 0.02;
  var svg = document.getElementById('section');
  var s = Number(svg.getAttribute('data-scale'));
  function all(sel) { return Array.prototype.slice.call(svg.querySelectorAll(sel)); }
  // Lignes de surface : polylignes « M x y L x y … » des bandes, de gauche à droite.
  var lines = all('path.s-band').map(function (p) {
    var n = p.getAttribute('d').match(/-?\d+(\.\d+)?(e-?\d+)?/g).map(Number);
    var pts = [];
    for (var i = 0; i + 1 < n.length; i += 2) { pts.push([n[i], n[i + 1]]); }
    return pts;
  });
  function groundY(x) {
    for (var i = 0; i < lines.length; i += 1) {
      var p = lines[i];
      if (x > p[0][0] + 1e-6 && x < p[p.length - 1][0] - 1e-6) {
        for (var k = 0; k + 1 < p.length; k += 1) {
          if (x >= p[k][0] && x <= p[k + 1][0]) {
            return p[k][1] + (p[k + 1][1] - p[k][1]) * (x - p[k][0]) / (p[k + 1][0] - p[k][0]);
          }
        }
      }
    }
    return null;
  }
  var rails = all('[data-rail]').map(function (r) { return { band: r.getAttribute('data-rail'), top: Number(r.getAttribute('data-top')), drawnTop: Number(r.getAttribute('y')) }; });
  var out = [];
  function record(label, expectH, gotH, gapM, extra) {
    var ok = Math.abs(gotH - expectH) <= TOL_M && Math.abs(gapM) <= TOL_M && (!extra || extra.ok);
    out.push({ label: label, expected_m: Math.round(expectH * 1000) / 1000, height_m: Math.round(gotH * 1000) / 1000, gap_m: Math.round(gapM * 1000) / 1000, extra: extra ? extra.text : '', ok: ok });
  }
  all('[data-kind]').forEach(function (g) {
    var b = g.getBBox();
    var ground = groundY(Number(g.getAttribute('data-x')));
    var label = g.getAttribute('data-kind') + '/' + g.getAttribute('data-variant');
    var extra = null;
    if (g.getAttribute('data-kind') === 'tree') {
      var crown = g.querySelector('.s-crown, path.s-tree2');
      var w = crown.getBBox().width / s;
      var want = Number(g.getAttribute('data-crown-m'));
      extra = { ok: Math.abs(w - want) <= TOL_M, text: 'couronne ' + w.toFixed(3) + ' / ' + want.toFixed(3) + ' m' };
    }
    record(label, Number(g.getAttribute('data-height-m')), (ground - b.y) / s, (ground - (b.y + b.height)) / s, extra);
  });
  all('[data-vehicle]').forEach(function (g) {
    var b = g.getBBox();
    var v = g.getAttribute('data-vehicle');
    var band = g.getAttribute('data-on-band');
    var onRails = rails.filter(function (r) { return r.band === band; });
    var ground = v === 'train' && onRails.length ? onRails[0].top : groundY(Number(g.getAttribute('data-x')));
    var want = Number(g.getAttribute('data-w-m'));
    var extra = v === 'bike' ? null : { ok: Math.abs(b.width / s - want) <= TOL_M, text: 'largeur ' + (b.width / s).toFixed(3) + ' / ' + want + ' m' };
    record('véhicule/' + v, Number(g.getAttribute('data-h-m')), (ground - b.y) / s, (ground - (b.y + b.height)) / s, extra);
  });
  rails.forEach(function (r) {
    record('rail/dessus', 0, 0, (r.top - r.drawnTop) / s, null);
  });
  var human = svg.querySelector('[data-human]');
  if (human) {
    var parts = Array.prototype.slice.call(human.querySelectorAll('.s-person'));
    var top = Math.min.apply(null, parts.map(function (p) { return p.getBBox().y; }));
    var bottom = Math.max.apply(null, parts.map(function (p) { var bb = p.getBBox(); return bb.y + bb.height; }));
    var hit = human.querySelector('.s-hit').getBBox();
    record('personnage', 1.75, (bottom - top) / s, (hit.y + hit.height - bottom) / s, null);
  }
  return JSON.stringify({ count: out.length, failures: out.filter(function (o) { return !o.ok; }) });
}());
