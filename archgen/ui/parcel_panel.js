// Panneau de parcelle (AG-069). Aucune géométrie ici : le noyau calcule, ce panneau envoie
// seulement les champs saisis. Un champ vide reprend la valeur de la rue.
(function () {
  'use strict';

  var DEBOUNCE_MS = 300;
  var state = { counter: 0, pending: {}, timer: null, digest: null, busy: false, street: null };
  var fields = Array.prototype.slice.call(document.querySelectorAll('[data-field]'));
  function byId(id) { return document.getElementById(id); }
  var el = { status: byId('status'), name: byId('parcel-name'), result: byId('result'), problems: byId('problems'),
    apply: byId('p-apply'), allReset: byId('p-all-reset'), width: byId('p-width'), widthHint: byId('p-width-hint') };

  function send(action, payload) {
    state.counter += 1;
    var id = 'p' + state.counter;
    state.pending[id] = action;
    window.sketchup.archgen_parcel(JSON.stringify({ v: 1, request_id: id, action: action, payload: payload || {} }));
  }

  function decimal(value) {
    return typeof value === 'number' ? String(Math.round(value * 1000000) / 1000000).replace('.', ',') : '';
  }

  var WORDS = { none: 'rien', awning: 'store banne', pergola: 'pergola', flat: 'plat', gable: 'deux pans', mansard: 'mansarde', dwelling: 'logement', shop: 'commerce', 'true': 'oui', 'false': 'non' };

  // Valeur de la rue, en grisé : placeholder d'un champ, libellé de l'option vide d'une liste.
  function showStreet(street) {
    fields.forEach(function (field) {
      var key = field.getAttribute('data-field');
      var value = street[key];
      if (field.tagName === 'SELECT') {
        field.options[0].textContent = 'Rue : ' + (WORDS[String(value)] || String(value));
      } else {
        field.placeholder = 'Rue : ' + decimal(value);
      }
    });
    el.width.disabled = Boolean(street.corner);
    el.widthHint.textContent = street.corner ? 'Bâtiment d’angle : sa largeur suit la rue.' : 'La voisine du même côté de rue prend ou cède la différence.';
  }

  function fill(own) {
    fields.forEach(function (field) {
      var value = own[field.getAttribute('data-field')];
      field.value = value === undefined || value === null ? '' : (typeof value === 'number' ? decimal(value) : String(value));
    });
  }

  function read(field) {
    var text = field.value.trim();
    if (text === '') { return null; }
    switch (field.getAttribute('data-kind')) {
      case 'int': return /^\d+$/.test(text) ? Number(text) : NaN;
      case 'number': return /^\d+([.,]\d+)?$/.test(text) ? Number(text.replace(',', '.')) : NaN;
      case 'bool': return text === 'true';
      default: return text;
    }
  }

  // Seuls les champs saisis partent ; un nombre illisible n'est jamais envoyé.
  function own() {
    var out = {};
    var bad = false;
    fields.forEach(function (field) {
      var value = read(field);
      if (typeof value === 'number' && isNaN(value)) { bad = true; }
      if (value !== null) { out[field.getAttribute('data-field')] = value; }
    });
    return bad ? null : out;
  }

  function showProblems(list) {
    el.problems.textContent = '';
    (list || []).forEach(function (problem) {
      var item = document.createElement('li');
      item.textContent = problem.message;
      el.problems.appendChild(item);
    });
  }

  function requestPreview() {
    clearTimeout(state.timer);
    state.digest = null;
    el.apply.disabled = true;
    state.timer = setTimeout(function () {
      var values = own();
      if (!values) { el.result.textContent = 'Saisissez un nombre valide.'; return; }
      el.result.textContent = 'Calcul…';
      send('preview', { own: values });
    }, DEBOUNCE_MS);
  }

  // Styles groupés par famille, après l'option « celui de la rue ».
  function fillStyles(styles) {
    var select = byId('p-style');
    while (select.options.length > 1) { select.remove(1); }
    Array.prototype.slice.call(select.querySelectorAll('optgroup')).forEach(function (g) { select.removeChild(g); });
    var groups = {};
    styles.forEach(function (style) {
      if (!groups[style.family]) {
        groups[style.family] = document.createElement('optgroup');
        groups[style.family].label = style.family;
        select.appendChild(groups[style.family]);
      }
      var option = document.createElement('option');
      option.value = style.id;
      option.textContent = style.label;
      groups[style.family].appendChild(option);
    });
  }

  function onInit(response) {
    if (!response.ok) {
      el.status.textContent = 'Bâtiment illisible';
      showProblems(response.diagnostics);
      return;
    }
    var result = response.result;
    state.street = result.street;
    fillStyles(result.styles || []);
    el.name.textContent = 'Bâtiment ' + result.parcel_id;
    el.status.textContent = result.custom_count + ' bâtiment(s) personnalisé(s) dans cette rue';
    showStreet(result.street);
    fill(result.own);
    requestPreview();
  }

  function onPreview(response) {
    var result = response.result || {};
    if (!response.ok || result.refused) {
      el.result.textContent = 'Réglage refusé :';
      showProblems(result.problems || response.diagnostics);
      return;
    }
    showProblems(response.diagnostics);
    state.digest = result.ensemble_digest;
    el.result.textContent = result.changed ? 'Prêt : la rue sera régénérée, Annuler la rétablit en une fois.' : 'Aucun changement.';
    el.apply.disabled = state.busy || !result.changed;
  }

  function onApplied(response) {
    state.busy = false;
    if (!response.ok) {
      el.result.textContent = 'Écriture refusée :';
      showProblems(response.diagnostics);
      requestPreview();
      return;
    }
    fill(response.result.own);
    el.status.textContent = response.result.custom_count + ' bâtiment(s) personnalisé(s) dans cette rue';
    el.result.textContent = 'Bâtiment mis à jour.';
    showProblems(response.diagnostics);
    state.digest = null;
    el.apply.disabled = true;
  }

  window.archgenParcelReceive = function (json) {
    var response = JSON.parse(json);
    var action = state.pending[response.request_id];
    delete state.pending[response.request_id];
    if (action === 'init') { onInit(response); return; }
    if (action === 'preview') { onPreview(response); return; }
    if (action === 'apply') { onApplied(response); }
  };

  window.archgenParcelRestart = function () { send('init'); };

  fields.forEach(function (field) {
    field.addEventListener(field.tagName === 'SELECT' ? 'change' : 'input', requestPreview);
  });
  Array.prototype.slice.call(document.querySelectorAll('[data-reset]')).forEach(function (button) {
    button.addEventListener('click', function () {
      document.querySelector('[data-field="' + button.getAttribute('data-reset') + '"]').value = '';
      requestPreview();
    });
  });
  el.allReset.addEventListener('click', function () {
    fields.forEach(function (field) { field.value = ''; });
    requestPreview();
  });
  el.apply.addEventListener('click', function () {
    var values = own();
    if (!values || !state.digest || state.busy) { return; }
    state.busy = true;
    el.apply.disabled = true;
    el.result.textContent = 'Écriture en cours…';
    send('apply', { own: values, ensemble_digest: state.digest });
  });

  send('init');
}());
