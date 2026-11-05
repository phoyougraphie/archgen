// Panneau ARCHGEN : affiche et transmet. Toute décision vient de Ruby ; le texte passe
// par textContent et aucun tracé n'est reçu sous forme de SVG ou de HTML.
(function () {
  'use strict';

  var L = window.ArchgenLogic;
  var DEBOUNCE_MS = 250;
  var SVG = 'http://www.w3.org/2000/svg';
  var LOCAL_ERROR = 'Saisissez un nombre valide.';
  var CHART_WIDTH = 420;
  var CHART_HEIGHT = 240;
  var CHART_PAD = 22;

  var state = {
    mode: 'new', overrides: {}, profiles: [], profile: null, baseProfile: null, targetToken: null,
    counter: 0, latestPreview: null, pending: {}, timer: null, localErrors: {}, lastConfig: null
  };

  var fields = Array.prototype.slice.call(document.querySelectorAll('[data-path]'));
  var knownPaths = fields.map(function (el) { return el.dataset.path; }).concat(['/roof/type', '/profile']);
  var el = {
    title: byId('title'), status: byId('status'), summary: byId('summary'), summaryList: byId('summary-list'),
    profile: byId('f-profile'), signature: byId('profile-signature'), roof: byId('f-roof'),
    previewSummary: byId('preview-summary'), elevation: byId('elevation'), plan: byId('plan'), warnings: byId('warnings'),
    reload: byId('reload'), reset: byId('reset'), previewBox: document.querySelector('.preview')
  };

  function byId(id) { return document.getElementById(id); }

  function setStatus(text, bad) {
    el.status.textContent = text;
    el.status.classList.toggle('is-bad', Boolean(bad));
  }

  // --- Pont

  function send(action, payload) {
    state.counter += 1;
    var id = L.nextRequestId(state.counter);
    state.pending[id] = action;
    window.sketchup.archgen_dispatch(JSON.stringify({ v: 1, request_id: id, action: action, payload: payload || {} }));
    return id;
  }

  // Ruby appelle ce nom fixe avec une chaîne JSON.
  window.archgenReceive = function (json) {
    var response = JSON.parse(json);
    var action = state.pending[response.request_id];
    delete state.pending[response.request_id];
    if (action === 'init') { onInit(response); }
    else if (action === 'load_selection') { onSelection(response); }
    else if (action === 'preview') { onPreview(response); }
  };

  window.archgenSetMode = function (mode) { startMode(mode); };

  // --- Démarrage

  function onInit(response) {
    if (!response.ok) { return showFailure(response.diagnostics); }
    var result = response.result;
    state.profiles = result.profiles;
    fillSelect(el.profile, result.profiles.map(function (p) { return { value: p.id, label: p.label }; }));
    document.querySelectorAll('[data-catalogue="materials"]').forEach(function (select) {
      fillSelect(select, result.materials.map(function (m) { return { value: m.id, label: m.label }; }));
    });
    startMode(result.mode);
  }

  function fillSelect(select, options) {
    select.textContent = '';
    options.forEach(function (option) {
      var node = document.createElement('option');
      node.value = option.value;
      node.textContent = option.label;
      select.appendChild(node);
    });
  }

  function startMode(mode) {
    state.mode = mode;
    state.overrides = {};
    state.localErrors = {};
    state.targetToken = null;
    el.reload.hidden = mode !== 'edit';
    el.title.textContent = mode === 'edit' ? 'Modifier le bâtiment sélectionné' : 'Nouveau bâtiment';
    if (mode === 'edit') { send('load_selection'); return; }
    chooseProfile(state.profiles[0]);
    requestPreview();
  }

  function chooseProfile(profile) {
    state.profile = profile;
    el.profile.value = profile.id;
    el.signature.textContent = profile.signature;
  }

  function findProfile(id) {
    return state.profiles.filter(function (p) { return p.id === id; })[0];
  }

  function onSelection(response) {
    if (!response.ok) {
      showFailure(response.diagnostics);
      setStatus('Édition indisponible : rechargez la sélection.', true);
      return;
    }
    state.targetToken = response.result.target_token;
    state.baseProfile = response.result.config.profile;
    state.profile = null;
    state.overrides = {};
    var known = findProfile(response.result.config.profile.id);
    if (known) {
      el.profile.value = known.id;
      el.signature.textContent = known.signature;
    }
    fillForm(response.result.config);
    requestPreview();
  }

  // --- Saisie

  function readField(field) {
    var text = field.value;
    switch (field.dataset.kind) {
      case 'number': return L.parseDecimal(text);
      case 'int': return L.parseInteger(text);
      case 'list': return L.parseList(text);
      case 'select': return text;
      case 'select-int': return L.parseInteger(text);
      case 'check': return field.checked;
      default: return text.trim() === '' ? null : text;
    }
  }

  function onFieldInput(event) {
    var field = event.target;
    var value = readField(field);
    var path = field.dataset.path;
    if (value === null) {
      state.localErrors[path] = field.dataset.kind === 'text' ? 'Saisissez un nom.' : LOCAL_ERROR;
      delete state.overrides[path];
      showLocalErrors();
      markStale('Saisie invalide : aperçu non mis à jour.');
      clearTimeout(state.timer);
      return;
    }
    delete state.localErrors[path];
    state.overrides[path] = value;
    showLocalErrors();
    schedule();
  }

  function onProfileChange() {
    var profile = findProfile(el.profile.value);
    chooseProfile(profile);
    state.overrides = L.clearStyleOverrides(state.overrides);
    state.localErrors = {};
    showLocalErrors();
    schedule();
  }

  function onRoofChange() {
    state.overrides = L.withRoofType(state.overrides, el.roof.value);
    Object.keys(state.localErrors).forEach(function (path) {
      if (path.indexOf('/roof/') === 0) { delete state.localErrors[path]; }
    });
    showRoofFields(el.roof.value);
    showLocalErrors();
    schedule();
  }

  function showRoofFields(type) {
    var active = L.activeRoofFields(type);
    document.querySelectorAll('[data-roof]').forEach(function (box) {
      box.hidden = active.indexOf(box.dataset.roof) < 0;
    });
  }

  function schedule() {
    markStale('Modifié');
    clearTimeout(state.timer);
    state.timer = setTimeout(requestPreview, DEBOUNCE_MS);
  }

  function markStale(text) {
    el.previewBox.classList.add('is-stale');
    setStatus(text, Object.keys(state.localErrors).length > 0);
  }

  function requestPreview() {
    if (Object.keys(state.localErrors).length > 0) { return; }
    setStatus('Validation en cours');
    var payload = { draft: L.buildDraft(state.overrides, state.profile) };
    if (state.targetToken) { payload.target_token = state.targetToken; }
    state.latestPreview = send('preview', payload);
  }

  // --- Réponses

  function onPreview(response) {
    if (!L.isCurrent(response.request_id, state.latestPreview)) { return; }
    clearDiagnostics();
    if (!response.ok) { showFailure(response.diagnostics); return; }
    el.previewBox.classList.remove('is-stale');
    fillForm(response.result.config);
    draw(response.result);
    showWarnings(response.diagnostics);
    setStatus('Aperçu prêt');
  }

  function showFailure(diagnostics) {
    clearDiagnostics();
    el.previewBox.classList.add('is-stale');
    var unique = L.uniqueDiagnostics(diagnostics);
    var groups = L.groupDiagnostics(unique, knownPaths);
    Object.keys(groups.byField).forEach(function (path) {
      groups.byField[path].forEach(function (d) { (d.severity === 'error' ? showFieldError : showFieldWarning)(path, L.messageText(d)); });
    });
    var errors = unique.filter(function (d) { return d.severity === 'error'; });
    el.summaryList.textContent = '';
    errors.forEach(function (d) { addSummaryItem(d); });
    el.summary.hidden = errors.length === 0;
    el.warnings.textContent = '';
    setStatus(errors.length ? 'Invalide' : 'Prêt', errors.length > 0);
    if (errors.some(function (d) { return d.code === 'E_TARGET_STALE'; })) { setStatus('Cible périmée', true); }
  }

  function addSummaryItem(diagnostic) {
    var item = document.createElement('li');
    var field = fieldFor(diagnostic.path);
    var text = (diagnostic.field ? diagnostic.field + ' : ' : '') + L.messageText(diagnostic);
    if (field) {
      var button = document.createElement('button');
      button.type = 'button';
      button.textContent = text;
      button.addEventListener('click', function () { focusField(field); });
      item.appendChild(button);
    } else {
      item.textContent = text;
    }
    el.summaryList.appendChild(item);
  }

  function fieldFor(path) {
    if (path === '/roof/type') { return el.roof; }
    if (path === '/profile') { return el.profile; }
    return fields.filter(function (f) { return f.dataset.path === path; })[0];
  }

  // Une erreur dans la section Avancé doit rester atteignable.
  function focusField(field) {
    var details = field.closest('details');
    if (details) { details.open = true; }
    field.focus();
  }

  function messageNode(field, className, text) {
    field.classList.toggle('is-invalid', className === 'error');
    var box = field.closest('.field');
    var node = document.createElement('p');
    node.className = className + ' generated';
    node.textContent = text;
    box.appendChild(node);
    var details = field.closest('details');
    if (details && className === 'error') { details.open = true; }
  }

  function showFieldError(path, text) {
    var field = fieldFor(path);
    if (field) { messageNode(field, 'error', text); }
  }

  function showFieldWarning(path, text) {
    var field = fieldFor(path);
    if (field) { messageNode(field, 'warning', text); }
  }

  function clearDiagnostics() {
    document.querySelectorAll('.generated').forEach(function (n) { n.parentNode.removeChild(n); });
    document.querySelectorAll('.is-invalid').forEach(function (n) { n.classList.remove('is-invalid'); });
    el.summary.hidden = true;
    showLocalErrors();
  }

  function showLocalErrors() {
    document.querySelectorAll('.local').forEach(function (n) { n.parentNode.removeChild(n); });
    Object.keys(state.localErrors).forEach(function (path) {
      var field = fieldFor(path);
      if (!field) { return; }
      field.classList.add('is-invalid');
      var node = document.createElement('p');
      node.className = 'error local';
      node.textContent = state.localErrors[path];
      field.closest('.field').appendChild(node);
    });
    fields.forEach(function (field) {
      if (!state.localErrors[field.dataset.path] && !field.closest('.field').querySelector('.generated.error')) {
        field.classList.remove('is-invalid');
      }
    });
  }

  function showWarnings(diagnostics) {
    el.warnings.textContent = '';
    L.uniqueDiagnostics(diagnostics).forEach(function (d) {
      if (d.severity !== 'warning') { return; }
      var item = document.createElement('li');
      item.textContent = (d.field ? d.field + ' : ' : '') + L.messageText(d);
      el.warnings.appendChild(item);
      showFieldWarning(d.path, L.messageText(d));
    });
  }

  // --- Remplissage : les valeurs saisies ne sont pas écrasées

  function fillForm(config) {
    state.lastConfig = config;
    var active = document.activeElement;
    fields.forEach(function (field) {
      var path = field.dataset.path;
      if (field === active || state.localErrors[path] !== undefined) { return; }
      if (Object.prototype.hasOwnProperty.call(state.overrides, path) && field.dataset.kind !== 'check') { return; }
      writeField(field, L.getPath(config, path));
    });
    el.roof.value = config.roof.type;
    showRoofFields(config.roof.type);
  }

  function writeField(field, value) {
    switch (field.dataset.kind) {
      case 'number': field.value = L.formatNumber(value); break;
      case 'list': field.value = L.formatList(value); break;
      case 'check': field.checked = Boolean(value); break;
      default: field.value = value === undefined || value === null ? '' : String(value);
    }
  }

  // --- Tracés : uniquement des coordonnées numériques reçues du noyau

  function draw(result) {
    var projection = result.projection;
    var front = projection.front_elevation;
    var plan = projection.plan_view;
    var elevationExtent = L.extentOf([front.wall_contour, front.roof_silhouette]);
    var planExtent = L.extentOf([plan.footprint, plan.roof_outline]);
    var scale = L.commonScale([elevationExtent, planExtent], CHART_WIDTH - (2 * CHART_PAD), CHART_HEIGHT - (2 * CHART_PAD));
    drawElevation(front, elevationExtent, scale, result.metrics);
    drawPlan(plan, planExtent, scale, result.metrics);
    el.previewSummary.textContent = L.summaryText(projection.summary, result.metrics);
  }

  function prepareSvg(svg, extent, scale) {
    svg.textContent = '';
    var width = Math.ceil((extent.width * scale) + (2 * CHART_PAD));
    var height = Math.ceil((extent.height * scale) + (2 * CHART_PAD));
    svg.setAttribute('viewBox', '0 0 ' + width + ' ' + height);
    svg.setAttribute('width', width);
    svg.setAttribute('height', height);
    return function (point) {
      return [CHART_PAD + ((point[0] - extent.minX) * scale), height - CHART_PAD - ((point[1] - extent.minY) * scale)];
    };
  }

  function shape(svg, name, attributes) {
    var node = document.createElementNS(SVG, name);
    Object.keys(attributes).forEach(function (key) { node.setAttribute(key, attributes[key]); });
    svg.appendChild(node);
    return node;
  }

  function polygon(svg, points, toScreen, className) {
    if (points.length < 2) { return; }
    var list = points.map(function (p) { return toScreen(p).join(','); }).join(' ');
    shape(svg, 'polygon', { points: list, class: className });
  }

  function label(svg, x, y, text, anchor) {
    var node = shape(svg, 'text', { x: x, y: y, 'text-anchor': anchor || 'middle' });
    node.textContent = text;
  }

  function dimensions(svg, extent, toScreen, widthLabel, heightLabel) {
    var bottomLeft = toScreen([extent.minX, extent.minY]);
    var bottomRight = toScreen([extent.maxX, extent.minY]);
    var topLeft = toScreen([extent.minX, extent.maxY]);
    shape(svg, 'line', { x1: bottomLeft[0], y1: bottomLeft[1] + 5, x2: bottomRight[0], y2: bottomRight[1] + 5, class: 'axis' });
    label(svg, (bottomLeft[0] + bottomRight[0]) / 2, bottomLeft[1] + 17, widthLabel);
    shape(svg, 'line', { x1: bottomLeft[0] - 5, y1: bottomLeft[1], x2: topLeft[0] - 5, y2: topLeft[1], class: 'axis' });
    label(svg, topLeft[0] + 2, topLeft[1] - 6, heightLabel, 'start');
  }

  // Les cotes affichées sont celles du plan, hors débords ; la ligne suit le tracé.
  function drawElevation(front, extent, scale, metrics) {
    var svg = el.elevation;
    var toScreen = prepareSvg(svg, extent, scale);
    polygon(svg, front.roof_silhouette, toScreen, 'roof');
    polygon(svg, front.wall_contour, toScreen, 'wall');
    front.openings.forEach(function (o) {
      var a = toScreen([o.x_min_m, o.z_max_m]);
      var b = toScreen([o.x_max_m, o.z_min_m]);
      shape(svg, 'rect', { x: a[0], y: a[1], width: b[0] - a[0], height: b[1] - a[1], class: o.kind });
    });
    dimensions(svg, extent, toScreen, 'X ' + L.formatNumber(round(metrics.width_m)) + ' m', 'Z ' + L.formatNumber(round(metrics.roof_top_z_m)) + ' m');
  }

  function drawPlan(plan, extent, scale, metrics) {
    var svg = el.plan;
    var toScreen = prepareSvg(svg, extent, scale);
    polygon(svg, plan.footprint, toScreen, 'wall');
    polygon(svg, plan.roof_outline, toScreen, 'roof-line');
    dimensions(svg, extent, toScreen, 'X ' + L.formatNumber(round(metrics.width_m)) + ' m', 'Y ' + L.formatNumber(round(metrics.depth_m)) + ' m');
  }

  function round(value) {
    return Math.round(value * 100) / 100;
  }

  // --- Événements

  fields.forEach(function (field) {
    field.addEventListener(field.dataset.kind === 'check' || field.tagName === 'SELECT' ? 'change' : 'input', onFieldInput);
  });
  el.profile.addEventListener('change', onProfileChange);
  el.roof.addEventListener('change', onRoofChange);
  el.reload.addEventListener('click', function () { startMode('edit'); });
  el.reset.addEventListener('click', function () {
    state.overrides = {};
    state.localErrors = {};
    showLocalErrors();
    requestPreview();
  });
  byId('form').addEventListener('submit', function (event) { event.preventDefault(); });

  if (!window.sketchup) {
    setStatus('Ouvrez ce panneau depuis SketchUp.', true);
    return;
  }
  setStatus('Validation en cours');
  send('init');
}());
