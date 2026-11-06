// Panneau de rue : affiche et transmet. Le tracé vient de l'outil, toute décision vient de
// Ruby ; le texte passe par textContent.
(function () {
  'use strict';

  var DEBOUNCE_MS = 300;
  var COOLDOWN_MS = 700;
  var state = { counter: 0, pending: {}, timer: null, digest: null, ready: false, busy: false, cooling: false, localError: null, mode: 'new', loaded: false };

  function byId(id) { return document.getElementById(id); }
  var el = {
    status: byId('status'), summary: byId('summary'), summaryList: byId('summary-list'), result: byId('result'), warnings: byId('warnings'),
    profile: byId('s-profile'), mode: byId('s-mode'), lod: byId('s-lod'), count: byId('s-count'), height: byId('s-height'),
    side: byId('s-side'), streetField: byId('s-street-field'), street: byId('s-street'), target: byId('s-target'), depth: byId('s-depth'), bay: byId('s-bay'),
    accessFields: byId('s-access-fields'), accessCount: byId('s-access-count'), accessWidth: byId('s-access-width'), accessHeight: byId('s-access-height'),
    title: byId('title'), guide: byId('guide'), replaceWarning: byId('replace-warning'), reload: byId('reload'),
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
    var values = [count, height, number(el.street), number(el.target), number(el.depth), number(el.bay), number(el.accessWidth), number(el.accessHeight)];
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
    var access = { count: el.accessCount.value === 'auto' ? 'auto' : Number(el.accessCount.value) };
    if (number(el.accessWidth) !== null) { access.width_m = number(el.accessWidth); }
    if (number(el.accessHeight) !== null) { access.height_m = number(el.accessHeight); }
    return { building: building, parcel: parcel, layout: layout, access: access };
  }

  function requestPreview() {
    clearTimeout(state.timer);
    state.ready = false;
    state.previewPending = true;
    updateButtons();
    state.timer = setTimeout(function () {
      state.previewPending = false;
      var values = settings();
      if (!values) { showLocalError(); return; }
      if (state.mode === 'edit') {
        if (state.loaded) { send('edit_preview', { settings: values }); }
      } else {
        send('preview', { settings: values });
      }
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
    // Une saisie encore en attente l'emporte sur l'état reçu de l'outil.
    if (!state.previewPending) {
      el.side.value = trace.side;
      el.streetField.hidden = trace.side !== 'both' || trace.closed;
    }
    el.side.disabled = trace.closed;
    el.accessFields.hidden = !trace.closed;
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
        (metrics.access_count ? metrics.access_count + ' accès à la cour ; ' : '') +
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
    if (action === 'load_selection') { onLoaded(response); return; }
    if (action === 'edit_preview') { showDiagnostics(allDiagnostics(response)); showEdit(response.result, response.ok); return; }
    if (action === 'regenerate') { onRegenerated(response); return; }
    showDiagnostics(allDiagnostics(response));
    showResult(response.result, response.ok);
  };

  // L'outil a changé le tracé.
  window.archgenStreetState = function (json) {
    var update = JSON.parse(json);
    showDiagnostics(allDiagnostics(update));
    showResult(update.result, update.ok);
  };

  window.archgenStreetRestart = function () { send('init'); };

  window.archgenStreetTool = function (active) {
    if (state.mode === 'edit') { return; }
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
    el.accessWidth.value = decimal(defaults.access.width_m);
    el.accessHeight.value = decimal(defaults.access.height_m);
    el.side.value = result.side;
    el.streetField.hidden = result.side !== 'both';
    state.mode = result.mode;
    applyMode();
    if (state.mode === 'edit') {
      send('load_selection');
    } else {
      window.archgenStreetTool(result.tool_active);
      requestPreview();
    }
  }


  function applyMode() {
    var edit = state.mode === 'edit';
    el.title.textContent = edit ? 'Modifier un ensemble' : 'Tracer une rue';
    el.guide.textContent = edit ? 'Le tracé reste celui de l’ensemble : seuls ses réglages changent.'
      : 'Cliquez le départ dans la vue, puis un point par sommet, ou tapez « longueur;angle ». Double-clic ou Échap pour finir.';
    el.replaceWarning.hidden = !edit;
    el.reload.hidden = !edit;
    el.clear.hidden = edit;
    if (edit) { el.resume.hidden = true; }
    state.loaded = false;
    state.ready = false;
    state.digest = null;
    updateButtons();
  }

  function setOptional(input, value) {
    input.value = value === undefined || value === null ? '' : decimal(value);
  }

  // Ce qui a été saisi à la création revient ; le reste suit le style.
  function fill(values) {
    var building = values.building;
    var levels = building.levels || {};
    el.profile.value = building.profile.id;
    el.mode.value = building.mode || 'shell';
    el.lod.value = String(building.lod === undefined ? 0 : building.lod);
    setOptional(el.count, levels.count);
    setOptional(el.height, levels.height_m);
    setOptional(el.target, values.parcel.target_width_m);
    setOptional(el.depth, values.parcel.depth_m);
    setOptional(el.bay, values.parcel.bay_width_m);
    var closed = values.trace.closed;
    el.accessFields.hidden = !closed;
    el.side.disabled = closed;
    if (closed) {
      el.accessCount.value = String(values.access.count);
      setOptional(el.accessWidth, values.access.width_m);
      setOptional(el.accessHeight, values.access.height_m);
      el.streetField.hidden = true;
    } else {
      el.side.value = values.layout.side;
      el.streetField.hidden = values.layout.side !== 'both';
      if (values.layout.street_width_m !== undefined) { setOptional(el.street, values.layout.street_width_m); }
    }
  }

  function onLoaded(response) {
    showDiagnostics(response.diagnostics);
    if (!response.ok) {
      state.loaded = false;
      state.digest = null;
      state.ready = false;
      el.status.textContent = 'Aucun ensemble chargé';
      el.result.textContent = 'Sélectionnez un ensemble, puis cliquez sur Recharger la sélection.';
      el.create.textContent = 'Remplacer cet ensemble';
      updateButtons();
      return;
    }
    state.loaded = true;
    fill(response.result.settings);
    el.status.textContent = 'Révision ' + response.result.revision;
    showEdit(response.result, true);
  }

  function showEdit(result, ok) {
    if (!result) { return; }
    var metrics = result.metrics;
    el.create.textContent = 'Remplacer cet ensemble';
    state.digest = metrics ? result.ensemble_digest : null;
    state.ready = Boolean(ok && metrics && result.changed);
    if (metrics) {
      el.result.textContent = metrics.parcel_count + ' bâtiments, dont ' + metrics.definition_count + ' différents ; ' +
        (metrics.access_count ? metrics.access_count + ' accès à la cour ; ' : '') +
        thousands(metrics.expanded_face_count) + ' faces.' + (result.changed ? '' : ' Aucun changement.');
    } else {
      el.result.textContent = 'Ces réglages ne peuvent pas être construits.';
    }
    updateButtons();
  }

  function onRegenerated(response) {
    state.busy = false;
    state.cooling = true;
    setTimeout(function () { state.cooling = false; updateButtons(); }, COOLDOWN_MS);
    showDiagnostics(response.diagnostics);
    if (response.ok) {
      el.status.textContent = 'Ensemble remplacé. Révision ' + response.result.revision;
      showEdit(response.result, true);
    } else {
      el.status.textContent = 'Remplacement refusé';
      state.ready = false;
      updateButtons();
    }
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

  // Un champ de texte n'écoute que la frappe : `change` part quand il perd le focus, donc au
  // moment du clic sur Créer, et l'aperçu relancé désactiverait le bouton sous la souris.
  Array.prototype.slice.call(document.querySelectorAll('input')).forEach(function (input) {
    input.addEventListener('input', requestPreview);
  });
  Array.prototype.slice.call(document.querySelectorAll('select')).forEach(function (select) {
    select.addEventListener('change', requestPreview);
  });

  el.create.addEventListener('click', function () {
    var values = settings();
    if (!values || !state.digest || state.busy) { return; }
    state.busy = true;
    state.ready = false;
    updateButtons();
    el.status.textContent = 'Écriture en cours…';
    send(state.mode === 'edit' ? 'regenerate' : 'create', { settings: values, ensemble_digest: state.digest });
  });

  el.clear.addEventListener('click', function () { send('clear'); });
  el.resume.addEventListener('click', function () { window.sketchup.archgen_street('activate_tool'); });
  el.reload.addEventListener('click', function () { send('load_selection'); });

  send('init');
}());
