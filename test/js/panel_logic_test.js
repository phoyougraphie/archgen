// Tests de la logique pure du panneau. Sous Node : node test/js/panel_logic_test.js
// Dans un navigateur où ArchgenLogic est chargé : le script retourne le même bilan.
(function (root) {
  'use strict';

  var L = typeof require === 'function' ? require('../../archgen/ui/panel_logic.js') : root.ArchgenLogic;
  var failures = [];
  var count = 0;

  function same(actual, expected, label) {
    count += 1;
    if (JSON.stringify(actual) !== JSON.stringify(expected)) {
      failures.push(label + ' : attendu ' + JSON.stringify(expected) + ', reçu ' + JSON.stringify(actual));
    }
  }

  // Saisies décimales
  same(L.parseDecimal('12'), 12, 'entier');
  same(L.parseDecimal('1,2'), 1.2, 'virgule');
  same(L.parseDecimal('1.2'), 1.2, 'point');
  same(L.parseDecimal(' 3,5 '), 3.5, 'espaces');
  same(L.parseDecimal(''), null, 'vide');
  same(L.parseDecimal('1,2,3'), null, 'ambigu');
  same(L.parseDecimal('1 000'), null, 'séparateur de milliers');
  same(L.parseDecimal('abc'), null, 'lettres');
  same(L.parseDecimal('1e3'), null, 'exposant');
  same(L.parseInteger('4'), 4, 'entier simple');
  same(L.parseInteger('4,5'), null, 'entier décimal refusé');
  same(L.parseInteger('-1'), null, 'entier négatif refusé');
  same(L.parseInteger('12345678901'), null, 'entier trop long refusé');
  same(L.parseList(''), [], 'liste vide');
  same(L.parseList('3,2 ; 3 ; 2,8'), [3.2, 3, 2.8], 'liste');
  same(L.parseList('3,2 ; x'), null, 'liste invalide');

  // Affichage
  same(L.formatNumber(1.2), '1,2', 'format décimal');
  same(L.formatNumber(12), '12', 'format entier');
  same(L.formatNumber(0.1 + 0.2), '0,3', 'bruit flottant masqué');
  same(L.formatList([3.2, 3]), '3,2 ; 3', 'format de liste');

  // Brouillon
  same(L.buildDraft({}, null), { schema_version: 1 }, 'brouillon minimal');
  same(L.buildDraft({ '/footprint/width_m': 14, '/name': 'A' }, { id: 'haussmann', revision: 1, label: 'H' }),
    { schema_version: 1, profile: { id: 'haussmann', revision: 1 }, footprint: { width_m: 14 }, name: 'A' }, 'brouillon imbriqué');
  same(L.getPath({ a: { b: 2 } }, '/a/b'), 2, 'lecture de chemin');
  same(L.getPath({ a: null }, '/a/b'), undefined, 'chemin absent');

  // Transitions
  same(L.clearStyleOverrides({ '/name': 'A', '/footprint/width_m': 9, '/facade/sill_m': 1, '/roof/type': 'flat', '/materials/wall': 'zinc', '/features/cornice': true, '/structure/wall_m': 0.3 }),
    { '/name': 'A', '/footprint/width_m': 9 }, 'un nouveau style oublie ses blocs');
  same(L.withRoofType({ '/roof/pitch_deg': 40, '/roof/overhang_m': 1, '/name': 'A' }, 'flat'),
    { '/name': 'A', '/roof/type': 'flat' }, 'un nouveau toit n’envoie que son type');
  same(L.activeRoofFields('flat'), ['overhang_m'], 'plat');
  same(L.activeRoofFields('mansard').length, 4, 'mansarde');
  same(L.inactiveRoofFields('gable'), ['lower_pitch_deg', 'inset_m'], 'inactifs deux pans');

  // Réponses périmées
  same(L.isCurrent('r3', 'r3'), true, 'dernière réponse');
  same(L.isCurrent('r2', 'r3'), false, 'réponse ancienne');
  same(L.isCurrent(null, 'r3'), false, 'réponse sans identifiant');
  same(L.isCurrent(3, '3'), false, 'identifiant non textuel');

  // Diagnostics
  var groups = L.groupDiagnostics([{ path: '/name' }, { path: '/target' }], ['/name']);
  same(groups.byField['/name'].length, 1, 'par champ');
  same(groups.general.length, 1, 'général');
  same(L.groupDiagnostics(null, []).general, [], 'sans diagnostic');

  // Une cause, un message
  var repeated = [
    { severity: 'error', path: '/a', message: 'M', code: 'E' }, { severity: 'error', path: '/a', message: 'M', code: 'E' },
    { severity: 'error', path: '/a', message: 'N', code: 'E' }, { severity: 'warning', path: '/a', message: 'M', code: 'W' }
  ];
  var unique = L.uniqueDiagnostics(repeated);
  same(unique.length, 3, 'dédoublonnage');
  same(unique[0].count, 2, 'nombre de baies');
  same(L.messageText(unique[0]), 'M (2 baies concernées)', 'message au pluriel');
  same(L.messageText(unique[1]), 'N', 'message simple');
  same(L.uniqueDiagnostics(null), [], 'aucun diagnostic');

  // Échelle commune
  same(L.commonScale([{ width: 12, height: 20 }, { width: 12, height: 9 }], 240, 200), 10, 'une seule échelle');
  same(L.commonScale([{ width: 0, height: 0 }], 100, 100), 1, 'étendue nulle');
  same(L.extentOf([[[0, 0], [12, 9]], [[-1, 2]]]), { minX: -1, maxX: 12, minY: 0, maxY: 9, width: 13, height: 9 }, 'étendue');
  same(L.extentOf([]).width, 0, 'étendue vide');

  // Résumé
  same(L.summaryText({ window_count: 31, door_count: 1, roof_top_z_m: 19.608764 }, { width_m: 12, depth_m: 9 }),
    '31 fenêtres, 1 porte ; 12 × 9 m ; sommet 19,61 m', 'résumé');

  var report = { count: count, failures: failures };
  if (typeof module === 'object' && module.exports) {
    console.log(count + ' contrôles, ' + failures.length + ' échec(s)');
    failures.forEach(function (f) { console.log(f); });
    process.exit(failures.length === 0 ? 0 : 1);
  }
  root.ArchgenLogicReport = report;
}(typeof self !== 'undefined' ? self : this));
