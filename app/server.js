'use strict';

require('dotenv').config();

const express  = require('express');
const helmet   = require('helmet');
const morgan   = require('morgan');
const cors     = require('cors');
const path     = require('path');

const db       = require('./src/db');
const users    = require('./src/routes/users');
const health   = require('./src/routes/health');

const app  = express();
const PORT = process.env.PORT || 3000;
const HOST = process.env.HOST || '0.0.0.0';

// ── Middlewares de sécurité ──────────────────────────────────────────────────
app.use(helmet());
app.use(cors({
  origin: process.env.CORS_ORIGIN || '*',
  methods: ['GET', 'POST', 'PUT', 'DELETE'],
}));
app.use(express.json({ limit: '1mb' }));
app.use(morgan('combined'));
app.use(express.static(path.join(__dirname, 'public')));

// ── Routes ───────────────────────────────────────────────────────────────────
app.use('/health', health);
app.use('/api/users', users);

app.get('/api/profile', (_req, res) => {
  res.json({
    status: 'OK',
    data: {
      nom: process.env.PROFILE_NAME || 'ADONIS-IX',
      identifiant: process.env.PROFILE_USERNAME || 'ad-gomis',
      email: process.env.PROFILE_EMAIL || 'non-defini@example.com',
      role: process.env.PROFILE_ROLE || 'Etudiant',
      projet: process.env.PROFILE_PROJECT || 'TP Architecture 3-tiers',
      date: process.env.PROFILE_DATE || '31 mars 2026',
    },
  });
});

// Meta API
app.get('/api', (req, res) => {
  res.json({
    status:      'OK',
    application: 'TP Architecture 3-tiers',
    version:     '1.0.0',
    serveur:     'VM2 — DMZ (192.168.100.10)',
    endpoints: {
      health:    'GET /health',
      profile:   'GET /api/profile',
      healthDB:  'GET /health/db',
      users:     'GET /api/users',
      userById:  'GET /api/users/:id',
      create:    'POST /api/users',
      update:    'PUT /api/users/:id',
      delete:    'DELETE /api/users/:id',
    },
  });
});

// Gestion des routes inconnues
app.use((req, res) => {
  res.status(404).json({ status: 'ERROR', message: `Route ${req.method} ${req.path} introuvable` });
});

// Gestionnaire d'erreurs global
app.use((err, req, res, _next) => {
  console.error('[ERROR]', err.message);
  res.status(500).json({ status: 'ERROR', message: 'Erreur interne du serveur' });
});

// ── Démarrage ────────────────────────────────────────────────────────────────
async function start() {
  try {
    app.listen(PORT, HOST, () => {
      console.log(`[SERVER] Démarré sur http://${HOST}:${PORT}`);
      console.log('[SERVER] Demarrage sans test DB initial');
    });
  } catch (err) {
    console.error('[FATAL] Impossible de démarrer :', err.message);
    process.exit(1);
  }
}

// Arrêt propre
process.on('SIGTERM', async () => {
  console.log('[SERVER] Arrêt (SIGTERM)...');
  await db.close();
  process.exit(0);
});

start();
