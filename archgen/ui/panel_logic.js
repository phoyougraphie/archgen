// Logique pure du panneau, sans DOM ni pont : testée sous Node (test/js).
// Aucune règle de faisabilité ici : tout ce qui décide vient de Ruby.
(function (root, factory) {
  var api = factory();
  if (typeof module === 'object' && module.exports) { module.exports = api; }
  root.ArchgenLogic = api;
}(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  // Blocs que reprend un nouveau profil : leurs réglages locaux sont oubliés.
  var STYLE_BLOCKS = ['/facade/', '/roof/', '/structure/', '/materials/', '/features/'];
  var ROOF_FIELDS = {
    flat: ['overhang_m'],
    gable: ['overhang_m', 'pitch_deg'],
    hip: ['overhang_m', 'pitch_deg'],
    mansard: ['overhang_m', 'pitch_deg', 'lower_pitch_deg', 'inset_m']
  };
  var ALL_ROOF_FIELDS = ['overhang_m', 'pitch_deg', 'lower_pitch_deg', 'inset_m'];

  // Virgule ou point, une représentation décimale sans ambiguïté, sinon null.
  function parseDecimal(text) {
    var value = String(text).trim();
    if (!/^-?\d+([.,]\d+)?$/.test(value)) { return null; }
    var number = Number(value.replace(',', '.'));
    return isFinite(number) ? number : null;
  }

  function parseInteger(text) {
    var value = String(text).trim();
    return /^\d+$/.test(value) && value.length <= 10 ? Number(value) : null;
  }

  // Liste de hauteurs séparées par des points-virgules ; vide = liste vide.
  function parseList(text) {
    var value = String(text).trim();
    if (value === '') { return []; }
    var numbers = value.split(';').map(parseDecimal);
    return numbers.indexOf(null) >= 0 ? null : numbers;
  }

  function formatNumber(value) {
    if (typeof value !== 'number') { return ''; }
    return String(Math.round(value * 1000000) / 1000000).replace('.', ',');
  }

  function formatList(values) {
    return (values || []).map(formatNumber).join(' ; ');
  }

  function setPath(target, path, value) {
    var keys = path.split('/').slice(1);
    var node = target;
    keys.slice(0, -1).forEach(function (key) {
      if (!Object.prototype.hasOwnProperty.call(node, key)) { node[key] = {}; }
      node = node[key];
    });
    node[keys[keys.length - 1]] = value;
    return target;
  }

  function getPath(source, path) {
    return path.split('/').slice(1).reduce(function (node, key) {
      return node === null || node === undefined ? undefined : node[key];
    }, source);
  }

  // Le brouillon ne contient que ce que l'utilisateur a changé.
  function buildDraft(overrides, profile) {
    var draft = { schema_version: 1 };
    if (profile) { draft.profile = { id: profile.id, revision: profile.revision }; }
    Object.keys(overrides).sort().forEach(function (path) { setPath(draft, path, overrides[path]); });
    return draft;
  }

  // Sélectionner un autre profil oublie les blocs qu'il reprend.
  function clearStyleOverrides(overrides) {
    var kept = {};
    Object.keys(overrides).forEach(function (path) {
      var style = STYLE_BLOCKS.some(function (prefix) { return path.indexOf(prefix) === 0; });
      if (!style) { kept[path] = overrides[path]; }
    });
    return kept;
  }

  // Changer de type de toit repart des valeurs du type : on n'envoie plus que le type.
  function withRoofType(overrides, type) {
    var kept = {};
    Object.keys(overrides).forEach(function (path) {
      if (path.indexOf('/roof/') !== 0) { kept[path] = overrides[path]; }
    });
    kept['/roof/type'] = type;
    return kept;
  }

  function activeRoofFields(type) {
    return ROOF_FIELDS[type] || [];
  }

  function inactiveRoofFields(type) {
    return ALL_ROOF_FIELDS.filter(function (field) { return activeRoofFields(type).indexOf(field) < 0; });
  }

  // Seule la réponse à la dernière demande d'aperçu peut s'appliquer.
  function isCurrent(requestId, latestId) {
    return typeof requestId === 'string' && requestId === latestId;
  }

  // Le bouton d'écriture n'est actif que sur un aperçu frais et sans action en cours.
  function canWrite(s) {
    if (s.busy || s.cooling || s.editStale || !s.previewReady || s.localErrorCount > 0) { return false; }
    return s.mode === 'new' || Boolean(s.confirmation);
  }

  // Tout diagnostic de cible ou de confirmation dit quoi faire ensuite, sans perdre le brouillon.
  // Un message survit à l'aperçu qu'il a demandé, ou tant que la cible reste périmée ; pas au-delà.
  function messageToKeep(pending, editStale, current) {
    if (pending) { return pending; }
    return editStale ? current : null;
  }

  function recoveryFor(diagnostics) {
    var codes = (diagnostics || []).map(function (d) { return d.code; });
    if (codes.indexOf('E_TARGET_STALE') >= 0) { return 'reload'; }
    if (codes.indexOf('E_CONFIRMATION_STALE') >= 0) { return 'preview'; }
    return 'none';
  }

  function nextRequestId(counter) {
    return 'r' + counter;
  }

  // Une même cause touche souvent plusieurs baies : un message, avec le nombre concerné.
  function uniqueDiagnostics(diagnostics) {
    var seen = {};
    var unique = [];
    (diagnostics || []).forEach(function (diagnostic) {
      var key = diagnostic.severity + '|' + diagnostic.path + '|' + diagnostic.message;
      if (seen[key]) { seen[key].count += 1; return; }
      seen[key] = { code: diagnostic.code, severity: diagnostic.severity, path: diagnostic.path, message: diagnostic.message, field: diagnostic.field, count: 1 };
      unique.push(seen[key]);
    });
    return unique;
  }

  function messageText(diagnostic) {
    return diagnostic.count > 1 ? diagnostic.message + ' (' + diagnostic.count + ' baies concernées)' : diagnostic.message;
  }

  function groupDiagnostics(diagnostics, knownPaths) {
    var groups = { byField: {}, general: [] };
    (diagnostics || []).forEach(function (diagnostic) {
      if (knownPaths.indexOf(diagnostic.path) >= 0) {
        (groups.byField[diagnostic.path] = groups.byField[diagnostic.path] || []).push(diagnostic);
      } else {
        groups.general.push(diagnostic);
      }
    });
    return groups;
  }

  // Une seule échelle pour l'élévation et le plan : pixels par mètre.
  // Ce que dit la section Terrain, d'après ce que Ruby a répondu.
  function siteStateText(s) {
    if (s.stale) {
      return s.terrain ? 'Terrain retenu. Rechargez la sélection pour continuer.' : 'Rechargez la sélection pour voir l’état de l’assise.';
    }
    if (s.hasSite) {
      return s.moved ? 'Assise périmée : le bâtiment a été déplacé. Relevez de nouveau.' : 'Ce bâtiment est adapté au terrain.';
    }
    return s.terrain ? 'Terrain retenu. Ce bâtiment n’a pas encore d’assise.' : 'Aucun terrain retenu.';
  }

  function canSurvey(s) {
    return Boolean(s.target && !s.stale && !s.busy && s.valid && (s.terrain || s.hasSite));
  }


  function commonScale(extents, widthPx, heightPx) {
    var scale = Infinity;
    extents.forEach(function (extent) {
      if (extent.width > 0) { scale = Math.min(scale, widthPx / extent.width); }
      if (extent.height > 0) { scale = Math.min(scale, heightPx / extent.height); }
    });
    return isFinite(scale) ? scale : 1;
  }

  function extentOf(pointLists) {
    var xs = [];
    var ys = [];
    pointLists.forEach(function (points) {
      points.forEach(function (point) { xs.push(point[0]); ys.push(point[1]); });
    });
    if (xs.length === 0) { return { minX: 0, maxX: 0, minY: 0, maxY: 0, width: 0, height: 0 }; }
    var minX = Math.min.apply(null, xs);
    var maxX = Math.max.apply(null, xs);
    var minY = Math.min.apply(null, ys);
    var maxY = Math.max.apply(null, ys);
    return { minX: minX, maxX: maxX, minY: minY, maxY: maxY, width: maxX - minX, height: maxY - minY };
  }

  function summaryText(summary, metrics) {
    var windows = summary.window_count;
    var doors = summary.door_count;
    return windows + (windows > 1 ? ' fenêtres, ' : ' fenêtre, ') + doors + (doors > 1 ? ' portes' : ' porte') +
      ' ; ' + formatNumber(metrics.width_m) + ' × ' + formatNumber(metrics.depth_m) + ' m ; sommet ' +
      formatNumber(Math.round(summary.roof_top_z_m * 100) / 100) + ' m';
  }

  return {
    parseDecimal: parseDecimal, parseInteger: parseInteger, parseList: parseList,
    formatNumber: formatNumber, formatList: formatList, getPath: getPath,
    buildDraft: buildDraft, clearStyleOverrides: clearStyleOverrides, withRoofType: withRoofType,
    activeRoofFields: activeRoofFields, inactiveRoofFields: inactiveRoofFields,
    isCurrent: isCurrent, nextRequestId: nextRequestId, groupDiagnostics: groupDiagnostics,
    uniqueDiagnostics: uniqueDiagnostics, messageText: messageText,
    canWrite: canWrite, recoveryFor: recoveryFor, messageToKeep: messageToKeep,
    commonScale: commonScale, extentOf: extentOf, summaryText: summaryText,
    setPath: setPath, siteStateText: siteStateText, canSurvey: canSurvey
  };
}));
