'use strict';

const refs = {
  toast: document.getElementById('toast'),
  profileBox: document.getElementById('profileBox'),
  healthBox: document.getElementById('healthBox'),
  apiBox: document.getElementById('apiBox'),
  refreshAllBtn: document.getElementById('refreshAllBtn'),
  loadProfileBtn: document.getElementById('loadProfileBtn'),
  checkHealthBtn: document.getElementById('checkHealthBtn'),
  loadApiBtn: document.getElementById('loadApiBtn'),
};

async function api(path, options) {
  const response = await fetch(path, {
    headers: { 'Content-Type': 'application/json' },
    ...options,
  });

  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    const detail = payload.message || 'Erreur API';
    throw new Error(detail);
  }

  return payload;
}

function showToast(message, isError = false) {
  refs.toast.textContent = message;
  refs.toast.style.background = isError ? '#8f3434' : '#1b2427';
  refs.toast.classList.add('show');
  window.clearTimeout(showToast.timer);
  showToast.timer = window.setTimeout(() => refs.toast.classList.remove('show'), 2200);
}

function setBusy(button, busy, busyText = '...') {
  if (!button) return;
  if (!button.dataset.label) button.dataset.label = button.textContent;
  button.disabled = busy;
  button.textContent = busy ? busyText : button.dataset.label;
}

function renderStatusGrid(target, entries) {
  target.innerHTML = entries
    .map(
      ([label, value]) =>
        `<div class="status-item"><strong>${escapeHtml(label)}</strong><span>${escapeHtml(String(value ?? '-'))}</span></div>`
    )
    .join('');
}

async function loadProfile() {
  setBusy(refs.loadProfileBtn, true, 'Chargement...');
  try {
    const payload = await api('/api/profile');
    const profile = payload.data || {};
    renderStatusGrid(refs.profileBox, [
      ['Nom', profile.nom],
      ['Identifiant', profile.identifiant],
      ['Email', profile.email],
      ['Role', profile.role],
      ['Projet', profile.projet],
      ['Date', profile.date],
    ]);
  } catch (error) {
    showToast(error.message, true);
  } finally {
    setBusy(refs.loadProfileBtn, false);
  }
}

async function loadHealth() {
  setBusy(refs.checkHealthBtn, true, 'Verification...');
  try {
    const health = await api('/health');
    renderStatusGrid(refs.healthBox, [
      ['Status', health.status],
      ['Serveur', health.serveur],
      ['IP', health.ip],
      ['Uptime', health.uptime],
      ['Horodatage', health.time],
    ]);
  } catch (error) {
    showToast(error.message, true);
  } finally {
    setBusy(refs.checkHealthBtn, false);
  }
}

async function loadApiMeta() {
  setBusy(refs.loadApiBtn, true, 'Chargement...');
  refs.apiBox.textContent = 'Chargement des meta-informations API...';
  try {
    const payload = await api('/api');
    refs.apiBox.textContent = JSON.stringify(payload, null, 2);
  } catch (error) {
    refs.apiBox.textContent = error.message;
    showToast(error.message, true);
  } finally {
    setBusy(refs.loadApiBtn, false);
  }
}

async function loadAll() {
  await Promise.all([loadProfile(), loadHealth(), loadApiMeta()]);
  showToast('Informations actualisees');
}

function escapeHtml(value) {
  return value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

refs.refreshAllBtn.addEventListener('click', loadAll);
refs.loadProfileBtn.addEventListener('click', loadProfile);
refs.checkHealthBtn.addEventListener('click', loadHealth);
refs.loadApiBtn.addEventListener('click', loadApiMeta);

void loadAll();
