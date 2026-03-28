'use strict';

const { Router } = require('express');
const db = require('../db');

const router = Router();

// GET /health — vérification générale du serveur
router.get('/', (_req, res) => {
  res.json({
    status:  'OK',
    serveur: 'vm2-web',
    ip:      '192.168.100.10',
    uptime:  Math.floor(process.uptime()) + 's',
    time:    new Date().toISOString(),
  });
});

// GET /health/db — vérification de la connexion MySQL (VM3)
router.get('/db', async (_req, res) => {
  try {
    const pool = db.getPool();
    const [rows] = await pool.query(
      'SELECT NOW() AS server_time, @@hostname AS db_host, @@version AS db_version'
    );
    res.json({
      status:   'OK',
      message:  'Connexion MySQL (VM3) opérationnelle',
      database: rows[0],
    });
  } catch (err) {
    res.status(503).json({
      status:  'ERROR',
      message: 'Impossible de joindre VM3 (BD)',
      detail:  err.message,
    });
  }
});

module.exports = router;
