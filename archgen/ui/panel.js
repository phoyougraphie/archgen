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
    counter: 0, latestPreview: null, pending: {}, timer: null, localErrors: {}, lastConfig: null,
    previewReady: false, previewDraft: null, confirmation: null, busy: false, cooling: false, editStale: false, notice: null, keptDraft: null, pendingMessage: null,
    site: { terrainToken: null, status: null, preview: null, confirmation: null, confirmMode: null, errors: {} }
  };
  var COOLDOWN_MS = 700;

  var fields = Array.prototype.slice.call(document.querySelectorAll('[data-path]'));
  var siteFields = Array.prototype.slice.call(document.querySelectorAll('[data-site-path]'));
  var knownPaths = fields.map(function (el) { return el.dataset.path; }).concat(['/roof/type', '/profile'])
    .concat(siteFields.map(function (el) { return '/site' + el.dataset.sitePath; }));
  var el = {
    title: byId('title'), status: byId('status'), summary: byId('summary'), summaryList: byId('summary-list'),
    profile: byId('f-profile'), signature: byId('profile-signature'), roof: byId('f-roof'),
    previewSummary: byId('preview-summary'), elevation: byId('elevation'), plan: byId('plan'), warnings: byId('warnings'),
    reload: byId('reload'), reset: byId('reset'), previewBox: document.querySelector('.preview'),
    write: byId('generate'), newBuilding: byId('new-building'), confirm: byId('confirm'),
    confirmMessage: byId('confirm-message'), confirmChanges: byId('confirm-changes'), confirmChangesTitle: byId('confirm-changes-title'),
    confirmYes: byId('confirm-yes'), confirmNo: byId('confirm-no'),
    terrain: byId('terrain'), siteState: byId('site-state'), siteSummary: byId('site-summary'), siteWarnings: byId('site-warnings'),
    siteRetain: byId('site-retain'), siteSurvey: byId('site-survey'), siteAdapt: byId('site-adapt'), siteRemove: byId('site-remove'),
    siteRatio: byId('site-ratio'), earthwork: byId('f-earthwork')
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
    else if (action === 'generate') { onWritten(response, 'Bâtiment créé.'); }
    else if (action === 'regenerate') { onWritten(response, 'Bâtiment régénéré.'); }
    else if (action === 'retain_terrain') { onRetained(response); }
    else if (action === 'site_status') { onSiteStatus(response); }
    else if (action === 'site_preview') { onSitePreview(response); }
    else if (action === 'site_remove_preview') { onSiteRemovePreview(response); }
    else if (action === 'adapt_site') { onSiteWritten(response, 'Bâtiment adapté au terrain.'); }
    else if (action === 'remove_site') { onSiteWritten(response, 'Assise retirée.'); }
  };

  window.archgenSetMode = function (mode) { startMode(mode); };

  // Ruby prévient : annulation, rétablissement, sélection, document, enregistrement.
  window.archgenNotify = function (json) {
    var notice = JSON.parse(json);
    closeConfirm();
    state.confirmation = null;
    forgetSitePreview();
    // Le jeton de terrain est lié au document : enregistrer ou en changer le périme.
    if (notice.reason === 'document' || notice.reason === 'saved') { state.site.terrainToken = null; }
    if (state.mode !== 'edit') {
      if (notice.reason === 'document') { requestPreview(); }
      updateWrite();
      return;
    }
    // Enregistrer change l'identité du document : la sélection se recharge sans perte.
    if (notice.reason === 'saved') {
      if (!state.busy) {
        state.keptDraft = { overrides: state.overrides, profile: state.profile };
        send('load_selection');
      }
      return;
    }
    state.editStale = true;
    el.previewBox.classList.add('is-stale');
    setStatus('Cible périmée', true);
    showGeneralMessage(notice.message);
    updateWrite();
    showSite();
  };

  // --- Démarrage

  function onInit(response) {
    if (!response.ok) { return showFailure(response.diagnostics); }
    var result = response.result;
    state.profiles = result.profiles;
    fillSelect(el.profile, result.profiles.map(function (p) { return { value: p.id, label: p.label, group: p.family }; }));
    document.querySelectorAll('[data-catalogue="materials"]').forEach(function (select) {
      fillSelect(select, result.materials.map(function (m) { return { value: m.id, label: m.label }; }));
    });
    fillSite(result.site);
    startMode(result.mode);
  }

  // Avec `group`, les options se rangent sous un optgroup par groupe, dans l'ordre reçu.
  function fillSelect(select, options) {
    select.textContent = '';
    var groups = {};
    options.forEach(function (option) {
      var node = document.createElement('option');
      node.value = option.value;
      node.textContent = option.label;
      var parent = select;
      if (option.group) {
        if (!groups[option.group]) {
          groups[option.group] = document.createElement('optgroup');
          groups[option.group].label = option.group;
          select.appendChild(groups[option.group]);
        }
        parent = groups[option.group];
      }
      parent.appendChild(node);
    });
  }

  function startMode(mode) {
    state.mode = mode;
    state.overrides = {};
    state.localErrors = {};
    state.targetToken = null;
    state.confirmation = null;
    state.editStale = false;
    state.previewReady = false;
    state.notice = null;
    closeConfirm();
    showMode();
    if (mode === 'edit') { send('load_selection'); return; }
    chooseProfile(state.profiles[0]);
    requestPreview();
  }

  function showMode() {
    var edit = state.mode === 'edit';
    el.reload.hidden = !edit;
    el.newBuilding.hidden = !edit;
    el.title.textContent = edit ? 'Modifier le bâtiment sélectionné' : 'Nouveau bâtiment';
    el.write.textContent = edit ? 'Régénérer' : 'Générer';
    el.reset.textContent = edit ? 'Annuler mes modifications' : 'Revenir aux valeurs du style';
    el.terrain.hidden = !edit;
    updateWrite();
    showSite();
  }

  function updateWrite() {
    el.write.disabled = !L.canWrite({
      mode: state.mode, busy: state.busy, cooling: state.cooling, editStale: state.editStale, previewReady: state.previewReady,
      localErrorCount: Object.keys(state.localErrors).length, confirmation: state.confirmation
    });
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
    var kept = state.keptDraft;
    state.keptDraft = null;
    if (!response.ok) {
      state.targetToken = null;
      state.previewReady = false;
      state.editStale = true;
      showFailure(response.diagnostics);
      setStatus('Édition indisponible : rechargez la sélection.', true);
      updateWrite();
      return;
    }
    enterEdit(response.result.target_token, response.result.config);
    // Un enregistrement ne doit pas effacer les réglages encore non appliqués.
    if (kept) {
      state.overrides = kept.overrides;
      state.profile = kept.profile;
      if (kept.profile) { el.profile.value = kept.profile.id; }
      fields.forEach(function (field) {
        var path = field.dataset.path;
        if (Object.prototype.hasOwnProperty.call(kept.overrides, path)) { writeField(field, kept.overrides[path]); }
      });
    }
    requestPreview();
  }

  // Une racine connue : création réussie, régénération réussie ou sélection rechargée.
  function enterEdit(token, config) {
    state.mode = 'edit';
    state.targetToken = token;
    state.baseProfile = config.profile;
    state.profile = null;
    state.overrides = {};
    state.localErrors = {};
    state.editStale = false;
    state.confirmation = null;
    forgetSitePreview();
    state.site.status = null;
    send('site_status', { target_token: token });
    showMode();
    showLocalErrors();
    var known = findProfile(config.profile.id);
    if (known) {
      el.profile.value = known.id;
      el.signature.textContent = known.signature;
    }
    fillForm(config);
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
      case 'tint': return L.parseInteger(text);
      case 'entrance': return text;
      case 'rail': return text;
      case 'balconies': return text;
      case 'bow': return text;
      case 'bell': return text;
      case 'wing': return wingValue(text);
      case 'check': return field.checked;
      case 'ground': return field.checked ? 'shop' : 'dwelling';
      default: return text.trim() === '' ? null : text;
    }
  }

  // AG-138 : la forme envoie l'aile entière ; « none » la retire.
  function wingValue(position) {
    var width = L.parseDecimal(document.getElementById('f-wing-width').value);
    var depth = L.parseDecimal(document.getElementById('f-wing-depth').value);
    return { position: position, width_m: width === null ? 4 : width, depth_m: depth === null ? 5 : depth };
  }

  function writeWing(field, value) {
    field.value = value ? value.position : 'none';
    document.getElementById('f-wing-width').value = value ? String(value.width_m).replace('.', ',') : '';
    document.getElementById('f-wing-depth').value = value ? String(value.depth_m).replace('.', ',') : '';
  }

  function onFieldInput(event) {
    var field = event.target;
    if (field.id === 'f-shop' || field.id === 'f-shutters' || field.id === 'f-cladding' || field.id === 'f-timber' || field.id === 'f-shopfront') { showShopHeight(); }
    var value = readField(field);
    var path = field.dataset.path;
    if (value === null) {
      state.localErrors[path] = field.dataset.kind === 'text' ? 'Saisissez un nom.' : LOCAL_ERROR;
      delete state.overrides[path];
      showLocalErrors();
      markStale('Saisie invalide : aperçu non mis à jour.');
      clearTimeout(state.timer);
      updateWrite();
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
    // Revenir au style enregistré n'est pas un changement de style.
    if (state.mode === 'edit' && state.baseProfile && profile.id === state.baseProfile.id) { state.profile = null; }
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

  // Toute nouvelle saisie ferme la confirmation : elle ne vaut que pour l'aperçu montré.
  function markStale(text) {
    state.previewReady = false;
    state.confirmation = null;
    state.notice = null;
    closeConfirm();
    state.site.confirmMode = null;
    el.previewBox.classList.add('is-stale');
    setStatus(text, Object.keys(state.localErrors).length > 0);
    updateWrite();
  }

  function requestPreview() {
    if (Object.keys(state.localErrors).length > 0) { return; }
    if (state.mode === 'edit' && !state.targetToken) { return; }
    if (!state.notice) { setStatus('Validation en cours'); }
    state.previewReady = false;
    state.confirmation = null;
    updateWrite();
    state.previewDraft = L.buildDraft(state.overrides, state.profile);
    var payload = { draft: state.previewDraft };
    if (state.targetToken) { payload.target_token = state.targetToken; }
    state.latestPreview = send('preview', payload);
  }

  // --- Écriture

  function onWriteClick() {
    if (el.write.disabled) { return; }
    if (state.mode === 'edit') { openConfirm(); return; }
    startWriting();
    send('generate', { draft: state.previewDraft });
  }

  function startWriting() {
    state.busy = true;
    state.cooling = true;
    closeConfirm();
    setStatus('Écriture en cours');
    updateWrite();
    showSite();
  }

  // Le second clic d'un double clic arrive après la réponse : il ne doit rien déclencher.
  function endWriting() {
    state.busy = false;
    setTimeout(function () {
      state.cooling = false;
      updateWrite();
      showSite();
    }, COOLDOWN_MS);
  }

  function openConfirm() {
    var confirmation = state.confirmation;
    el.confirmMessage.textContent = confirmation.message;
    el.confirmChanges.textContent = '';
    confirmation.changes.forEach(function (change) {
      var item = document.createElement('li');
      item.textContent = change.label + ' : ' + change.from + ' → ' + change.to;
      el.confirmChanges.appendChild(item);
    });
    el.confirmChanges.hidden = confirmation.changes.length === 0;
    el.confirmChangesTitle.textContent = confirmation.changes.length === 0 ? 'Aucun réglage ne change : la géométrie sera recréée à l’identique.' : 'Changements';
    el.confirm.hidden = false;
    el.write.disabled = true;
    el.confirmChanges.scrollTop = 0;
    el.confirmYes.focus();
    el.confirmChanges.scrollTop = 0;
  }

  function closeConfirm() {
    el.confirm.hidden = true;
  }

  function onConfirmYes() {
    if (state.site.confirmMode) { return onSiteConfirmYes(); }
    var confirmation = state.confirmation;
    if (!confirmation || state.busy) { return; }
    state.confirmation = null;
    startWriting();
    send('regenerate', { draft: state.previewDraft, target_token: state.targetToken, confirmation_token: confirmation.token });
  }

  // Annuler garde le brouillon et la sélection ; confirmer exigera un aperçu frais.
  function onConfirmNo() {
    if (state.site.confirmMode) {
      closeConfirm();
      forgetSitePreview();
      setStatus('Assise non modifiée : relevez de nouveau pour confirmer.');
      showSite();
      el.siteSurvey.focus();
      return;
    }
    closeConfirm();
    requestPreview();
    el.write.focus();
  }

  function onWritten(response, successText) {
    endWriting();
    if (response.ok) {
      state.notice = successText + ' Révision ' + response.result.revision + '.';
      clearDiagnostics();
      enterEdit(response.result.target_token, response.result.config);
      requestPreview();
      return;
    }
    var recovery = L.recoveryFor(response.diagnostics);
    showFailure(response.diagnostics);
    if (recovery === 'preview') {
      // Le brouillon est conservé : on redemande un aperçu frais, sans écrire.
      state.pendingMessage = response.diagnostics.map(function (d) { return d.message; })[0];
      requestPreview();
      showGeneralMessage(state.pendingMessage);
      return;
    }
    if (recovery === 'reload') { state.editStale = true; }
    updateWrite();
    el.summary.focus();
  }

  function showGeneralMessage(text) {
    el.summaryList.textContent = '';
    var item = document.createElement('li');
    item.textContent = text;
    el.summaryList.appendChild(item);
    el.summary.hidden = false;
  }

  // --- Réponses

  function onPreview(response) {
    if (!L.isCurrent(response.request_id, state.latestPreview)) { return; }
    var kept = L.messageToKeep(state.pendingMessage, state.editStale, el.summary.hidden ? null : generalMessageIfAny());
    state.pendingMessage = null;
    clearDiagnostics();
    if (!response.ok) {
      state.previewReady = false;
      state.confirmation = null;
      showFailure(response.diagnostics);
      if (L.recoveryFor(response.diagnostics) === 'reload') { state.editStale = true; }
      updateWrite();
      return;
    }
    el.previewBox.classList.remove('is-stale');
    state.previewReady = true;
    state.confirmation = response.result.confirmation || null;
    fillForm(response.result.config);
    draw(response.result);
    showWarnings(response.diagnostics);
    setStatus(state.notice || 'Aperçu prêt');
    if (kept) { showGeneralMessage(kept); }
    updateWrite();
  }

  function generalMessageIfAny() {
    var first = el.summaryList.firstChild;
    return first && !first.querySelector('button') ? first.textContent : null;
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
    var site = siteFields.filter(function (f) { return '/site' + f.dataset.sitePath === path; })[0];
    if (site) { return site; }
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

  // --- Terrain : le panneau affiche et transmet, Ruby relève, calcule et décide

  function fillSite(settings) {
    siteFields.forEach(function (field) { writeField(field, L.getPath(settings, field.dataset.sitePath)); });
    state.site.errors = {};
    showSiteErrors();
  }

  // Un aperçu d'assise ne vaut que pour ce qui a été relevé, et une seule fois.
  function forgetSitePreview() {
    state.site.preview = null;
    state.site.confirmation = null;
    state.site.confirmMode = null;
    el.siteSummary.textContent = '';
    el.siteWarnings.textContent = '';
  }

  function readSite() {
    var settings = {};
    state.site.errors = {};
    siteFields.forEach(function (field) {
      var value = readField(field);
      if (value === null) { state.site.errors[field.dataset.sitePath] = LOCAL_ERROR; return; }
      L.setPath(settings, field.dataset.sitePath, value);
    });
    showSiteErrors();
    return settings;
  }

  function showSiteErrors() {
    document.querySelectorAll('.site-local').forEach(function (n) { n.parentNode.removeChild(n); });
    siteFields.forEach(function (field) {
      var text = state.site.errors[field.dataset.sitePath];
      field.classList.toggle('is-invalid', Boolean(text));
      if (!text) { return; }
      var node = document.createElement('p');
      node.className = 'error site-local';
      node.textContent = text;
      field.closest('.field').appendChild(node);
    });
  }

  function showSite() {
    var site = state.site;
    var hasSite = Boolean(site.status && site.status.has_site);
    var valid = Object.keys(site.errors).length === 0;
    el.siteState.textContent = L.siteStateText({ stale: state.editStale, hasSite: hasSite, moved: Boolean(site.status && site.status.moved), terrain: Boolean(site.terrainToken) });
    el.siteRatio.hidden = el.earthwork.value !== 'embankment';
    el.siteRetain.disabled = state.busy;
    el.siteSurvey.disabled = !L.canSurvey({ target: state.targetToken, stale: state.editStale, busy: state.busy, valid: valid, terrain: Boolean(site.terrainToken), hasSite: hasSite });
    el.siteAdapt.disabled = !site.preview || state.editStale || state.busy || state.cooling;
    el.siteRemove.disabled = !hasSite || !state.targetToken || state.editStale || state.busy || state.cooling;
  }

  function onSiteInput() {
    forgetSitePreview();
    closeConfirm();
    readSite();
    showSite();
  }

  function sitePayload() {
    var payload = { site: readSite(), target_token: state.targetToken };
    if (state.site.terrainToken) { payload.terrain_token = state.site.terrainToken; }
    return payload;
  }

  function onSiteSurveyClick() {
    var payload = sitePayload();
    showSite();
    if (el.siteSurvey.disabled) { return; }
    forgetSitePreview();
    setStatus('Relevé en cours');
    send('site_preview', payload);
  }

  function onSiteAdaptClick() {
    var preview = state.site.preview;
    if (el.siteAdapt.disabled || !preview) { return; }
    state.site.confirmation = preview.confirmation;
    state.site.confirmMode = 'adapt';
    openSiteConfirm(preview.confirmation.message, preview.lines);
  }

  function onSiteRemoveClick() {
    if (el.siteRemove.disabled) { return; }
    send('site_remove_preview', { target_token: state.targetToken });
  }

  function openSiteConfirm(message, lines) {
    el.confirmMessage.textContent = message;
    el.confirmChanges.textContent = '';
    lines.forEach(function (line) {
      var item = document.createElement('li');
      item.textContent = line;
      el.confirmChanges.appendChild(item);
    });
    el.confirmChanges.hidden = lines.length === 0;
    el.confirmChangesTitle.textContent = lines.length === 0 ? '' : 'Valeurs relevées';
    el.confirm.hidden = false;
    el.write.disabled = true;
    el.confirmYes.focus();
  }

  function onSiteConfirmYes() {
    var site = state.site;
    var confirmation = site.confirmation;
    if (!confirmation || state.busy) { return; }
    var mode = site.confirmMode;
    site.confirmation = null;
    site.confirmMode = null;
    startWriting();
    if (mode === 'remove') {
      send('remove_site', { target_token: state.targetToken, confirmation_token: confirmation.token });
      return;
    }
    var payload = sitePayload();
    payload.confirmation_token = confirmation.token;
    send('adapt_site', payload);
  }

  function onRetained(response) {
    if (!response.ok) { return showSiteFailure(response); }
    state.site.terrainToken = response.result.terrain_token;
    forgetSitePreview();
    clearDiagnostics();
    setStatus('Terrain retenu');
    if (state.editStale) { showGeneralMessage('Terrain retenu. Sélectionnez de nouveau le bâtiment, puis rechargez la sélection.'); }
    showSite();
  }

  function onSiteStatus(response) {
    if (!response.ok) {
      state.site.status = null;
      showSite();
      return;
    }
    state.site.status = response.result;
    if (response.result.settings) { fillSite(response.result.settings); }
    showSite();
  }

  function onSitePreview(response) {
    if (!response.ok) { return showSiteFailure(response); }
    state.site.preview = response.result;
    clearDiagnostics();
    el.siteSummary.textContent = '';
    response.result.lines.forEach(function (line) {
      var item = document.createElement('li');
      item.textContent = line;
      el.siteSummary.appendChild(item);
    });
    el.siteWarnings.textContent = '';
    L.uniqueDiagnostics(response.diagnostics).forEach(function (d) {
      var item = document.createElement('li');
      item.textContent = L.messageText(d);
      el.siteWarnings.appendChild(item);
    });
    setStatus('Relevé prêt');
    showSite();
  }

  function onSiteRemovePreview(response) {
    if (!response.ok) { return showSiteFailure(response); }
    state.site.confirmation = response.result.confirmation;
    state.site.confirmMode = 'remove';
    openSiteConfirm(response.result.confirmation.message, []);
  }

  function onSiteWritten(response, successText) {
    forgetSitePreview();
    onWritten(response, successText);
    showSite();
  }

  // L'aperçu du bâtiment reste valable : seule l'assise est refusée.
  function showSiteFailure(response) {
    forgetSitePreview();
    showFailure(response.diagnostics);
    if (L.recoveryFor(response.diagnostics) === 'reload') { state.editStale = true; }
    if (!state.editStale) { el.previewBox.classList.remove('is-stale'); }
    updateWrite();
    showSite();
    var details = el.terrain;
    details.open = true;
  }

  // --- Remplissage : les valeurs saisies ne sont pas écrasées

  function fillForm(config) {
    state.lastConfig = config;
    var active = document.activeElement;
    fields.forEach(function (field) {
      var path = field.dataset.path;
      if (field === active || state.localErrors[path] !== undefined) { return; }
      if (Object.prototype.hasOwnProperty.call(state.overrides, path) && !L.isToggle(field.dataset.kind)) { return; }
      writeField(field, L.getPath(config, path));
    });
    showShopHeight();
    el.roof.value = config.roof.type;
    showRoofFields(config.roof.type);
  }

  // AG-067 : la hauteur du commerce ne s'affiche qu'avec un rez-de-chaussée commerçant.
  function showShopHeight() {
    document.getElementById('f-shop-height-field').hidden = !document.getElementById('f-shop').checked;
    document.getElementById('f-shopfront-field').hidden = !document.getElementById('f-shop').checked;
    document.getElementById('f-awning-material-field').hidden = !document.getElementById('f-shop').checked || document.getElementById('f-shopfront').value !== 'awning';
    document.getElementById('f-shutters-material-field').hidden = !document.getElementById('f-shutters').checked;
    document.getElementById('f-cladding-material-field').hidden = !document.getElementById('f-cladding').checked;
    document.getElementById('f-timber-material-field').hidden = !document.getElementById('f-timber').checked;
  }

  function writeField(field, value) {
    switch (field.dataset.kind) {
      case 'number': field.value = L.formatNumber(value); break;
      case 'list': field.value = L.formatList(value); break;
      case 'check': field.checked = Boolean(value); break;
      case 'ground': field.checked = value === 'shop'; break;
      case 'ridge': field.value = value || 'parallel'; break;
      case 'arch': field.value = value || 'flat'; break;
      case 'ribbon': field.value = value || 'bays'; break;
      case 'shopfront': field.value = value || 'none'; break;
      case 'tint': field.value = String(value || 0); break;
      case 'entrance': field.value = value || 'none'; break;
      case 'rail': field.value = value || 'none'; break;
      case 'balconies': field.value = value || 'noble'; break;
      case 'bow': field.value = value || 'none'; break;
      case 'bell': field.value = value || 'none'; break;
      case 'wing': writeWing(field, value); break;
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
    field.addEventListener(L.isToggle(field.dataset.kind) || field.tagName === 'SELECT' ? 'change' : 'input', onFieldInput);
  });
  ['f-wing-width', 'f-wing-depth'].forEach(function (id) {
    document.getElementById(id).addEventListener('input', function () { onFieldInput({ target: document.getElementById('f-wing') }); });
  });
  el.profile.addEventListener('change', onProfileChange);
  el.roof.addEventListener('change', onRoofChange);
  siteFields.forEach(function (field) {
    field.addEventListener(field.tagName === 'SELECT' ? 'change' : 'input', onSiteInput);
  });
  el.siteRetain.addEventListener('click', function () { send('retain_terrain'); });
  el.siteSurvey.addEventListener('click', onSiteSurveyClick);
  el.siteAdapt.addEventListener('click', onSiteAdaptClick);
  el.siteRemove.addEventListener('click', onSiteRemoveClick);
  el.reload.addEventListener('click', function () { startMode('edit'); });
  el.newBuilding.addEventListener('click', function () { startMode('new'); });
  el.write.addEventListener('click', onWriteClick);
  el.confirmYes.addEventListener('click', onConfirmYes);
  el.confirmNo.addEventListener('click', onConfirmNo);
  el.reset.addEventListener('click', function () {
    state.overrides = {};
    state.localErrors = {};
    state.notice = null;
    closeConfirm();
    if (state.mode === 'edit' && state.baseProfile) {
      state.profile = null;
      var saved = findProfile(state.baseProfile.id);
      if (saved) {
        el.profile.value = saved.id;
        el.signature.textContent = saved.signature;
      }
    }
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
