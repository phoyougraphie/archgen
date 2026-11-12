// Éditeur de coupe de voirie : compose, transmet, dessine. Plages, valeurs par défaut des
// éléments, position des objets et alertes viennent de Ruby ; le texte passe par textContent.
(function () {
  'use strict';

  var SVG = 'http://www.w3.org/2000/svg';
  var L = window.ArchgenLogic;
  var DEBOUNCE_MS = 120;
  var VW = 1100;
  var PERSON_M = 1.75;
  // Gabarits de repère, en mètres : largeur, hauteur. Affichage seulement.
  var VEHICLES = { car: [1.8, 1.5, 'Voiture'], bus: [2.55, 3.0, 'Bus'], tram: [2.4, 3.4, 'Tram'], train: [2.9, 4.1, 'Train'], bike: [0.6, 1.75, 'Cycliste'] };

  var state = {
    counter: 0, latest: null, pending: {}, timer: null, bands: {}, bandList: [], items: {}, presets: [], families: [],
    draft: [], name: null, preset: null, sel: 0, section: null, diagnostics: [], person: null,
    veh: true, drag: null, geom: null, stale: false, localError: null,
    mode: 'trace', writes: false, digest: null, busy: false, loaded: false, radiusError: null, notice: null
  };

  function byId(id) { return document.getElementById(id); }
  var el = {
    status: byId('status'), presets: byId('presets'), section: byId('section'), plan: byId('plan'), sum: byId('sum'),
    count: byId('count'), n: byId('n'), addType: byId('add-type'), addBand: byId('add-band'), mirror: byId('mirror'),
    bands: byId('bands'), diag: byId('diag'), veh: byId('veh'), title: byId('title'),
    roadBox: byId('road-box'), roadHint: byId('road-hint'), radius: byId('r-radius'), axis: byId('r-axis'),
    roadResult: byId('road-result'), roadDiag: byId('road-diag'), create: byId('road-create'), clear: byId('road-clear'),
    reload: byId('road-reload'), resume: byId('road-resume'),
    ground: byId('r-ground'), retain: byId('r-retain'), survey: byId('r-survey'), groundState: byId('r-ground-state'),
    waterBox: byId('r-water-box'), water: byId('r-water'), grade: byId('r-grade'), drop: byId('r-drop'), chamber: byId('r-chamber'), level: byId('r-level'),
    fGrade: byId('f-grade'), fDrop: byId('f-drop'), fChamber: byId('f-chamber'), fLevel: byId('f-level')
  };
  // Réglages propres à une bande (EAU_CONTRACT), dans l'ordre d'affichage.
  var SETTING_LABELS = { freeboard_m: ['Revanche m', 'revanche en mètres'], depth_m: ['Profondeur m', 'profondeur en mètres'],
    height_m: ['Hauteur m', 'hauteur en mètres'], slope_percent: ['Pente %', 'pente en pour cent'] };

  // --- Pont

  function send(action, payload) {
    state.counter += 1;
    var id = 'r' + state.counter;
    state.pending[id] = action;
    if (action === 'preview' || action === 'init') { state.latest = id; }
    window.sketchup.archgen_road(JSON.stringify({ v: 1, request_id: id, action: action, payload: payload || {} }));
  }

  function profile() {
    var out = { road_profile_version: 1, bands: state.draft };
    if (state.name) { out.name = state.name; }
    return out;
  }

  // Rayon vide : celui de départ à la création, ceux enregistrés à la modification.
  function road() {
    var out = { axis: el.axis.value, on_ground: el.ground.checked };
    var text = el.radius.value.trim();
    var value = text === '' ? null : L.parseDecimal(text);
    state.radiusError = text !== '' && value === null ? 'Saisissez un rayon valide.' : null;
    if (value !== null) { out.radius_m = value; }
    var water = waterSettings();
    if (water) { out.water = water; }
    return out;
  }

  // --- Eau (AG-056) : le régime n'existe qu'avec une bande d'eau ou de mer ; Ruby juge les valeurs.

  function hasWater() {
    return state.draft.some(function (b) { return b.type === 'water' || b.type === 'sea'; });
  }

  function waterSettings() {
    showWaterFields();
    if (!hasWater()) { return null; }
    var out = { mode: el.water.value };
    var fields = { river: [['max_grade_percent', el.grade]], canal: [['lock_drop_m', el.drop], ['lock_length_m', el.chamber]], flat: [['level_m', el.level]] };
    fields[out.mode].forEach(function (pair) {
      var text = pair[1].value.trim();
      if (text === '') { return; }
      var v = L.parseDecimal(text);
      if (v === null) { state.radiusError = 'Saisissez un nombre valide pour l’eau.'; } else { out[pair[0]] = v; }
    });
    return out;
  }

  function showWaterFields() {
    el.waterBox.hidden = !hasWater();
    el.fGrade.hidden = el.water.value !== 'river';
    el.fDrop.hidden = el.water.value !== 'canal';
    el.fChamber.hidden = el.water.value !== 'canal';
    el.fLevel.hidden = el.water.value !== 'flat';
  }

  function waterSummary(m, locks) {
    if (m.water_drop_m === undefined && m.lock_count === undefined) { return ''; }
    var text = ' Eau : chute de ' + fmt(m.water_drop_m || 0) + ' m';
    if (m.lock_count !== undefined) {
      text += m.lock_count === 0 ? ', aucune écluse' : ', ' + m.lock_count + ' écluse' + (m.lock_count > 1 ? 's' : '') + ' à ' +
        locks.map(function (l) { return fmt(l.s_m); }).join(', ') + ' m du départ';
    }
    return text + '.';
  }

  function requestPreview(now) {
    clearTimeout(state.timer);
    // Une saisie de l'utilisateur efface l'annonce d'une écriture ; le recalcul qui la suit la garde.
    if (!now) { state.notice = null; }
    state.digest = null;
    updateButtons();
    el.status.textContent = 'Calcul…';
    var go = function () {
      if (state.localError) { showLocal(); return; }
      var r = road();
      if (state.radiusError) {
        el.roadResult.textContent = state.radiusError;
        el.roadDiag.textContent = '';
        el.status.textContent = 'Saisie à corriger';
        el.status.className = 'status is-bad';
        return;
      }
      send('preview', { profile: profile(), road: r });
    };
    // Jamais d'envoi depuis la réception d'une réponse : le pont pourrait rappeler la page en cascade.
    state.timer = setTimeout(go, now ? 0 : DEBOUNCE_MS);
  }

  // Ruby envoie une chaîne JSON, comme aux autres panneaux (défaut vu en H19 : un objet était attendu).
  window.archgenRoadReceive = function (json) {
    var response = JSON.parse(json);
    var action = state.pending[response.request_id];
    delete state.pending[response.request_id];
    if ((action === 'preview' || action === 'init') && response.request_id !== state.latest) { return; }
    if (action === 'init') { return start(response.result); }
    if (action === 'preview') { return previewed(response); }
    if (action === 'create' || action === 'regenerate') { return written(response, action); }
    if (action === 'load_selection') { return loadedRoad(response); }
    if (action === 'clear') { requestPreview(true); }
    if (action === 'retain_terrain') { return groundAnswer(response, false); }
    if (action === 'survey_ground') { return groundAnswer(response, true); }
  };

  function previewed(response) {
    state.diagnostics = response.diagnostics || [];
    if (response.ok) { showGround(response.result.ground); }
    if (response.ok) {
      state.section = response.result.section;
      state.stale = false;
      el.status.textContent = state.notice || 'Coupe acceptée';
      el.status.className = 'status';
      showRoad(response.result.road);
    } else {
      state.stale = true;
      el.status.textContent = 'Coupe refusée : voir les bandes en rouge';
      el.status.className = 'status is-bad';
      showRoad(null);
    }
    drawAll();
    showRowErrors();
  }

  // --- Voie : tracé, résultat, écriture

  function fmtInt(n) { return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ' '); }

  function showRoad(road) {
    el.roadDiag.textContent = '';
    state.digest = null;
    if (!state.writes) { el.roadBox.hidden = true; return; }
    el.roadBox.hidden = false;
    if (!road) {
      el.roadResult.textContent = state.mode === 'edit'
        ? (state.loaded ? 'Calcul impossible : corrigez la coupe.' : 'Sélectionnez une voie ARCHGEN, puis cliquez sur Recharger la sélection.')
        : 'Tracez la voie dans la vue : un clic par sommet, ou « longueur;angle » au clavier. Double-clic ou Échap pour finir.';
    } else if (road.ok) {
      var m = road.metrics;
      el.roadResult.textContent = 'Voie de ' + fmt(m.length_m) + ' m sur ' + fmt(m.width_m) + ' m : ' + fmtInt(m.item_count) + ' objets' +
        (m.sleeper_count ? ' dont ' + fmtInt(m.sleeper_count) + ' traverses' : '') + ', ' + fmtInt(m.expanded_face_count) + ' faces au total.';
      if (m.grade_max_percent !== undefined) {
        el.roadResult.textContent += ' Pente jusqu’à ' + fmt(m.grade_max_percent) + ' %, déblai ' + fmt(m.cut_max_m) + ' m, remblai ' + fmt(m.fill_max_m) + ' m.';
      }
      el.roadResult.textContent += waterSummary(m, road.locks || []);
      // AG-102 : rejoindre d'autres voies en fait un réseau, carrefours compris.
      if (road.merge && road.merge.count) {
        el.roadResult.textContent += ' Elle rejoint ' + road.merge.count + (road.merge.count > 1 ? ' voies ou réseaux' : ' voie ou réseau') + ' : ensemble, ils formeront un réseau avec ses carrefours.';
      }
      if (road.merge && road.merge.refused) {
        road.merge.refused.forEach(function (d) { node('li', { className: 'is-error' }, el.roadDiag, d.message); });
      }
      state.digest = road.road_digest;
    } else {
      el.roadResult.textContent = 'Cette voie ne peut pas être créée :';
    }
    (road && road.diagnostics || []).forEach(function (d) {
      node('li', { className: d.severity === 'error' ? 'is-error' : 'is-warning' }, el.roadDiag, d.message);
    });
    updateButtons();
  }

  function updateButtons() {
    el.create.disabled = !state.digest || state.busy;
    el.ground.disabled = state.mode === 'edit';
    el.retain.hidden = state.mode === 'edit' || !el.ground.checked;
    el.survey.hidden = !el.ground.checked;
    el.survey.disabled = state.busy;
    el.clear.hidden = state.mode !== 'trace';
    el.reload.hidden = state.mode !== 'edit';
  }

  function written(response, action) {
    state.busy = false;
    if (response.ok) {
      var r = response.result;
      state.notice = (action === 'create' ? 'Voie créée' : 'Voie remplacée') + ', révision ' + r.revision + '. Annuler la retire en une fois.';
      el.status.textContent = state.notice;
      el.status.className = 'status';
    } else {
      // Le refus reste affiché après le recalcul qui suit, jusqu'à la saisie suivante.
      state.notice = response.diagnostics.map(function (d) { return d.message; }).join(' ');
      el.status.textContent = state.notice;
      el.status.className = 'status is-bad';
    }
    requestPreview(true);
  }

  function loadedRoad(response) {
    if (!response.ok) {
      state.loaded = false;
      el.status.textContent = response.diagnostics.map(function (d) { return d.message; }).join(' ');
      el.status.className = 'status is-bad';
      showRoad(null);
      return;
    }
    var r = response.result;
    state.loaded = true;
    el.axis.value = r.axis;
    el.radius.value = r.radius_m === null ? '' : L.formatNumber(r.radius_m);
    el.radius.placeholder = r.radius_m === null ? 'rayons enregistrés' : '';
    el.ground.checked = r.on_ground === true;
    var w = r.water || {};
    el.water.value = w.mode || 'flat';
    el.grade.value = w.max_grade_percent === undefined ? '' : L.formatNumber(w.max_grade_percent);
    el.drop.value = w.lock_drop_m === undefined ? '' : L.formatNumber(w.lock_drop_m);
    el.chamber.value = w.lock_length_m === undefined ? '' : L.formatNumber(w.lock_length_m);
    el.level.value = w.level_m === undefined ? '' : L.formatNumber(w.level_m);
    state.notice = 'Voie chargée, révision ' + r.revision;
    el.status.textContent = state.notice;
    el.status.className = 'status';
    load(r.profile, matchPreset(r.profile));
  }

  // --- Terrain (AG-049) : retenir, relever sur demande ; la voie se calcule ensuite avec ce relevé.

  function showGround(g) {
    if (!g) { return; }
    var parts = [g.terrain ? 'Terrain retenu.' : (state.mode === 'edit' ? '' : 'Aucun terrain retenu : sélectionnez-le, puis Retenir.')];
    parts.push(g.surveyed ? 'Relevé fait (' + fmtInt(g.points) + ' points).' : 'Pas encore relevé.');
    el.groundState.textContent = el.ground.checked ? parts.join(' ') : '';
  }

  function groundAnswer(response, surveyed) {
    state.busy = false;
    if (!response.ok) {
      el.status.textContent = response.diagnostics.map(function (d) { return d.message; }).join(' ');
      el.status.className = 'status is-bad';
      updateButtons();
      return;
    }
    if (surveyed) { previewed(response); } else { showGround(response.result.ground); requestPreview(true); }
  }

  el.ground.addEventListener('change', function () { requestPreview(false); });
  el.water.addEventListener('change', function () { requestPreview(false); });
  [el.grade, el.drop, el.chamber, el.level].forEach(function (input) {
    input.addEventListener('input', function () { requestPreview(false); });
  });
  el.retain.addEventListener('click', function () { send('retain_terrain', {}); });
  el.survey.addEventListener('click', function () {
    el.status.textContent = 'Relevé du terrain…';
    state.busy = true;
    updateButtons();
    send('survey_ground', { profile: profile(), road: road() });
  });

  window.archgenRoadTrace = function () { requestPreview(false); };
  window.archgenRoadTool = function (active) { el.resume.hidden = active || state.mode !== 'trace'; };
  window.archgenRoadRestart = function () { send('init', {}); };

  function setMode(mode) {
    state.mode = mode;
    el.title.textContent = mode === 'edit' ? 'Modifier la voie' : 'Tracer une voie';
    el.create.textContent = mode === 'edit' ? 'Remplacer cette voie' : 'Créer la voie';
    el.roadHint.textContent = mode === 'edit'
      ? 'Le tracé ne change pas. Rayon vide : chaque sommet garde le sien. La voie est remplacée en entier ; Annuler la rétablit en une fois.'
      : 'Rayon appliqué à chaque sommet, 0 pour un angle vif. L’axe suit le milieu ou un bord de la coupe.';
  }

  function start(result) {
    state.writes = result.writes;
    state.loaded = false;
    setMode(result.mode);
    if (result.mode === 'trace' && el.radius.value === '') { el.radius.value = L.formatNumber(result.default_radius_m); }
    el.resume.hidden = result.tool_active || result.mode !== 'trace';
    state.bands = {};
    state.bandList = result.bands;
    result.bands.forEach(function (b) { state.bands[b.type] = b; });
    state.items = {};
    result.items.forEach(function (i) { state.items[i.kind] = i; });
    state.presets = result.presets;
    state.families = result.families;
    load(result.profile, matchPreset(result.profile));
    fillAddType();
    renderPresets();
  }

  function matchPreset(p) {
    var found = state.presets.filter(function (x) { return JSON.stringify(x.profile.bands) === JSON.stringify(p.bands); })[0];
    return found ? found.id : null;
  }

  function load(p, presetId) {
    state.draft = JSON.parse(JSON.stringify(p.bands));
    state.name = p.name || null;
    state.preset = presetId;
    state.sel = 0;
    state.person = null;
    renderPresets();
    renderList();
    requestPreview(true);
  }

  function custom() {
    if (state.preset !== null) { state.preset = null; state.name = null; renderPresets(); }
  }

  // --- Panneau

  function node(tag, attrs, parent, text) {
    var e = document.createElement(tag);
    Object.keys(attrs || {}).forEach(function (k) {
      if (k === 'className') { e.className = attrs[k]; } else if (attrs[k] !== false && attrs[k] !== null) { e.setAttribute(k, attrs[k] === true ? '' : attrs[k]); }
    });
    if (text !== undefined) { e.textContent = text; }
    if (parent) { parent.appendChild(e); }
    return e;
  }

  // Une rangée par famille (AG-147) : libellé, puis ses boutons.
  function renderPresets() {
    el.presets.textContent = '';
    var byPreset = {};
    state.presets.forEach(function (p) { byPreset[p.id] = p; });
    state.families.forEach(function (f) {
      var row = node('div', { class: 'road-family', role: 'group', 'aria-label': f.label }, el.presets);
      node('span', { class: 'road-family-name' }, row, f.label);
      var buttons = node('div', { class: 'road-family-buttons' }, row);
      f.ids.forEach(function (id) {
        var p = byPreset[id];
        var b = node('button', { type: 'button', 'data-preset': p.id, 'aria-pressed': String(state.preset === p.id) }, buttons, p.name);
        b.addEventListener('click', function () { load(p.profile, p.id); });
      });
    });
  }

  function fillAddType() {
    el.addType.textContent = '';
    state.bandList.forEach(function (b) { node('option', { value: b.type }, el.addType, b.label); });
  }

  function options(select, list, value) {
    list.forEach(function (o) {
      var opt = node('option', { value: o[0] }, select, o[1]);
      if (o[0] === value) { opt.selected = true; }
    });
  }

  function decimalInput(value, label, parent, onValue) {
    var input = node('input', { inputmode: 'decimal', 'aria-label': label, value: L.formatNumber(value) }, parent);
    input.addEventListener('input', function () {
      var v = L.parseDecimal(input.value);
      input.classList.toggle('is-invalid', v === null);
      state.localError = v === null ? 'Saisissez un nombre valide.' : null;
      if (v !== null) { onValue(v); }
      requestPreview(false);
    });
    return input;
  }

  function renderList() {
    el.bands.textContent = '';
    el.n.textContent = state.draft.length + ' bande' + (state.draft.length > 1 ? 's' : '');
    state.draft.forEach(function (band, i) {
      var li = node('li', { 'data-i': String(i), className: i === state.sel ? 'is-selected' : '' }, el.bands);
      var row = node('div', { className: 'road-row' }, li);
      node('span', { className: 'road-num' }, row, String(i + 1));
      node('span', { className: 'road-sw c-' + band.type, 'aria-hidden': 'true' }, row);
      var type = node('select', { 'aria-label': 'Type de la bande ' + (i + 1) }, row);
      options(type, state.bandList.map(function (b) { return [b.type, b.label]; }), band.type);
      type.addEventListener('change', function () {
        Object.keys(SETTING_LABELS).forEach(function (k) { delete band[k]; });
        band.type = type.value;
        band.width_m = state.bands[type.value].default_width_m;
        if (!state.bands[type.value].accepts_items) { band.items = []; }
        state.sel = i;
        custom(); renderList(); requestPreview(true);
      });
      decimalInput(band.width_m, 'Largeur de la bande ' + (i + 1) + ', en mètres', row, function (v) { band.width_m = v; custom(); });
      var moves = node('span', { className: 'road-moves' }, row);
      button(moves, '↑', 'Déplacer la bande ' + (i + 1) + ' vers la gauche', i === 0, function () { move(i, -1); });
      button(moves, '↓', 'Déplacer la bande ' + (i + 1) + ' vers la droite', i === state.draft.length - 1, function () { move(i, 1); });
      button(moves, '×', 'Retirer la bande ' + (i + 1), state.draft.length === 1, function () {
        state.draft.splice(i, 1);
        state.sel = Math.min(state.sel, state.draft.length - 1);
        custom(); renderList(); requestPreview(true);
      });
      var settings = state.bands[band.type].settings || {};
      var keys = Object.keys(SETTING_LABELS).filter(function (k) { return settings[k]; });
      if (keys.length) {
        var tune = node('div', { className: 'road-tune' }, li);
        keys.forEach(function (k) {
          var value = band[k] === undefined ? settings[k]['default'] : band[k];
          field(tune, SETTING_LABELS[k][0], value, state.bands[band.type].label + ' ' + (i + 1) + ', ' + SETTING_LABELS[k][1] +
            ', de ' + L.formatNumber(settings[k].min) + ' à ' + L.formatNumber(settings[k].max), function (v) { band[k] = v; });
        });
      }
      li.addEventListener('focusin', function () { select(i); });
      li.addEventListener('click', function () { select(i); });
      if (i === state.sel) { renderItems(li, band, i); }
    });
    showRowErrors();
  }

  function button(parent, text, label, disabled, action) {
    var b = node('button', { type: 'button', 'aria-label': label, title: label, disabled: disabled }, parent, text);
    b.addEventListener('click', function (e) { e.stopPropagation(); action(); });
    return b;
  }

  function select(i) {
    if (state.sel === i) { return; }
    state.sel = i;
    var focused = document.activeElement && document.activeElement.getAttribute('aria-label');
    renderList();
    drawSection();
    if (focused) {
      var again = el.bands.querySelector('[aria-label="' + focused.replace(/"/g, '') + '"]');
      if (again) { again.focus(); }
    }
  }

  function move(i, d) {
    var b = state.draft.splice(i, 1)[0];
    state.draft.splice(i + d, 0, b);
    state.sel = i + d;
    custom(); renderList(); requestPreview(true);
  }

  function renderItems(li, band, i) {
    var box = node('div', { className: 'road-items' }, li);
    if (!state.bands[band.type].accepts_items) {
      node('p', { className: 'hint' }, box, 'Rien ne se pose sur cette bande.');
      return;
    }
    band.items = band.items || [];
    band.items.forEach(function (item, j) {
      var c = state.items[item.kind];
      var row = node('div', { className: 'road-item' }, box);
      var kindLabel = node('label', {}, row);
      node('span', { className: 'road-kind' }, kindLabel, c.label);
      var variant = node('select', { 'aria-label': c.label + ' ' + (j + 1) + ', variante' }, kindLabel);
      options(variant, c.variants.map(function (v) { return [v.id, v.label]; }), item.variant);
      variant.addEventListener('change', function () { item.variant = variant.value; custom(); requestPreview(true); });
      field(row, 'Haut. m', item.height_m, c.label + ' ' + (j + 1) + ', hauteur en mètres', function (v) { item.height_m = v; });
      var name = c.label + ' ' + (j + 1);
      // Pose (docs/MOBILIER_CONTRACT.md §2, AG-124) : au pas, ou à des positions depuis le début de la voie.
      if (item.positions_m) {
        positionsField(row, item, name);
      } else if (c.repeat === 'spaced') {
        field(row, 'Pas m', item.spacing_m, name + ', pas en mètres', function (v) { item.spacing_m = v; });
      } else {
        node('span', { className: 'hint' }, row, 'continu');
      }
      if (c.repeat === 'spaced') {
        var mode = node('select', { 'aria-label': name + ', pose' }, node('label', {}, row, 'Pose'));
        options(mode, [['spaced', 'Au pas'], ['positions', 'Positions']], item.positions_m ? 'positions' : 'spaced');
        mode.addEventListener('change', function () {
          if (mode.value === 'positions') { delete item.spacing_m; item.positions_m = [10]; } else { delete item.positions_m; item.spacing_m = c.default_spacing_m; }
          custom(); renderList(); requestPreview(true);
        });
      } else {
        node('span', {}, row);
      }
      if (c.height_variation) {
        field(row, 'Variation', item.height_variation || 0, name + ', variation de hauteur, de 0 à 0,3', function (v) { item.height_variation = v; });
      } else if (c.default_count) {
        field(row, 'Arceaux', item.count || c.default_count, name + ', nombre d’arceaux, de ' + c.min_count + ' à ' + c.max_count, function (v) { item.count = Math.round(v); });
      } else if (item.kind === 'sign') {
        var facing = node('select', { 'aria-label': name + ', sens' }, node('label', {}, row, 'Sens'));
        options(facing, [['forward', 'Sens du tracé'], ['backward', 'Autre sens']], item.facing || 'forward');
        facing.addEventListener('change', function () { item.facing = facing.value; custom(); requestPreview(true); });
      } else {
        node('span', {}, row);
      }
      button(row, '×', 'Retirer ' + c.label.toLowerCase() + ' ' + (j + 1), false, function () {
        band.items.splice(j, 1);
        custom(); renderList(); requestPreview(true);
      });
    });
    var add = node('div', { className: 'road-add' }, box);
    var kind = node('select', { 'aria-label': 'Élément à ajouter sur la bande ' + (i + 1) }, add);
    options(kind, Object.keys(state.items).map(function (k) { return [k, state.items[k].label]; }), null);
    button(add, 'Ajouter l’élément', 'Ajouter cet élément sur la bande ' + (i + 1), false, function () {
      var c = state.items[kind.value];
      var item = { kind: c.kind, variant: c.default_variant, height_m: c.default_height_m };
      if (c.repeat === 'spaced') { item.spacing_m = c.default_spacing_m; }
      if (c.repeat === 'positions') { item.positions_m = [10]; }
      if (c.default_count) { item.count = c.default_count; }
      band.items.push(item);
      custom(); renderList(); requestPreview(true);
    });
  }

  // Positions en mètres, séparées par des points-virgules : « 12 ; 48,5 ».
  function positionsField(row, item, name) {
    var l = node('label', {}, row, 'Positions m');
    var input = node('input', { 'aria-label': name + ', positions en mètres depuis le début de la voie, séparées par des points-virgules',
      value: item.positions_m.map(function (p) { return L.formatNumber(p); }).join(' ; ') }, l);
    input.addEventListener('input', function () {
      var parts = input.value.split(';').map(function (t) { return L.parseDecimal(t.trim()); });
      var bad = parts.length === 0 || parts.some(function (v) { return v === null; });
      input.classList.toggle('is-invalid', bad);
      state.localError = bad ? 'Saisissez des distances en mètres séparées par des points-virgules.' : null;
      if (!bad) { item.positions_m = parts; custom(); }
      requestPreview(false);
    });
  }

  function field(row, label, value, aria, onValue) {
    var l = node('label', {}, row, label);
    decimalInput(value, aria, l, function (v) { onValue(v); custom(); });
  }

  // Une erreur se rattache à sa bande ; le reste s'affiche sous la liste.
  function showRowErrors() {
    var byBand = {};
    var general = [];
    state.diagnostics.forEach(function (d) {
      var m = /^\/bands\/(\d+)/.exec(d.path || '');
      if (m && d.severity === 'error') { (byBand[m[1]] = byBand[m[1]] || []).push(d.message); } else { general.push(d); }
    });
    Array.prototype.forEach.call(el.bands.children, function (li) {
      var i = li.getAttribute('data-i');
      li.classList.toggle('is-invalid', !!byBand[i]);
      Array.prototype.forEach.call(li.querySelectorAll('.road-row-error'), function (p) { li.removeChild(p); });
      (byBand[i] || []).forEach(function (m) { node('p', { className: 'road-row-error' }, li, m); });
    });
    el.diag.textContent = '';
    if (state.localError) { node('li', { className: 'is-error' }, el.diag, state.localError); }
    general.forEach(function (d) { node('li', { className: d.severity === 'error' ? 'is-error' : 'is-warning' }, el.diag, d.message); });
    if (!state.localError && state.diagnostics.length === 0) { node('li', {}, el.diag, 'Aucun refus ni alerte.'); }
  }

  function showLocal() {
    el.status.textContent = 'Saisie à corriger';
    el.status.className = 'status is-bad';
    state.stale = true;
    drawSection();
    showRowErrors();
  }

  // --- Dessin SVG

  function svg(tag, attrs, parent, text) {
    var e = document.createElementNS(SVG, tag);
    Object.keys(attrs).forEach(function (k) { e.setAttribute(k, attrs[k]); });
    if (text !== undefined) { e.textContent = text; }
    parent.appendChild(e);
    return e;
  }

  function fmt(v) { return L.formatNumber(Math.round(v * 100) / 100); }

  function surfaceZ(x) {
    var bands = state.section.bands;
    for (var i = 0; i < bands.length; i += 1) {
      var p = bands[i].surface;
      for (var k = 0; k + 1 < p.length; k += 1) {
        if (x >= p[k][0] && x <= p[k + 1][0]) {
          var w = p[k + 1][0] - p[k][0];
          return w < 1e-9 ? p[k][1] : p[k][1] + (p[k + 1][1] - p[k][1]) * (x - p[k][0]) / w;
        }
      }
    }
    return 0;
  }

  function topOf() {
    var top = 2.2;
    state.section.items.forEach(function (it) { top = Math.max(top, it.z_m + it.height_m + 0.3); });
    if (state.veh) { top = Math.max(top, 4.8); }
    state.section.bands.forEach(function (b) { b.surface.forEach(function (p) { top = Math.max(top, p[1] + 2); }); });
    return top;
  }

  function drawSection() {
    var root = el.section;
    root.textContent = '';
    var sec = state.section;
    if (!sec) { return; }
    root.classList.toggle('road-stale', state.stale);
    var W = sec.width_m;
    var margin = 46;
    var s = Math.min(48, (VW - 2 * margin) / Math.max(W, 1));
    var top = topOf();
    // Sous le niveau 0 : 1,4 m, ou le lit d'un plan d'eau et 0,6 m de plus (EAU_CONTRACT).
    var below = 1.4;
    sec.bands.forEach(function (b) { b.surface.forEach(function (p) { below = Math.max(below, 0.6 - p[1]); }); });
    var head = 24;
    var base = head + top * s;
    var ox = (VW - W * s) / 2;
    var cy = base + below * s + 18;
    var H = cy + 40;
    state.geom = { s: s, ox: ox };
    function X(m) { return ox + m * s; }
    function Z(z) { return base - z * s; }
    root.setAttribute('viewBox', '0 0 ' + VW + ' ' + H);
    // Échelle exposée pour la recette : les sondes mesurent chaque objet en mètres.
    root.setAttribute('data-scale', s);

    svg('rect', { x: 0, y: 0, width: VW, height: base, class: 's-sky' }, root);
    var d = 'M0 ' + Z(sec.bands[0].surface[0][1]);
    sec.bands.forEach(function (b) { b.surface.forEach(function (p) { d += ' L' + X(p[0]) + ' ' + Z(p[1]); }); });
    var last = sec.bands[sec.bands.length - 1].surface;
    d += ' L' + VW + ' ' + Z(last[last.length - 1][1]) + ' L' + VW + ' ' + (base + below * s) + ' L0 ' + (base + below * s) + ' Z';
    svg('path', { d: d, class: 's-earth' }, root);

    // Surface de l'eau, transparente, au-dessus du lit.
    (sec.water || []).forEach(function (w) {
      var band = sec.bands[w.band];
      var d2 = 'M' + X(w.x0_m) + ' ' + Z(w.z_m);
      band.surface.forEach(function (p) { d2 += ' L' + X(p[0]) + ' ' + Z(Math.min(p[1], w.z_m)); });
      d2 += ' L' + X(w.x1_m) + ' ' + Z(w.z_m) + ' Z';
      svg('path', { d: d2, class: 's-water' }, root);
    });

    var thick = Math.max(5, 0.22 * s);
    sec.bands.forEach(function (b) {
      if (b.index === state.sel) {
        svg('rect', { x: X(b.x0_m), y: head, width: (b.x1_m - b.x0_m) * s, height: base - head + below * s, class: 's-select' }, root);
      }
      var line = b.surface.map(function (p, k) { return (k ? 'L' : 'M') + X(p[0]) + ' ' + Z(p[1]); }).join(' ');
      svg('path', { d: line, class: 's-band c-' + b.type, 'stroke-width': thick }, root);
    });
    sec.curbs.forEach(function (c) {
      var x = c.side === 'right' ? X(c.x_m) : X(c.x_m - c.width_m);
      svg('rect', { x: x, y: Z(c.z_high_m), width: Math.max(2, c.width_m * s), height: Math.max(3, (c.z_high_m - c.z_low_m + 0.12) * s), class: 's-curb' }, root);
    });
    // Traverses de 2,6 m sous les rails, dessus au niveau du ballast ; rails posés dessus (0,17 m de haut),
    // ou encastrés au ras de la chaussée. Défaut vu à la mesure : rails dessinés 12 cm trop haut.
    sec.bands.filter(function (b) { return b.type === 'rail'; }).forEach(function (b) {
      var c = (b.x0_m + b.x1_m) / 2;
      svg('rect', { x: X(c - 1.3), y: Z(b.level_m), width: 2.6 * s, height: Math.max(3, 0.15 * s), class: 's-trunk' }, root);
    });
    sec.rails.forEach(function (r) {
      var tall = r.kind === 'ballast' ? 0.17 : 0.05;
      svg('rect', { x: X(r.x_m) - Math.max(2, 0.035 * s), y: Z(r.z_m), width: Math.max(4, 0.07 * s), height: Math.max(3, tall * s), class: 's-rail', 'data-rail': r.band, 'data-x': X(r.x_m), 'data-top': Z(r.z_m) }, root);
    });
    if (state.veh) { drawVehicles(root, sec, X, Z, s); }
    sec.items.forEach(function (it) { drawItem(root, it, X, Z, s); });
    sec.bands.forEach(function (b) {
      var hit = svg('rect', { x: X(b.x0_m), y: head, width: (b.x1_m - b.x0_m) * s, height: base - head + below * s, class: 's-hit', 'data-band': b.index }, root);
      svg('title', {}, hit, (b.index + 1) + '. ' + state.bands[b.type].label + ', ' + fmt(b.x1_m - b.x0_m) + ' m');
    });
    drawPerson(root, X, Z, s, W);
    drawDims(root, sec, X, s, cy, W);
  }

  function drawVehicles(root, sec, X, Z, s) {
    sec.bands.forEach(function (b) {
      var type = b.type;
      var v = null;
      if (type === 'lane') { v = (b.x1_m - b.x0_m) >= 3.4 && sec.width_m > 25 ? 'bus' : 'car'; }
      if (type === 'parking' || type === 'track') { v = 'car'; }
      if (type === 'tram' || type === 'tram_lane') { v = 'tram'; }
      if (type === 'rail') { v = 'train'; }
      if (type === 'cycle') { v = 'bike'; }
      if (!v) { return; }
      var c = (b.x0_m + b.x1_m) / 2;
      // Un train roule sur ses rails, pas sur le ballast : défaut vu à la mesure, il flottait de 13 cm.
      var onRails = sec.rails.filter(function (r) { return r.band === b.index; });
      var z = type === 'rail' && onRails.length ? onRails[0].z_m : surfaceZ(c);
      var dim = VEHICLES[v];
      var w = dim[0] * s;
      var h = dim[1] * s;
      var x = X(c);
      var y = Z(z);
      var g = svg('g', { 'pointer-events': 'none', 'data-vehicle': v, 'data-on-band': b.index, 'data-w-m': dim[0], 'data-h-m': dim[1], 'data-x': x }, root);
      svg('title', {}, g, dim[2]);
      if (v === 'bike') {
        svg('circle', { cx: x, cy: y - h + 0.12 * s, r: 0.12 * s, class: 's-veh' }, g);
        svg('rect', { x: x - 0.2 * s, y: y - h + 0.26 * s, width: 0.4 * s, height: 0.7 * s, class: 's-veh' }, g);
        svg('rect', { x: x - 0.03 * s, y: y - 0.8 * s, width: 0.06 * s, height: 0.8 * s, class: 's-veh' }, g);
        return;
      }
      var low = v === 'car' ? 0.45 : 0.22;
      svg('rect', { x: x - w / 2, y: y - h, width: w, height: h - 0.18 * s, rx: 0.18 * s, class: 's-veh' }, g);
      svg('rect', { x: x - w / 2 + 0.14 * s, y: y - h + 0.16 * s, width: w - 0.28 * s, height: h * (1 - low) - 0.34 * s, rx: 0.08 * s, class: 's-glass' }, g);
      svg('rect', { x: x - w / 2 + 0.14 * s, y: y - 0.18 * s, width: 0.26 * s, height: 0.18 * s, class: 's-steel' }, g);
      svg('rect', { x: x + w / 2 - 0.4 * s, y: y - 0.18 * s, width: 0.26 * s, height: 0.18 * s, class: 's-steel' }, g);
    });
  }

  function drawItem(root, it, X, Z, s) {
    var g = svg('g', { 'data-kind': it.kind, 'data-variant': it.variant, 'data-height-m': it.height_m, 'data-crown-m': it.kind === 'tree' ? 2 * it.crown_radius_m : 0, 'data-x': X(it.x_m) }, root);
    var c = state.items[it.kind];
    var variant = c.variants.filter(function (v) { return v.id === it.variant; })[0];
    svg('title', {}, g, c.label + ' : ' + variant.label + ', ' + fmt(it.height_m) + ' m');
    var x = X(it.x_m);
    var z = Z(it.z_m);
    var h = it.height_m * s;
    var dir = it.toward === 'left' ? -1 : 1;
    if (it.kind === 'tree') {
      var r = it.crown_radius_m * s;
      var base = it.crown_base_m * s;
      svg('rect', { x: x - Math.max(1.5, 0.012 * h), y: z - base - 2, width: Math.max(3, 0.024 * h), height: base + 2, class: 's-trunk' }, g);
      if (it.variant === 'conifer') {
        svg('path', { d: 'M' + x + ' ' + (z - h) + 'L' + (x + r) + ' ' + (z - base) + 'L' + (x - r) + ' ' + (z - base) + 'Z', class: 's-tree2' }, g);
      } else {
        svg('ellipse', { cx: x, cy: z - (base + h) / 2, rx: r, ry: (h - base) / 2, class: (it.variant === 'columnar' ? 's-tree2' : 's-tree') + ' s-crown' }, g);
      }
    } else if (it.kind === 'lamp') {
      svg('line', { x1: x, y1: z, x2: x, y2: z - h, class: 's-pole', 'stroke-width': it.variant === 'high' ? 3 : 2 }, g);
      var a = 1.5 * s;
      if (it.variant === 'single' || it.variant === 'double') {
        [dir, it.variant === 'double' ? -dir : null].forEach(function (k) {
          if (k === null) { return; }
          // La crosse retombe depuis le haut du mât : rien ne dépasse la hauteur annoncée (défaut vu à la mesure).
          svg('path', { d: 'M' + x + ' ' + (z - h) + 'q' + (k * a * 0.6) + ' 0 ' + (k * a) + ' ' + (0.12 * s), class: 's-pole', 'stroke-width': 2 }, g);
          svg('rect', { x: x + k * a - 0.25 * s, y: z - h + 0.12 * s, width: 0.5 * s, height: 3, class: 's-steel' }, g);
        });
      } else if (it.variant === 'ped') {
        var globe = Math.max(3, 0.18 * s);
        svg('circle', { cx: x, cy: z - h + globe, r: globe, class: 's-steel' }, g);
      } else if (it.variant === 'heritage') {
        svg('path', { d: 'M' + (x - 0.22 * s) + ' ' + (z - h + 0.55 * s) + 'L' + (x + 0.22 * s) + ' ' + (z - h + 0.55 * s) + 'L' + (x + 0.3 * s) + ' ' + (z - h) + 'L' + (x - 0.3 * s) + ' ' + (z - h) + 'Z', class: 's-steel' }, g);
      } else {
        svg('rect', { x: x - 0.9 * s, y: z - h, width: 1.8 * s, height: Math.max(4, 0.25 * s), class: 's-steel' }, g);
      }
    } else if (it.kind === 'hedge') {
      svg('rect', { x: x - 0.4 * s, y: z - h, width: 0.8 * s, height: h, rx: Math.min(6, 0.2 * s), class: 's-hedge' }, g);
    } else if (it.kind === 'fence') {
      svg('rect', { x: x - 1.5, y: z - h, width: 3, height: h, class: it.variant === 'mesh' ? 's-steel' : 's-trunk' }, g);
    } else if (it.kind === 'guard') {
      if (it.variant === 'concrete') {
        svg('path', { d: 'M' + (x - 0.3 * s) + ' ' + z + 'L' + (x - 0.08 * s) + ' ' + (z - h) + 'L' + (x + 0.08 * s) + ' ' + (z - h) + 'L' + (x + 0.3 * s) + ' ' + z + 'Z', class: 's-concrete' }, g);
      } else {
        svg('line', { x1: x, y1: z, x2: x, y2: z - h, class: 's-pole', 'stroke-width': 2 }, g);
        svg('rect', { x: x - 0.08 * s, y: z - h, width: 0.16 * s, height: 0.31 * s, class: 's-steel' }, g);
      }
    } else if (it.kind === 'road_stud') {
      // Plot de chaussée (D-10) : galet de 10 cm sur la limite gauche de sa bande.
      svg('rect', { x: x - 0.05 * s, y: z - h, width: 0.1 * s, height: h, class: it.variant === 'reflective' ? 's-reflector' : 's-stud' }, g);
    } else if (it.kind === 'sand_fence') {
      // Ganivelle (AG-052) : paroi de lattes vue en bout, comme une barrière.
      svg('rect', { x: x - 1.5, y: z - h, width: 3, height: h, class: 's-trunk' }, g);
    } else if (it.kind === 'low_wall') {
      svg('rect', { x: x - 0.15 * s, y: z - h, width: 0.3 * s, height: h, class: 's-concrete' }, g);
    } else if (it.kind === 'bollard') {
      svg('rect', { x: x - Math.max(1.5, 0.05 * s), y: z - h, width: Math.max(3, 0.1 * s), height: h, rx: 1.5, class: 's-steel' }, g);
    } else if (it.kind === 'pole') {
      svg('line', { x1: x, y1: z, x2: x, y2: z - h, class: 's-pole', 'stroke-width': 2.5 }, g);
      svg('line', { x1: x, y1: z - h + 0.4 * s, x2: x + dir * 2.6 * s, y2: z - h + 0.4 * s, class: 's-pole', 'stroke-width': 1.5 }, g);
      svg('line', { x1: x + dir * 0.2 * s, y1: z - h + 1.1 * s, x2: x + dir * 3.4 * s, y2: z - h + 1.1 * s, class: 's-wire', 'stroke-width': 1 }, g);
    } else if (it.kind === 'bench') {
      // Banc vu en bout (AG-120) : assise de 0,40 m, dossier côté chaussée.
      svg('rect', { x: x - 0.2 * s, y: z - 0.47 * s, width: 0.4 * s, height: Math.max(2, 0.05 * s), class: 's-trunk' }, g);
      svg('rect', { x: x + dir * 0.18 * s - 0.02 * s, y: z - h, width: Math.max(2, 0.04 * s), height: h - 0.5 * s, class: 's-trunk' }, g);
      svg('rect', { x: x - 0.03 * s, y: z - 0.42 * s, width: Math.max(2, 0.06 * s), height: 0.42 * s, class: 's-steel' }, g);
    } else if (it.kind === 'bin') {
      svg('rect', { x: x - 0.25 * s, y: z - h, width: 0.5 * s, height: h, rx: 2, class: 's-steel' }, g);
    } else if (it.kind === 'bus_stop') {
      // Abri vu en bout (AG-124) : fond vitré loin de la chaussée, toit, banc ; ou mât et plaque.
      if (it.variant === 'shelter') {
        svg('rect', { x: x - dir * 0.7 * s - 1, y: z - h, width: 2, height: h, class: 's-glass' }, g);
        svg('rect', { x: x - 0.75 * s, y: z - h, width: 1.5 * s, height: Math.max(2, 0.1 * s), class: 's-steel' }, g);
        svg('line', { x1: x + dir * 0.7 * s, y1: z, x2: x + dir * 0.7 * s, y2: z - h, class: 's-pole', 'stroke-width': 1.5 }, g);
        svg('rect', { x: x - dir * 0.5 * s - 0.15 * s, y: z - 0.47 * s, width: 0.3 * s, height: Math.max(2, 0.05 * s), class: 's-trunk' }, g);
      } else {
        svg('line', { x1: x, y1: z, x2: x, y2: z - 2.6 * s, class: 's-pole', 'stroke-width': 2 }, g);
        svg('rect', { x: x - 0.2 * s, y: z - 2.6 * s, width: 0.4 * s, height: 0.4 * s, class: 's-sign-blue' }, g);
      }
    } else if (it.kind === 'sign') {
      // Panneau vu de face dans la coupe : mât et plaque à sa forme et ses couleurs (D-36).
      svg('line', { x1: x, y1: z, x2: x, y2: z - h, class: 's-pole', 'stroke-width': 1.5 }, g);
      var shapes = { stop: [8, 22.5, 'red'], give_way: [3, -90, 'white'], prohibition: [16, 0, 'red'], limit: [16, 0, 'white'],
        mandatory: [16, 0, 'blue'], information: [4, 45, 'blue'], danger: [3, 90, 'white'], crossing: [4, 45, 'blue'] };
      var sh = shapes[it.variant] || shapes.limit;
      var r = 0.35 * s;
      var pts = [];
      for (var k = 0; k < sh[0]; k++) {
        var a = (sh[1] * Math.PI / 180) + (2 * Math.PI * k / sh[0]);
        pts.push((x - r * Math.cos(a)) + ',' + (z - h + r - r * Math.sin(a)));
      }
      svg('polygon', { points: pts.join(' '), class: 's-sign-' + sh[2] }, g);
    } else if (it.kind === 'bike_rack') {
      // Arceau en U renversé de 0,80 m, vu de face dans la coupe.
      svg('path', { d: 'M' + (x - 0.4 * s) + ' ' + z + 'L' + (x - 0.4 * s) + ' ' + (z - h) + 'L' + (x + 0.4 * s) + ' ' + (z - h) + 'L' + (x + 0.4 * s) + ' ' + z, class: 's-pole', fill: 'none', 'stroke-width': 2 }, g);
    }
  }

  function drawPerson(root, X, Z, s, W) {
    if (state.person === null) {
      // Sur un cheminement piéton, sinon sur une bande plate hors voies, fossés et talus (pas au fond d'un fossé).
      var away = ['carriageway', 'tram', 'rail', 'ditch', 'bank'];
      var ped = state.section.bands.filter(function (b) { return b.role === 'pedestrian'; })[0] ||
        state.section.bands.filter(function (b) { return away.indexOf(b.role) < 0; })[0] || state.section.bands[0];
      state.person = ped.x0_m + (ped.x1_m - ped.x0_m) * 0.7;
    }
    state.person = Math.max(0, Math.min(W, state.person));
    var x = X(state.person);
    var z = Z(surfaceZ(state.person));
    var h = PERSON_M * s;
    var g = svg('g', { class: 's-human', 'data-human': '1' }, root);
    svg('title', {}, g, 'Personnage de 1,75 m : glissez-le le long de la coupe');
    svg('rect', { x: x - 0.5 * s, y: z - 1.9 * s, width: s, height: 1.9 * s, class: 's-hit' }, g);
    // Silhouette de face, du sommet du crâne (1,75 m) à la plante des pieds (0) : défaut vu en H19.
    function y(m) { return z - m * s; }
    svg('circle', { cx: x, cy: y(1.64), r: 0.11 * s, class: 's-person', 'data-person-head': '1' }, g);
    svg('path', { d: 'M' + (x - 0.21 * s) + ' ' + y(1.47) + 'L' + (x + 0.21 * s) + ' ' + y(1.47) + 'L' + (x + 0.17 * s) + ' ' + y(0.88) + 'L' + (x - 0.17 * s) + ' ' + y(0.88) + 'Z', class: 's-person' }, g);
    svg('rect', { x: x - 0.29 * s, y: y(1.45), width: 0.07 * s, height: 0.62 * s, class: 's-person' }, g);
    svg('rect', { x: x + 0.22 * s, y: y(1.45), width: 0.07 * s, height: 0.62 * s, class: 's-person' }, g);
    svg('rect', { x: x - 0.16 * s, y: y(0.9), width: 0.13 * s, height: 0.9 * s, class: 's-person' }, g);
    svg('rect', { x: x + 0.03 * s, y: y(0.9), width: 0.13 * s, height: 0.9 * s, class: 's-person' }, g);
    svg('text', { x: x, y: z - h - 5, 'text-anchor': 'middle', class: 's-person-text' }, g, '1,75 m');
  }

  function drawDims(root, sec, X, s, cy, W) {
    svg('line', { x1: X(0), y1: cy, x2: X(W), y2: cy, class: 's-dim' }, root);
    sec.bands.forEach(function (b) {
      var x0 = X(b.x0_m);
      var w = (b.x1_m - b.x0_m) * s;
      svg('line', { x1: x0, y1: cy - 4, x2: x0, y2: cy + 4, class: 's-dim' }, root);
      if (w >= 30) { svg('text', { x: x0 + w / 2, y: cy - 5, 'text-anchor': 'middle', class: 's-dim-text' }, root, fmt(b.x1_m - b.x0_m)); }
      svg('text', { x: x0 + w / 2, y: cy + 14, 'text-anchor': 'middle', class: 's-dim-text' }, root, String(b.index + 1));
    });
    svg('line', { x1: X(W), y1: cy - 4, x2: X(W), y2: cy + 4, class: 's-dim' }, root);
    svg('text', { x: X(W / 2), y: cy + 32, 'text-anchor': 'middle', class: 's-dim-strong' }, root, 'Emprise ' + fmt(W) + ' m');
    var bar = W > 20 ? 5 : 2;
    svg('rect', { x: 12, y: cy + 24, width: bar * s, height: 4, class: 's-scale', 'data-scale-m': bar }, root);
    svg('text', { x: 12, y: cy + 20, class: 's-dim-text' }, root, bar + ' m');
    for (var i = 1; i < sec.bands.length; i += 1) {
      var gx = X(sec.bands[i].x0_m);
      var g = svg('g', { 'data-grip': String(i) }, root);
      svg('title', {}, g, 'Glisser pour changer la largeur de la bande ' + i);
      svg('rect', { x: gx - 8, y: cy - 15, width: 16, height: 26, class: 's-grip-hit' }, g);
      svg('rect', { x: gx - 2.5, y: cy - 9, width: 5, height: 14, rx: 1.5, class: 's-grip' }, g);
    }
  }

  function drawPlan() {
    var root = el.plan;
    root.textContent = '';
    var sec = state.section;
    if (!sec) { return; }
    var W = sec.width_m;
    var s = Math.min(14, 250 / Math.max(W, 1));
    var len = VW / s;
    var H = W * s + 26;
    root.setAttribute('viewBox', '0 0 ' + VW + ' ' + H);
    sec.bands.forEach(function (b, i) {
      var y = b.x0_m * s + 4;
      var h = (b.x1_m - b.x0_m) * s;
      svg('rect', { x: 0, y: y, width: VW, height: h, class: 'c-' + b.type }, root);
      var next = sec.bands[i + 1];
      if ((b.type === 'lane' || b.type === 'tram_lane') && next && (next.type === 'lane' || next.type === 'tram_lane')) {
        svg('line', { x1: 0, y1: y + h, x2: VW, y2: y + h, class: 's-mark', 'stroke-width': Math.max(1, 0.15 * s), 'stroke-dasharray': (3 * s) + ' ' + (3 * s) }, root);
      }
      if (b.type === 'parking') {
        for (var p = 0; p < len; p += 5) { svg('line', { x1: p * s, y1: y, x2: p * s, y2: y + h, class: 's-mark', 'stroke-width': 1 }, root); }
      }
    });
    sec.rails.forEach(function (r) {
      svg('line', { x1: 0, y1: r.x_m * s + 4, x2: VW, y2: r.x_m * s + 4, class: 's-pole', 'stroke-width': Math.max(1, 0.1 * s) }, root);
    });
    var per = {};
    sec.items.forEach(function (it) {
      var y = it.x_m * s + 4;
      if (it.repeat === 'spaced') {
        for (var dd = it.spacing_m / 2; dd < len; dd += it.spacing_m) {
          if (it.kind === 'tree') {
            svg('circle', { cx: dd * s, cy: y, r: Math.max(1.5, it.crown_radius_m * s), class: (it.variant === 'columnar' || it.variant === 'conifer' ? 's-tree2' : 's-tree') + ' s-crown' }, root);
          } else {
            svg('circle', { cx: dd * s, cy: y, r: Math.max(1.6, 0.25 * s), class: 's-steel' }, root);
          }
        }
        per[it.kind] = (per[it.kind] || 0) + it.count_per_100m;
      } else {
        svg('line', { x1: 0, y1: y, x2: VW, y2: y, class: it.kind === 'hedge' ? 's-pole s-hedge-line' : 's-pole', 'stroke-width': it.kind === 'hedge' ? Math.max(2, 0.8 * s) : Math.max(1, 0.12 * s) }, root);
      }
    });
    svg('rect', { x: 12, y: W * s + 12, width: 10 * s, height: 4, class: 's-scale' }, root);
    svg('text', { x: 16 + 10 * s, y: W * s + 18, class: 's-dim-text' }, root, '10 m');
    var parts = Object.keys(per).map(function (k) { return per[k] + ' × ' + state.items[k].label.toLowerCase(); });
    el.count.textContent = (parts.length ? parts.join(', ') : 'aucun objet répété') + ' pour 100 m ; vue sur ' + Math.round(len) + ' m';
  }

  function drawSummary() {
    var sec = state.section;
    if (!sec) { el.sum.textContent = ''; return; }
    var lanes = sec.bands.filter(function (b) { return b.type === 'lane' || b.type === 'tram_lane' || b.type === 'track'; }).length;
    var rails = sec.bands.filter(function (b) { return b.type === 'tram' || b.type === 'tram_lane' || b.type === 'rail'; }).length;
    var ped = sec.bands.filter(function (b) { return b.role === 'pedestrian'; }).length;
    var bits = ['emprise ' + fmt(sec.width_m) + ' m'];
    if (lanes) { bits.push(lanes + ' voie' + (lanes > 1 ? 's' : '')); }
    if (rails) { bits.push(rails + ' sur rails'); }
    if (ped) { bits.push(ped + ' cheminement' + (ped > 1 ? 's' : '') + ' piéton' + (ped > 1 ? 's' : '')); }
    el.sum.textContent = bits.join(' ; ');
  }

  function drawAll() { drawSection(); drawPlan(); drawSummary(); }

  // --- Gestes dans la coupe

  function toMeters(e) {
    var r = el.section.getBoundingClientRect();
    var vb = el.section.viewBox.baseVal;
    return ((e.clientX - r.left) * vb.width / r.width - state.geom.ox) / state.geom.s;
  }

  el.section.addEventListener('pointerdown', function (e) {
    if (!state.geom) { return; }
    var grip = e.target.closest('[data-grip]');
    if (grip) {
      var i = Number(grip.getAttribute('data-grip'));
      state.drag = { type: 'grip', i: i, start: toMeters(e), width: state.draft[i - 1].width_m };
      el.section.setPointerCapture(e.pointerId);
      state.sel = i - 1;
      renderList();
      e.preventDefault();
      return;
    }
    if (e.target.closest('[data-human]')) {
      state.drag = { type: 'human' };
      el.section.setPointerCapture(e.pointerId);
      e.preventDefault();
      return;
    }
    var hit = e.target.closest('[data-band]');
    if (hit) { select(Number(hit.getAttribute('data-band'))); }
  });

  el.section.addEventListener('pointermove', function (e) {
    if (!state.drag) { return; }
    var m = toMeters(e);
    if (state.drag.type === 'human') { state.person = m; drawSection(); return; }
    var band = state.draft[state.drag.i - 1];
    var c = state.bands[band.type];
    var w = Math.round((state.drag.width + m - state.drag.start) * 20) / 20;
    band.width_m = Math.max(c.min_width_m, Math.min(c.max_width_m, w));
    var input = el.bands.querySelector('[aria-label="Largeur de la bande ' + state.drag.i + ', en mètres"]');
    if (input) { input.value = L.formatNumber(band.width_m); }
    custom();
    requestPreview(true);
  });

  function endDrag() { state.drag = null; }
  el.section.addEventListener('pointerup', endDrag);
  el.section.addEventListener('pointercancel', endDrag);

  el.addBand.addEventListener('click', function () {
    var c = state.bands[el.addType.value];
    var at = Math.min(state.sel + 1, state.draft.length);
    state.draft.splice(at, 0, { type: c.type, width_m: c.default_width_m, items: [] });
    state.sel = at;
    custom(); renderList(); requestPreview(true);
  });

  el.mirror.addEventListener('click', function () {
    state.draft.reverse();
    state.sel = state.draft.length - 1 - state.sel;
    custom(); renderList(); requestPreview(true);
  });

  el.veh.addEventListener('change', function () { state.veh = el.veh.checked; drawSection(); });

  // Seul « input » relance l'aperçu : quitter un champ ne doit jamais désactiver le bouton sous la souris (AG-036).
  el.radius.addEventListener('input', function () { requestPreview(false); });
  el.axis.addEventListener('input', function () { requestPreview(false); });
  el.create.addEventListener('click', function () {
    if (!state.digest || state.busy) { return; }
    state.busy = true;
    updateButtons();
    el.status.textContent = state.mode === 'edit' ? 'Remplacement en cours…' : 'Écriture de la voie en cours…';
    send(state.mode === 'edit' ? 'regenerate' : 'create', { profile: profile(), road: road(), road_digest: state.digest });
  });
  el.clear.addEventListener('click', function () { send('clear', {}); });
  el.reload.addEventListener('click', function () { send('load_selection', {}); });
  el.resume.addEventListener('click', function () { window.sketchup.archgen_road('activate_tool'); });

  send('init', {});
}());
