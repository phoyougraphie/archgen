// Panneau de rue : affiche et transmet. Le tracé vient de l'outil, toute décision vient de
// Ruby ; le texte passe par textContent.
(function () {
  'use strict';

  var DEBOUNCE_MS = 300;
  var COOLDOWN_MS = 700;
  var state = { counter: 0, pending: {}, timer: null, digest: null, ready: false, busy: false, cooling: false, localError: null };

  function byId(id) { return document.getElementById(id); }
  var el = {
    status: byId('status'), summary: byId('summary'), summaryList: byId('summary-list'), result: byId('result'), warnings: byId('warnings'),
    profile: byId('s-profile'), mode: byId('s-mode'), lod: byId('s-lod'), count: byId('s-count'), height: byId('s-height'),
    side: byId('s-side'), streetField: byId('s-street-field'), street: byId('s-street'), target: byId('s-target'), depth: byId('s-depth'), bay: byId('s-bay'),
    create: byId('create'), clear: byId('clear'), resume: byId('resume')
  };

  function send(action, payload) {
    state.counter += 1;
    var id = 's' + state.counter;
    state.pending[id] = action;
    window.sketchup.archgen_street(JSON.stringify({ v: 1, request_id: id, action: action, payload: payload || {} }));
  }

  function number(input) {
    var text = input.value.trim().replace(',', '.');
    if (text === '') { return null; }
    var value = Number(text);
    return isFinite(value) ? value : NaN;
  }

  // Un champ vide laisse la valeur du style ; une saisie illisible n'est jamais envoyée.
  function settings() {
    var building = { profile: { id: el.profile.value }, mode: el.mode.value, lod: Number(el.lod.value) };
    var levels = {};
    var count = number(el.count);
    var height = number(el.height);
    var values = [count, height, number(el.street), number(el.target), number(el.depth), number(el.bay)];
    state.localError = values.some(function (v) { return v !== null && isNaN(v); }) ? 'Saisissez un nombre valide.' : null;
    if (state.localError) { return null; }
    if (count !== null) { levels.count = count; }
    if (height !== null) { levels.height_m = height; }
    if (count !== null || height !== null) { building.levels = levels; }
    var parcel = {};
    if (number(el.target) !== null) { parcel.target_width_m = number(el.target); }
    if (number(el.depth) !== null) { parcel.depth_m = number(el.depth); }
    if (number(el.bay) !== null) { parcel.bay_width_m = number(el.bay); }
    var layout = { side: el.side.value };
    if (el.side.value === 'both' && number(el.street) !== null) { layout.street_width_m = number(el.street); }
    return { building: building, parcel: parcel, layout: layout };
  }

  function requestPreview() {
    clearTimeout(state.timer);
    state.ready = false;
    updateButtons();
    state.timer = setTimeout(function () {
      var values = settings();
      if (values) { send('preview', { settings: values }); } else { showLocalError(); }
    }, DEBOUNCE_MS);
  }

  function showLocalError() {
    state.digest = null;
    el.result.textContent = state.localError;
    updateButtons();
  }

  function updateButtons() {
    el.create.disabled = !state.ready || state.busy || state.cooling;
    el.clear.disabled = state.busy || !state.hasTrace;
  }

  // Un tracé refusé garde son état : ses refus arrivent dans le résultat.
  function allDiagnostics(response) {
    return response.diagnostics.concat((response.result && response.result.problems) || []);
  }

  function showDiagnostics(diagnostics) {
    var errors = diagnostics.filter(function (d) { return d.severity === 'error'; });
    var warnings = diagnostics.filter(function (d) { return d.severity !== 'error'; });
    fillList(el.summaryList, unique(errors));
    el.summary.hidden = errors.length === 0;
    fillList(el.warnings, unique(warnings));
    el.warnings.hidden = warnings.length === 0;
  }

  // Le même refus peut viser plusieurs parcelles : un seul message suffit à l'affichage.
  function unique(diagnostics) {
    var seen = {};
    return diagnostics.map(function (d) { return d.message; }).filter(function (m) {
      if (seen[m]) { return false; }
      seen[m] = true;
      return true;
    });
  }

  function fillList(list, messages) {
    list.textContent = '';
    messages.forEach(function (message) {
      var item = document.createElement('li');
      item.textContent = message;
      list.appendChild(item);
    });
  }

  function decimal(value) {
    return String(Math.round(value * 100) / 100).replace('.', ',');
  }

  function thousands(value) {
    return String(value).replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
  }

  function showResult(result, ok) {
    var trace = result && result.trace;
    if (!trace) { return; }
    el.side.value = trace.side;
    el.streetField.hidden = trace.side !== 'both';
    state.hasTrace = trace.state !== 'empty';
    // « N bâtiments créés » ne vaut plus dès qu'un nouveau tracé commence.
    if (state.hasTrace && el.status.textContent.indexOf('créés') !== -1) { el.status.textContent = 'Tracé actif'; }
    var metrics = result.metrics;
    var finished = trace.state === 'ready';
    state.digest = metrics ? result.ensemble_digest : null;
    state.ready = Boolean(ok && metrics && finished);
    if (!state.hasTrace) {
      el.result.textContent = 'Aucun tracé.';
      el.create.textContent = 'Créer';
    } else if (metrics) {
      el.result.textContent = metrics.parcel_count + ' bâtiments, dont ' + metrics.definition_count + ' différents ; ' +
        thousands(metrics.expanded_face_count) + ' faces ; façades de ' + decimal(metrics.facade_length_m) + ' m.' +
        (finished ? '' : ' Tracé en cours.');
      el.create.textContent = 'Créer ces ' + metrics.parcel_count + ' bâtiments';
    } else {
      el.result.textContent = trace.points < 2 ? 'Tracé en cours.' : 'Ce tracé ne peut pas être construit.';
      el.create.textContent = 'Créer';
    }
    updateButtons();
  }

  window.archgenStreetReceive = function (json) {
    var response = JSON.parse(json);
    var action = state.pending[response.request_id];
    delete state.pending[response.request_id];
    if (action === 'init') { onInit(response); return; }
    if (action === 'create') { onCreated(response); return; }
    showDiagnostics(allDiagnostics(response));
    showResult(response.result, response.ok);
  };

  // L'outil a changé le tracé.
  window.archgenStreetState = function (json) {
    var update = JSON.parse(json);
    showDiagnostics(allDiagnostics(update));
    showResult(update.result, update.ok);
  };

  window.archgenStreetTool = function (active) {
    el.resume.hidden = active;
    el.status.textContent = active ? 'Tracé actif' : 'Outil inactif';
  };

  function onInit(response) {
    if (!response.ok) { el.status.textContent = 'Panneau indisponible'; return; }
    var result = response.result;
    el.profile.textContent = '';
    result.profiles.forEach(function (profile) {
      var option = document.createElement('option');
      option.value = profile.id;
      option.textContent = profile.label;
      el.profile.appendChild(option);
    });
    var defaults = result.defaults;
    el.profile.value = defaults.building.profile.id;
    el.mode.value = defaults.building.mode;
    el.lod.value = String(defaults.building.lod);
    el.target.value = decimal(defaults.parcel.target_width_m);
    el.depth.value = decimal(defaults.parcel.depth_m);
    el.bay.value = decimal(defaults.parcel.bay_width_m);
    el.street.value = decimal(defaults.layout.street_width_m);
    el.side.value = result.side;
    el.streetField.hidden = result.side !== 'both';
    window.archgenStreetTool(result.tool_active);
    requestPreview();
  }

  function onCreated(response) {
    state.busy = false;
    state.cooling = true;
    setTimeout(function () { state.cooling = false; updateButtons(); }, COOLDOWN_MS);
    showDiagnostics(response.diagnostics);
    showResult(response.result, false);
    if (response.ok) {
      el.status.textContent = response.result.created.metrics.parcel_count + ' bâtiments créés';
    } else {
      requestPreview();
    }
    updateButtons();
  }

  Array.prototype.slice.call(document.querySelectorAll('input, select')).forEach(function (input) {
    input.addEventListener('input', requestPreview);
    input.addEventListener('change', requestPreview);
  });

  el.create.addEventListener('click', function () {
    var values = settings();
    if (!values || !state.digest || state.busy) { return; }
    state.busy = true;
    state.ready = false;
    updateButtons();
    el.status.textContent = 'Écriture en cours…';
    send('create', { settings: values, ensemble_digest: state.digest });
  });

  el.clear.addEventListener('click', function () { send('clear'); });
  el.resume.addEventListener('click', function () { window.sketchup.archgen_street('activate_tool'); });

  send('init');
}());
