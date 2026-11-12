// Panneau « Importer une carte » (AG-129). Aucun calcul ici : Ruby lit, télécharge et juge.
(function () {
  'use strict';

  var state = { counter: 0, pending: {}, source: null };
  function byId(id) { return document.getElementById(id); }
  var el = { status: byId('status'), lat: byId('m-lat'), lon: byId('m-lon'), size: byId('m-size'), map: byId('m-map'),
    terrain: byId('m-terrain'), ign: byId('m-ign'), roads: byId('m-roads'), buildings: byId('m-buildings'),
    terrainLayer: byId('m-terrain-layer'), style: byId('m-style'), preview: byId('m-preview'), importBtn: byId('m-import'),
    result: byId('m-result'), attribution: byId('m-attribution'), georef: byId('m-georef') };

  var LABELS = { networks: 'Réseaux de voies', roads: 'Voies', buildings: 'Bâtiments', terrain_faces: 'Faces de terrain' };

  function send(action, payload) {
    state.counter += 1;
    var id = 'm' + state.counter;
    state.pending[id] = action;
    window.sketchup.archgen_map(JSON.stringify({ v: 1, request_id: id, action: action, payload: payload || {} }));
  }

  function number(input) {
    var text = input.value.trim().replace(',', '.');
    return /^-?\d+(\.\d+)?$/.test(text) ? Number(text) : null;
  }

  function line(text) {
    var li = document.createElement('li');
    li.textContent = text;
    el.result.appendChild(li);
  }

  function showDiagnostics(response) {
    (response.diagnostics || []).forEach(function (d) { line(d.message); });
  }

  function layers() {
    var out = [];
    if (el.roads.checked) { out.push('roads'); }
    if (el.buildings.checked) { out.push('buildings'); }
    if (el.terrainLayer.checked) { out.push('terrain'); }
    return out;
  }

  // AG-145 : Ruby envoie une chaîne JSON, jamais un objet (même pont que le panneau du bâtiment).
  function parsed(message) { return typeof message === 'string' ? JSON.parse(message) : message; }

  window.archgenMapReceive = function (message) {
    var response = parsed(message);
    var action = state.pending[response.request_id];
    delete state.pending[response.request_id];
    if (action === 'init' && response.ok) {
      var r = response.result;
      el.style.textContent = '';
      r.styles.forEach(function (s) {
        var o = document.createElement('option');
        o.value = s.id; o.textContent = s.label;
        el.style.appendChild(o);
      });
      if (r.georef) {
        el.lat.value = String(r.georef[0]); el.lon.value = String(r.georef[1]);
        el.georef.textContent = 'Centre : la géolocalisation du modèle.';
      }
      el.status.textContent = 'Prêt.';
      return;
    }
    if (action === 'choose' && response.ok && response.result.path) {
      (response.result.kind === 'terrain' ? el.terrain : el.map).value = response.result.path;
      if (response.result.kind === 'map') { state.source = { kind: 'file' }; }
      el.importBtn.disabled = true;
      return;
    }
    el.result.textContent = '';
    if (action === 'download') {
      el.status.textContent = response.ok && response.result.started ? 'Téléchargement depuis ' + response.result.host + '…' : 'Téléchargement annulé.';
      showDiagnostics(response);
      return;
    }
    if (action === 'preview') {
      el.importBtn.disabled = !response.ok;
      if (response.ok) {
        var c = response.result.counts;
        Object.keys(LABELS).forEach(function (k) { line(LABELS[k] + ' : ' + c[k]); });
        Object.keys(response.result.skipped).forEach(function (k) { line('Écartés (' + k + ') : ' + response.result.skipped[k]); });
        el.attribution.textContent = response.result.attribution.join(' ; ');
        el.status.textContent = 'Aperçu prêt : rien n’est encore écrit.';
      } else {
        el.status.textContent = 'Aperçu refusé.';
      }
      showDiagnostics(response);
      return;
    }
    if (action === 'import') {
      el.importBtn.disabled = true;
      el.status.textContent = response.ok ? 'Carte importée : une seule entrée d’Annuler la retire.' : 'Import refusé : rien n’a été écrit.';
      showDiagnostics(response);
    }
  };

  window.archgenMapDownloaded = function (message) {
    var response = parsed(message);
    el.result.textContent = '';
    if (response.ok) {
      el.map.value = response.result.path;
      state.source = response.result.source;
      el.status.textContent = 'Extrait reçu et gardé : ' + response.result.path;
    } else {
      el.status.textContent = 'Téléchargement refusé.';
    }
    showDiagnostics(response);
  };

  byId('m-map-pick').addEventListener('click', function () { send('choose', { kind: 'map' }); });
  byId('m-terrain-pick').addEventListener('click', function () { send('choose', { kind: 'terrain' }); });
  byId('m-download').addEventListener('click', function () {
    send('download', { lat: number(el.lat), lon: number(el.lon), size_m: number(el.size) });
  });
  el.preview.addEventListener('click', function () {
    send('preview', { map_path: el.map.value, terrain_path: el.terrain.value, lat: number(el.lat), lon: number(el.lon),
      style: el.style.value, layers: layers(), ign: el.ign.checked, source: state.source || { kind: 'file' } });
  });
  el.importBtn.addEventListener('click', function () { send('import', {}); });
  send('init');
}());
