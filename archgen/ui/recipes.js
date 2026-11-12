// Recettes (AG-148) : réglages d'un panneau enregistrés sous un nom, sur ce poste. Ce bloc
// affiche et transmet ; Ruby garde les recettes et juge leur nom. Le texte passe par textContent.
(function () {
  'use strict';

  function node(tag, attrs, parent, text) {
    var e = document.createElement(tag);
    Object.keys(attrs || {}).forEach(function (k) { e.setAttribute(k, attrs[k]); });
    if (text !== undefined) { e.textContent = text; }
    if (parent) { parent.appendChild(e); }
    return e;
  }

  // opts : root (élément vide), prefix (ids uniques), send(action, payload),
  // current() -> données à enregistrer ou null si la saisie est invalide, apply(data, name).
  function mount(opts) {
    var state = { list: [], pendingDelete: null, shown: false };
    var root = opts.root;
    root.textContent = '';
    var box = node('details', { class: 'section recipes' }, root);
    node('summary', {}, box, 'Mes recettes');
    node('p', { class: 'hint' }, box, 'Vos réglages enregistrés sous un nom, sur ce poste, pour tous vos modèles.');

    var pickRow = node('div', { class: 'recipes-row' }, box);
    node('label', { for: opts.prefix + '-recipe' }, pickRow, 'Recette');
    var select = node('select', { id: opts.prefix + '-recipe' }, pickRow);
    var apply = node('button', { type: 'button' }, pickRow, 'Appliquer');
    var remove = node('button', { type: 'button' }, pickRow, 'Effacer');

    var confirmRow = node('div', { class: 'recipes-row recipes-confirm', role: 'alertdialog', 'aria-live': 'assertive' }, box);
    var confirmText = node('span', {}, confirmRow);
    var confirmYes = node('button', { type: 'button', class: 'danger' }, confirmRow, 'Oui, effacer');
    var confirmNo = node('button', { type: 'button' }, confirmRow, 'Non');
    confirmRow.hidden = true;

    var saveRow = node('div', { class: 'recipes-row' }, box);
    node('label', { for: opts.prefix + '-recipe-name' }, saveRow, 'Nom');
    var name = node('input', { id: opts.prefix + '-recipe-name', type: 'text', maxlength: '60', autocomplete: 'off', placeholder: 'ex. Rue commerçante de bourg' }, saveRow);
    var save = node('button', { type: 'button', class: 'primary' }, saveRow, 'Enregistrer');

    var status = node('p', { class: 'recipes-status', role: 'status', 'aria-live': 'polite' }, box);

    function find(n) {
      return state.list.filter(function (r) { return r.name === n; })[0];
    }

    function render() {
      var chosen = select.value;
      select.textContent = '';
      node('option', { value: '' }, select, state.list.length ? '— Choisir une recette —' : 'Aucune recette enregistrée');
      state.list.forEach(function (r) { node('option', { value: r.name }, select, r.name); });
      select.value = find(chosen) ? chosen : '';
      refresh();
    }

    function refresh() {
      var picked = Boolean(select.value);
      apply.disabled = !picked;
      remove.disabled = !picked;
      select.disabled = state.list.length === 0;
      var typed = name.value.trim().replace(/\s+/g, ' ');
      save.disabled = typed === '';
      save.textContent = find(typed) ? 'Remplacer' : 'Enregistrer';
    }

    function say(text, bad) {
      status.textContent = text;
      status.classList.toggle('is-bad', Boolean(bad));
    }

    function closeConfirm() {
      state.pendingDelete = null;
      confirmRow.hidden = true;
    }

    select.addEventListener('change', function () {
      closeConfirm();
      if (select.value) { name.value = select.value; }
      say('');
      refresh();
    });
    name.addEventListener('input', refresh);
    name.addEventListener('keydown', function (event) {
      if (event.key !== 'Enter') { return; }
      event.preventDefault();
      if (!save.disabled) { save.click(); }
    });

    apply.addEventListener('click', function () {
      var recipe = find(select.value);
      if (!recipe) { return; }
      closeConfirm();
      opts.apply(JSON.parse(JSON.stringify(recipe.data)), recipe.name);
      say('Recette « ' + recipe.name + ' » appliquée.');
    });

    save.addEventListener('click', function () {
      var data = opts.current();
      if (!data) { say('Corrigez d’abord la saisie : ces réglages ne peuvent pas être enregistrés.', true); return; }
      closeConfirm();
      say('Enregistrement…');
      opts.send('save_recipe', { name: name.value, data: data });
    });

    remove.addEventListener('click', function () {
      if (!select.value) { return; }
      state.pendingDelete = select.value;
      confirmText.textContent = 'Effacer la recette « ' + select.value + ' » ? Elle ne pourra pas être rétablie.';
      confirmRow.hidden = false;
      confirmNo.focus();
    });
    confirmNo.addEventListener('click', function () { closeConfirm(); remove.focus(); });
    confirmYes.addEventListener('click', function () {
      if (!state.pendingDelete) { return; }
      say('Effacement…');
      opts.send('delete_recipe', { name: state.pendingDelete });
      closeConfirm();
    });

    render();

    return {
      // Ouvert d'office seulement s'il y a des recettes ; ensuite, l'utilisateur décide.
      update: function (list) {
        state.list = list || [];
        if (!state.shown) { box.open = state.list.length > 0; state.shown = true; }
        render();
      },
      // Réponse de Ruby à save_recipe ou delete_recipe.
      receive: function (action, response) {
        if (!response.ok) {
          say(response.diagnostics.map(function (d) { return d.message; }).join(' '), true);
          return;
        }
        state.list = response.result.recipes;
        if (action === 'save_recipe') {
          var saved = name.value.trim().replace(/\s+/g, ' ');
          render();
          select.value = saved;
          refresh();
          say('Recette « ' + saved + ' » enregistrée.');
        } else {
          select.value = '';
          name.value = '';
          render();
          say('Recette effacée.');
        }
      }
    };
  }

  window.ArchgenRecipes = { mount: mount };
}());
