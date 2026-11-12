// Panneau de réseau de voies (AG-048) : ajoute les voies tracées, règle les carrefours, montre le
// plan. Toute décision vient de Ruby ; le texte passe par textContent.
(function () {
  'use strict';

  var SVG = 'http://www.w3.org/2000/svg';
  var TYPES = [['simple', 'Simple'], ['signals', 'À feux'], ['roundabout', 'Giratoire'], ['double_roundabout', 'Double giratoire'], ['level_crossing', 'Passage à niveau'], ['bridge', 'Pont']];
  var KINDS = [['beam', 'Poutre'], ['arch', 'Arc'], ['vault', 'Voûte']];
  var state = { counter: 0, mode: 'trace', writes: false, digest: null, busy: false, network: null, roads: [], settings: [], trace: null, notice: null, lastJunctions: [] };

  function byId(id) { return document.getElementById(id); }
  var el = {
    title: byId('title'), status: byId('status'), hint: byId('trace-hint'), preset: byId('n-preset'), axis: byId('n-axis'),
    radius: byId('n-radius'), add: byId('n-add'), resume: byId('n-resume'), addBox: byId('add-box'), roads: byId('roads'),
    junctions: byId('junctions'), metrics: byId('metrics'), diag: byId('diag'), create: byId('n-create'), reload: byId('n-reload'),
    regenerate: byId('n-regenerate'), clear: byId('n-clear'), plan: byId('plan')
  };

  function send(action, payload) {
    state.counter += 1;
    state.busy = action === 'create' || action === 'regenerate';
    updateButtons();
    window.sketchup.archgen_network(JSON.stringify({ v: 1, request_id: 'n' + state.counter, action: action, payload: payload || {} }));
  }

  function decimal(text) {
    var t = String(text).trim().replace(',', '.');
    if (!/^-?\d+(\.\d+)?$/.test(t)) { return null; }
    return parseFloat(t);
  }

  function node(tag, attrs, parent, text) {
    var n = document.createElement(tag);
    Object.keys(attrs || {}).forEach(function (k) { n.setAttribute(k, attrs[k]); });
    if (text !== undefined) { n.textContent = text; }
    if (parent) { parent.appendChild(n); }
    return n;
  }

  function svg(tag, attrs, parent) {
    var n = document.createElementNS(SVG, tag);
    Object.keys(attrs).forEach(function (k) { n.setAttribute(k, attrs[k]); });
    parent.appendChild(n);
    return n;
  }

  function messages(list) { return (list || []).map(function (d) { return d.message; }); }

  window.archgenNetworkReceive = function (json) {
    var r = typeof json === 'string' ? JSON.parse(json) : json;
    state.busy = false;
    if (!r.ok) {
      el.status.textContent = messages(r.diagnostics).join(' ') || 'Refusé';
      updateButtons();
      return;
    }
    var res = r.result || {};
    if (res.version) { start(res); return; }
    if (res.created) { state.notice = 'Réseau créé, révision ' + res.revision + '.'; }
    if (res.regenerated) { state.notice = 'Réseau remplacé, révision ' + res.revision + '.'; }
    if (res.revision && !res.regenerated && !res.created) { state.notice = 'Réseau chargé, révision ' + res.revision + '.'; }
    if (res.state) { applyState(res.state); }
    if ('network' in res) { showNetwork(res.network); } else if (res.created) { showNetwork(null); }
    if (res.trace) { state.trace = res.trace; showTrace(); }
    el.status.textContent = state.notice || (state.network && state.network.ok ? 'Réseau accepté' : 'Prêt');
    updateButtons();
  };

  window.archgenNetworkTrace = function (trace) {
    state.trace = typeof trace === 'string' ? JSON.parse(trace) : trace;
    state.notice = null;
    showTrace();
    updateButtons();
  };
  window.archgenNetworkTool = function (active) { el.resume.hidden = active || state.mode !== 'trace'; };
  window.archgenNetworkRestart = function () { send('init', {}); };

  function start(res) {
    state.mode = res.mode;
    state.writes = res.writes;
    el.preset.textContent = '';
    var names = {};
    res.presets.forEach(function (p) { names[p.id] = p.name; });
    res.families.forEach(function (f) {
      var group = node('optgroup', { label: f.label }, el.preset);
      f.ids.forEach(function (id) { node('option', { value: id }, group, names[id]); });
    });
    el.preset.value = 'ville';
    el.radius.value = String(res.default_radius_m).replace('.', ',');
    state.trace = res.trace;
    var edit = state.mode === 'edit';
    el.title.textContent = edit ? 'Modifier le réseau sélectionné' : 'Tracer un réseau de voies';
    el.addBox.hidden = edit;
    el.create.hidden = edit;
    el.reload.hidden = !edit;
    el.regenerate.hidden = !edit;
    el.resume.hidden = res.tool_active || edit;
    applyState(res.state);
    showNetwork(null);
    showTrace();
    el.status.textContent = edit ? 'Chargement de la sélection…' : 'Tracez une voie dans la vue';
    if (edit) { send('load_selection', {}); } else if (state.roads.length) { send('preview', {}); }
    updateButtons();
  }

  function applyState(s) {
    state.roads = s.roads;
    state.settings = s.junctions;
    renderRoads();
  }

  function showTrace() {
    var t = state.trace || { points: 0, finished: false };
    if (state.mode === 'edit') { el.hint.textContent = ''; return; }
    if (t.finished) {
      el.hint.textContent = 'Tracé de ' + String(t.length_m).replace('.', ',') + ' m prêt : choisissez son type, puis ajoutez-le.';
    } else if (t.points > 0) {
      el.hint.textContent = 'Tracé en cours : double-clic ou Échap pour le terminer.';
    } else {
      el.hint.textContent = state.roads.length ? 'Tracez la voie suivante dans la vue.' : 'Tracez la première voie dans la vue.';
    }
  }

  function renderRoads() {
    el.roads.textContent = '';
    if (!state.roads.length) { node('li', {}, el.roads, 'Aucune voie.'); return; }
    state.roads.forEach(function (r, i) {
      var li = node('li', { 'class': 'net-road' }, el.roads);
      node('span', {}, li, r.id + ' : ' + (r.name || 'Coupe composée'));
      var b = node('button', { type: 'button', 'aria-label': 'Retirer la voie ' + r.id }, li, '×');
      b.disabled = state.mode === 'edit' && i === 0;
      b.addEventListener('click', function () { send('remove_road', { id: r.id }); });
    });
  }

  function setting(id) {
    return state.settings.filter(function (s) { return s.id === id; })[0] || { id: id };
  }

  function numberField(parent, label, value, onValue) {
    var wrap = node('label', {}, parent, label);
    var input = node('input', { inputmode: 'decimal', 'aria-label': label }, wrap);
    input.value = value === undefined || value === null ? '' : String(value).replace('.', ',');
    input.addEventListener('change', function () {
      var t = input.value.trim();
      var v = t === '' ? null : decimal(t);
      if (t !== '' && v === null) { el.status.textContent = 'Saisissez un nombre : ' + label + '.'; return; }
      onValue(v);
    });
  }

  function renderJunctions(list) {
    el.junctions.textContent = '';
    if (!list || !list.length) { node('li', {}, el.junctions, 'Aucun carrefour.'); return; }
    list.forEach(function (j) {
      var s = setting(j.id);
      var li = node('li', { 'class': 'net-junction' }, el.junctions);
      node('div', {}, li, j.id + ' : ' + j.arms + ' branches');
      var type = node('select', { 'aria-label': 'Type du carrefour ' + j.id }, li);
      TYPES.forEach(function (t) { node('option', { value: t[0] }, type, t[1]); });
      type.value = s.type || j.type || 'simple';
      var fields = node('div', { 'class': 'net-fields' }, li);
      var draft = JSON.parse(JSON.stringify(s));
      var apply = function () {
        var out = { id: j.id, type: type.value };
        ['corner_radius_m', 'outer_radius_m', 'ring_width_m', 'pair', 'ramp_grade_percent', 'bridge_kind', 'over', 'clearance_m', 'crossing_studs'].forEach(function (k) {
          if (draft[k] !== undefined && draft[k] !== null && draft[k] !== '') { out[k] = draft[k]; }
        });
        if (out.type !== 'roundabout' && out.type !== 'double_roundabout') { delete out.outer_radius_m; delete out.ring_width_m; }
        if (out.type !== 'double_roundabout') { delete out.pair; }
        var ramped = out.type === 'level_crossing' || out.type === 'bridge';
        if (!ramped) { delete out.ramp_grade_percent; } else { delete out.corner_radius_m; }
        if (out.type !== 'bridge') { delete out.bridge_kind; delete out.over; delete out.clearance_m; }
        if (out.type !== 'signals' || !out.crossing_studs) { delete out.crossing_studs; }
        state.notice = null;
        send('set_junction', { junction: out });
      };
      type.addEventListener('change', apply);
      if (type.value === 'bridge') {
        // Pont (AG-059) : genre, voie portée (entre deux routes), hauteur libre, pente des rampes.
        var kindWrap = node('label', {}, fields, 'Genre');
        var kind = node('select', { 'aria-label': 'Genre du pont ' + j.id }, kindWrap);
        KINDS.forEach(function (k) { node('option', { value: k[0] }, kind, k[1]); });
        kind.value = draft.bridge_kind || j.bridge_kind || 'beam';
        kind.addEventListener('change', function () { draft.bridge_kind = kind.value; apply(); });
        var overWrap = node('label', {}, fields, 'Voie portée');
        var over = node('select', { 'aria-label': 'Voie portée par le pont ' + j.id }, overWrap);
        node('option', { value: '' }, over, 'selon les voies');
        j.id.split('+').forEach(function (part) { var id = part.split('@')[0]; node('option', { value: id }, over, id); });
        over.value = draft.over || '';
        over.addEventListener('change', function () { draft.over = over.value || null; apply(); });
        numberField(fields, 'Hauteur libre, m', draft.clearance_m, function (v) { draft.clearance_m = v; apply(); });
        numberField(fields, 'Pente des rampes, %', draft.ramp_grade_percent, function (v) { draft.ramp_grade_percent = v; apply(); });
      } else if (type.value === 'level_crossing') {
        numberField(fields, 'Pente des rampes, %', draft.ramp_grade_percent, function (v) { draft.ramp_grade_percent = v; apply(); });
      } else {
        numberField(fields, 'Rayon des bordures, m', draft.corner_radius_m, function (v) { draft.corner_radius_m = v; apply(); });
      }
      if (type.value === 'signals') {
        // Clous de passage piéton (D-10, ADR-42).
        var studWrap = node('label', { 'class': 'net-check' }, fields);
        var stud = node('input', { type: 'checkbox', 'aria-label': 'Clous aux passages piétons de ' + j.id }, studWrap);
        studWrap.appendChild(document.createTextNode(' Clous aux passages piétons'));
        stud.checked = draft.crossing_studs === true;
        stud.addEventListener('change', function () { draft.crossing_studs = stud.checked; apply(); });
      }
      var round = type.value === 'roundabout' || type.value === 'double_roundabout';
      if (round) {
        numberField(fields, 'Rayon extérieur, m', draft.outer_radius_m, function (v) { draft.outer_radius_m = v; apply(); });
        numberField(fields, 'Largeur de l’anneau, m', draft.ring_width_m, function (v) { draft.ring_width_m = v; apply(); });
      }
      if (type.value === 'double_roundabout') {
        var wrap = node('label', {}, fields, 'Second carrefour');
        var pair = node('select', { 'aria-label': 'Second carrefour de ' + j.id }, wrap);
        node('option', { value: '' }, pair, '—');
        list.forEach(function (o) { if (o.id !== j.id) { node('option', { value: o.id }, pair, o.id); } });
        pair.value = draft.pair || '';
        pair.addEventListener('change', function () { draft.pair = pair.value || null; apply(); });
      }
    });
  }

  function fmt(n) { return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ' ').replace('.', ','); }

  function showNetwork(network) {
    state.network = network;
    state.digest = network && network.ok ? network.road_digest : null;
    el.diag.textContent = '';
    el.metrics.textContent = '';
    if (!network) { state.lastJunctions = []; renderJunctions([]); drawPlan(null); return; }
    messages(network.diagnostics).forEach(function (m) { node('li', {}, el.diag, m); });
    // Un refus garde la liste des carrefours : on corrige un pont refusé là où on l'a réglé.
    if (!network.ok) { el.metrics.textContent = 'Réseau refusé : rien ne sera écrit.'; renderJunctions(state.lastJunctions); drawPlan(null); return; }
    state.lastJunctions = network.junctions || [];
    var m = network.metrics;
    el.metrics.textContent = m.road_count + (m.road_count > 1 ? ' voies, ' : ' voie, ') + fmt(m.length_m.toFixed(1)) + ' m ; ' + m.junction_count + (m.junction_count > 1 ? ' carrefours ; ' : ' carrefour ; ') +
      (m.bridge_count ? m.bridge_count + (m.bridge_count > 1 ? ' ponts ; ' : ' pont ; ') : '') +
      fmt(m.item_count) + ' objets, ' + fmt(m.expanded_face_count) + ' faces au total.';
    renderJunctions(network.junctions);
    drawPlan(network);
  }

  function drawPlan(network) {
    el.plan.textContent = '';
    if (!network || !network.plan) { return; }
    var xs = [], ys = [];
    network.plan.faces.forEach(function (f) { f[0].forEach(function (p) { xs.push(p[0]); ys.push(p[1]); }); });
    if (!xs.length) { return; }
    var x0 = Math.min.apply(null, xs), x1 = Math.max.apply(null, xs), y0 = Math.min.apply(null, ys), y1 = Math.max.apply(null, ys);
    var pad = Math.max(x1 - x0, y1 - y0) * 0.03 + 1;
    // Repère SVG : y vers le bas ; le nord du modèle reste en haut.
    el.plan.setAttribute('viewBox', [x0 - pad, -(y1 + pad), (x1 - x0) + (2 * pad), (y1 - y0) + (2 * pad)].join(' '));
    var g = svg('g', { transform: 'scale(1,-1)' }, el.plan);
    network.plan.faces.forEach(function (f) {
      svg('polygon', { points: f[0].map(function (p) { return p[0] + ',' + p[1]; }).join(' '), fill: f[1], stroke: f[1], 'stroke-width': 0.05 }, g);
    });
    var size = Math.max(1.5, Math.max(x1 - x0, y1 - y0) / 60);
    (network.junctions || []).forEach(function (j) {
      svg('circle', { cx: j.point_m[0], cy: -j.point_m[1], r: size / 2, fill: '#c0392b' }, el.plan);
      var t = svg('text', { x: j.point_m[0] + size, y: -j.point_m[1] - size, 'font-size': size * 1.4 }, el.plan);
      t.textContent = j.id;
    });
  }

  function updateButtons() {
    var t = state.trace || {};
    el.add.disabled = state.busy || !t.finished;
    var ready = state.writes && !state.busy && !!state.digest;
    el.create.disabled = !ready;
    el.regenerate.disabled = !ready;
  }

  el.add.addEventListener('click', function () {
    var r = decimal(el.radius.value);
    if (r === null) { el.status.textContent = 'Saisissez un rayon valide.'; return; }
    state.notice = null;
    send('add_road', { preset: el.preset.value, axis: el.axis.value, radius_m: r });
  });
  el.resume.addEventListener('click', function () { window.sketchup.archgen_network('activate_tool'); });
  el.create.addEventListener('click', function () { send('create', { road_digest: state.digest }); });
  el.regenerate.addEventListener('click', function () { send('regenerate', { road_digest: state.digest }); });
  el.reload.addEventListener('click', function () { send('load_selection', {}); });
  el.clear.addEventListener('click', function () { state.notice = null; send('clear', {}); if (state.mode === 'trace') { showNetwork(null); } });

  send('init', {});
}());
