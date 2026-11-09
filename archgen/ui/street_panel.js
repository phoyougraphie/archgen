// Panneau de rue : affiche et transmet. Le tracé vient de l'outil, toute décision vient de
// Ruby ; le texte passe par textContent.
(function () {
  'use strict';

  var DEBOUNCE_MS = 300;
  var COOLDOWN_MS = 700;
  var state = { counter: 0, pending: {}, timer: null, digest: null, ready: false, busy: false, cooling: false, localError: null, mode: 'new', loaded: false, touched: {} };

  function byId(id) { return document.getElementById(id); }
  var el = {
    status: byId('status'), summary: byId('summary'), summaryList: byId('summary-list'), result: byId('result'), warnings: byId('warnings'),
    profile: byId('s-profile'), mode: byId('s-mode'), lod: byId('s-lod'), count: byId('s-count'), height: byId('s-height'),
    side: byId('s-side'), streetField: byId('s-street-field'), street: byId('s-street'), target: byId('s-target'), depth: byId('s-depth'), bay: byId('s-bay'),
    accessFields: byId('s-access-fields'), accessCount: byId('s-access-count'), accessWidth: byId('s-access-width'), accessHeight: byId('s-access-height'),
    title: byId('title'), guide: byId('guide'), replaceWarning: byId('replace-warning'), reload: byId('reload'),
    create: byId('create'), clear: byId('clear'), resume: byId('resume'),
    terrain: byId('s-terrain'), siteRetain: byId('site-retain'), sitePolicy: byId('s-site-policy'), siteOffset: byId('s-site-offset'), siteMaterial: byId('s-site-material'),
    glazing: byId('s-glazing'), chimneys: byId('s-chimneys'), muntins: byId('s-muntins'), shutters: byId('s-shutters'), dormers: byId('s-dormers'), shop: byId('s-shop'), shopHeight: byId('s-shop-height'),
    shopHeightField: byId('s-shop-height-field'), custom: byId('s-custom'), customField: byId('s-custom-field'), customLabel: byId('s-custom-label'),
    variety: byId('s-variety'), vmin: byId('s-vmin'), vmax: byId('s-vmax'), vstep: byId('s-vstep'), seed: byId('s-seed'),
    roofs: Array.prototype.slice.call(document.querySelectorAll('input[data-roof]')),
    siteStep: byId('s-site-step'), siteSurvey: byId('site-survey'), siteAdapt: byId('site-adapt'), siteRemove: byId('site-remove'), siteLines: byId('site-lines')
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
    var values = [count, height, number(el.street), number(el.target), number(el.depth), number(el.bay), number(el.accessWidth), number(el.accessHeight),
      number(el.vmin), number(el.vmax), number(el.vstep), number(el.seed), number(el.shopHeight)];
    state.localError = values.some(function (v) { return v !== null && isNaN(v); }) ? 'Saisissez un nombre valide.' : null;
    if (!state.localError && el.variety.checked && (number(el.vmin) === null || number(el.vmax) === null)) {
      state.localError = 'Saisissez la fourchette de niveaux.';
    }
    if (state.localError) { return null; }
    if (count !== null) { levels.count = count; }
    if (height !== null) { levels.height_m = height; }
    if (count !== null || height !== null) { building.levels = levels; }
    details(building);
    var parcel = {};
    if (number(el.target) !== null) { parcel.target_width_m = number(el.target); }
    if (number(el.depth) !== null) { parcel.depth_m = number(el.depth); }
    if (number(el.bay) !== null) { parcel.bay_width_m = number(el.bay); }
    var layout = { side: el.side.value };
    if (el.side.value === 'both' && number(el.street) !== null) { layout.street_width_m = number(el.street); }
    var access = { count: el.accessCount.value === 'auto' ? 'auto' : Number(el.accessCount.value) };
    if (number(el.accessWidth) !== null) { access.width_m = number(el.accessWidth); }
    if (number(el.accessHeight) !== null) { access.height_m = number(el.accessHeight); }
    var out = { building: building, parcel: parcel, layout: layout, access: access, variety: variety() };
    if (number(el.seed) !== null) { out.seed = number(el.seed); }
    // AG-069 : retirer d'un coup les réglages propres posés au clic droit.
    if (state.mode === 'edit' && el.custom.checked) { out.parcels = null; }
    return out;
  }

  // AG-067 : une case Détails n'est envoyée que si on l'a touchée ; sinon la rue suit son style.
  function details(building) {
    var features = {};
    if (state.touched.glazing) { features.glazing = el.glazing.checked; }
    if (state.touched.chimneys) { features.chimneys = el.chimneys.checked; }
    ['muntins', 'shutters', 'dormers'].forEach(function (key) {
      if (state.touched[key]) { features[key] = el[key].checked; }
    });
    if (Object.keys(features).length) { building.features = features; }
    if (state.touched.shop) { building.ground_floor = el.shop.checked ? 'shop' : 'dwelling'; }
    if (el.shop.checked && number(el.shopHeight) !== null) { building.shop = { height_m: number(el.shopHeight) }; }
  }

  // Cases du style, ou celles enregistrées ; un style d'une autre révision n'a ni vitrage ni cheminées.
  function fillDetails(building) {
    var hints = (state.profiles[el.profile.value] || {}).details || {};
    var stored = building ? building.features || {} : {};
    var sameRevision = !building || !building.profile.revision || building.profile.revision === hints.revision;
    el.glazing.checked = stored.glazing !== undefined ? stored.glazing : sameRevision && Boolean(hints.glazing);
    el.chimneys.checked = stored.chimneys !== undefined ? stored.chimneys : sameRevision && Boolean(hints.chimneys);
    ['muntins', 'shutters', 'dormers'].forEach(function (key) {
      el[key].checked = stored[key] !== undefined ? stored[key] : sameRevision && Boolean(hints[key]);
    });
    el.shop.checked = Boolean(building) && building.ground_floor === 'shop';
    el.shopHeight.value = building && building.shop && building.shop.height_m !== undefined ? decimal(building.shop.height_m) : '';
    el.shopHeight.placeholder = hints.shop_height_m === undefined ? '' : decimal(hints.shop_height_m);
    state.touched = {};
    showShopHeight();
  }

  function showShopHeight() {
    el.shopHeightField.hidden = !el.shop.checked;
  }

  // Case décochée : null, la rue garde un seul gabarit (et la variété enregistrée est retirée).
  function variety() {
    if (!el.variety.checked) { return null; }
    var levels = { min: number(el.vmin), max: number(el.vmax) };
    if (number(el.vstep) !== null) { levels.max_step = number(el.vstep); }
    var roofs = el.roofs.filter(function (box) { return box.checked; }).map(function (box) { return box.getAttribute('data-roof'); });
    return roofs.length ? { levels: levels, roofs: roofs } : { levels: levels };
  }

  var ROOF_WORDS = { flat: ['toit plat', 'toits plats'], gable: ['toit à deux pans', 'toits à deux pans'], mansard: ['mansarde', 'mansardes'] };

  // La répartition tirée, annoncée avant d'écrire : « de 3 à 7 niveaux, 2 toits plats, 4 mansardes ».
  function varietyText(drawn) {
    if (!drawn) { return ''; }
    var levels = Object.keys(drawn.levels || {}).map(Number).sort(function (a, b) { return a - b; });
    var parts = [];
    if (levels.length === 1) { parts.push(levels[0] + (levels[0] > 1 ? ' niveaux partout' : ' niveau partout')); }
    if (levels.length > 1) { parts.push('de ' + levels[0] + ' à ' + levels[levels.length - 1] + ' niveaux'); }
    Object.keys(drawn.roofs || {}).forEach(function (roof) {
      var n = drawn.roofs[roof];
      var words = ROOF_WORDS[roof] || [roof, roof];
      parts.push(n + ' ' + (n > 1 ? words[1] : words[0]));
    });
    return parts.length ? ' Tirage : ' + parts.join(', ') + '.' : '';
  }

  function toggleVariety() {
    Array.prototype.slice.call(document.querySelectorAll('input[data-variety]')).forEach(function (input) { input.disabled = !el.variety.checked; });
  }

  // Le style dit ses toits et sa fourchette : ce sont les valeurs proposées ; un toit hors style
  // reste possible, signalé par le style au moment de l'aperçu.
  function applyStyle(reset) {
    var profile = state.profiles[el.profile.value] || { roofs: ['flat', 'gable', 'mansard'] };
    el.roofs.forEach(function (box) {
      var roof = box.getAttribute('data-roof');
      var inStyle = profile.roofs.indexOf(roof) !== -1;
      var label = byId(box.id + '-label');
      label.textContent = label.textContent.replace(' (hors style)', '') + (inStyle ? '' : ' (hors style)');
      if (reset) { box.checked = inStyle; }
    });
    if (reset) {
      var levels = profile.levels || { min: 3, max: 6 };
      el.vmin.value = String(levels.min);
      el.vmax.value = String(levels.max);
      el.vstep.value = '2';
    }
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
el.siteSurvey.disabled = state.busy || !state.loaded;
el.siteAdapt.disabled = state.busy || state.cooling || !state.siteDigest;
el.siteRemove.disabled = state.busy || state.cooling || !state.hasSite;
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
        varietyText(result.variety) + (finished ? '' : ' Tracé en cours.');
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
if (action === 'retain_terrain') { onRetained(response); return; }
if (action === 'site_preview') { onSitePreview(response); return; }
if (action === 'adapt_site' || action === 'remove_site') { onSiteWritten(response, action); return; }
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
    state.profiles = {};
    result.profiles.forEach(function (profile) {
      state.profiles[profile.id] = profile;
      var option = document.createElement('option');
      option.value = profile.id;
      option.textContent = profile.label;
      el.profile.appendChild(option);
    });
    var defaults = result.defaults;
    el.profile.value = defaults.building.profile.id;
    el.mode.value = defaults.building.mode;
    el.lod.value = String(defaults.building.lod);
    el.seed.value = '1';
    el.variety.checked = false;
    applyStyle(true);
    fillDetails(null);
    toggleVariety();
    el.target.value = decimal(defaults.parcel.target_width_m);
    el.depth.value = decimal(defaults.parcel.depth_m);
    el.bay.value = decimal(defaults.parcel.bay_width_m);
    el.street.value = decimal(defaults.layout.street_width_m);
    el.accessWidth.value = decimal(defaults.access.width_m);
el.accessHeight.value = decimal(defaults.access.height_m);
el.siteMaterial.textContent = '';
result.site_materials.forEach(function (material) {
  var option = document.createElement('option');
  option.value = material.id;
  option.textContent = material.label;
  el.siteMaterial.appendChild(option);
});
state.siteDefaults = result.site_defaults;
fillSite(result.site_defaults);
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
    el.terrain.hidden = !edit;
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

function fillSite(values) {
  el.sitePolicy.value = values.platform.policy;
  el.siteOffset.value = decimal(values.platform.offset_m);
  el.siteMaterial.value = values.plinth_material;
  el.siteStep.value = decimal(values.survey.step_m);
}

function siteValues() {
  var offset = number(el.siteOffset);
  var step = number(el.siteStep);
  if (offset === null || isNaN(offset) || step === null || isNaN(step)) { return null; }
  return { platform: { policy: el.sitePolicy.value, offset_m: offset }, plinth_material: el.siteMaterial.value, survey: { step_m: step } };
}

function showSiteState(site) {
  state.hasSite = Boolean(site && site.has_site);
  if (state.hasSite) { fillSite(site.settings); }
  if (site && site.moved) { fillList(el.siteLines, ['L’ensemble a bougé depuis son adaptation : relevez de nouveau.']); el.siteLines.hidden = false; }
}

function resetSitePreview() {
  state.siteDigest = null;
  el.siteLines.textContent = '';
  el.siteLines.hidden = true;
  updateButtons();
}

function onRetained(response) {
  showDiagnostics(response.diagnostics);
  el.status.textContent = response.ok ? 'Terrain retenu. Resélectionnez l’ensemble, puis rechargez.' : 'Terrain refusé';
  if (response.ok) { state.loaded = false; state.ready = false; resetSitePreview(); }
}

function onSitePreview(response) {
  state.busy = false;
  showDiagnostics(response.diagnostics);
  state.siteDigest = response.ok ? response.result.site_digest : null;
  fillList(el.siteLines, response.ok ? response.result.lines : []);
  el.siteLines.hidden = !response.ok;
    // Le pied collant ne doit pas cacher les valeurs à vérifier.
    if (response.ok) { el.siteLines.scrollIntoView({ block: 'center' }); }
  el.status.textContent = response.ok ? 'Relevé terminé. Vérifiez les valeurs avant d’adapter.' : 'Relevé refusé';
  updateButtons();
}

function onSiteWritten(response, action) {
  state.busy = false;
  state.cooling = true;
  setTimeout(function () { state.cooling = false; updateButtons(); }, COOLDOWN_MS);
  showDiagnostics(response.diagnostics);
  resetSitePreview();
  if (response.ok) {
    showSiteState(response.result.site);
    el.status.textContent = (action === 'adapt_site' ? 'Ensemble adapté au terrain. Révision ' : 'Assise retirée. Révision ') + response.result.revision;
  } else {
    el.status.textContent = action === 'adapt_site' ? 'Adaptation refusée' : 'Retrait refusé';
  }
  updateButtons();
}

// Le relevé bloque SketchUp : le message doit s'afficher avant.
function runSite(message, action, payload) {
  state.busy = true;
  el.status.textContent = message;
  updateButtons();
  setTimeout(function () { send(action, payload); }, 30);
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
    el.seed.value = values.seed === undefined ? '1' : String(values.seed);
    fillDetails(building);
    var drawn = values.variety;
    el.variety.checked = Boolean(drawn);
    applyStyle(!drawn);
    if (drawn) {
      el.vmin.value = String(drawn.levels.min);
      el.vmax.value = String(drawn.levels.max);
      el.vstep.value = drawn.levels.max_step === undefined ? '2' : String(drawn.levels.max_step);
      // Sans liste, chaque parcelle garde le toit du bâtiment : aucune case cochée.
      el.roofs.forEach(function (box) { box.checked = Boolean(drawn.roofs) && drawn.roofs.indexOf(box.getAttribute('data-roof')) !== -1; });
    }
    toggleVariety();
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
    resetSitePreview();
    showSiteState(response.result.site);
    fill(response.result.settings);
    var custom = response.result.custom_count || 0;
    el.custom.checked = false;
    el.customField.hidden = custom === 0;
    el.customLabel.textContent = 'Retirer les réglages propres de ' + custom + ' bâtiment(s) personnalisé(s) au clic droit';
    el.status.textContent = 'Révision ' + response.result.revision + (custom ? ', ' + custom + ' bâtiment(s) personnalisé(s)' : '');
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
        thousands(metrics.expanded_face_count) + ' faces.' + varietyText(result.variety) + (result.changed ? '' : ' Aucun changement.');
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
  Array.prototype.slice.call(document.querySelectorAll('input:not([data-site])')).forEach(function (input) {
    input.addEventListener('input', requestPreview);
  });
  Array.prototype.slice.call(document.querySelectorAll('select:not([data-site])')).forEach(function (select) {
    select.addEventListener('change', requestPreview);
  });
  // Un réglage de terrain changé rend l'aperçu de l'assise caduc, sans toucher à celui de l'ensemble.
  Array.prototype.slice.call(document.querySelectorAll('input[data-site]')).forEach(function (input) {
    input.addEventListener('input', resetSitePreview);
  });
  Array.prototype.slice.call(document.querySelectorAll('select[data-site]')).forEach(function (select) {
    select.addEventListener('change', resetSitePreview);
  });

  el.variety.addEventListener('change', function () { toggleVariety(); requestPreview(); });
  el.roofs.forEach(function (box) { box.addEventListener('change', requestPreview); });
  // Un autre style propose ses toits et sa fourchette, tant que la variété n'est pas choisie.
  el.profile.addEventListener('change', function () {
    applyStyle(!el.variety.checked);
    // Un autre style propose ses cases Détails, sauf celles qu'on a touchées.
    var hints = (state.profiles[el.profile.value] || {}).details || {};
    if (!state.touched.glazing) { el.glazing.checked = Boolean(hints.glazing); }
    if (!state.touched.chimneys) { el.chimneys.checked = Boolean(hints.chimneys); }
    ['muntins', 'shutters', 'dormers'].forEach(function (key) {
      if (!state.touched[key]) { el[key].checked = Boolean(hints[key]); }
    });
    el.shopHeight.placeholder = hints.shop_height_m === undefined ? '' : decimal(hints.shop_height_m);
  });
  Array.prototype.slice.call(document.querySelectorAll('input[data-detail]')).forEach(function (box) {
    box.addEventListener('change', function () { state.touched[box.getAttribute('data-detail')] = true; showShopHeight(); requestPreview(); });
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
el.siteRetain.addEventListener('click', function () { send('retain_terrain'); });
el.siteSurvey.addEventListener('click', function () {
  var site = siteValues();
  if (!site) { el.status.textContent = 'Saisissez un décalage et un pas valides.'; return; }
  runSite('Relevé du terrain en cours…', 'site_preview', { site: site });
});
el.siteAdapt.addEventListener('click', function () {
  var site = siteValues();
  if (!site || !state.siteDigest) { return; }
  runSite('Adaptation en cours : relevé, puis écriture…', 'adapt_site', { site: site, site_digest: state.siteDigest });
});
el.siteRemove.addEventListener('click', function () { runSite('Retrait en cours…', 'remove_site', {}); });

  send('init');
}());
