'use strict';

const { Router } = require('express');
const db = require('../db');

const router = Router();

// ── Helpers ──────────────────────────────────────────────────────────────────
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function validateUser(body) {
  const errors = [];
  if (!body.nom  || body.nom.trim().length < 2)  errors.push('nom requis (min 2 caractères)');
  if (!body.email || !EMAIL_RE.test(body.email)) errors.push('email invalide');
  return errors;
}

// ── GET /api/users — liste paginée ───────────────────────────────────────────
router.get('/', async (req, res) => {
  try {
    const limit  = Math.min(parseInt(req.query.limit  || '20', 10), 100);
    const offset = Math.max(parseInt(req.query.offset || '0',  10), 0);
    const pool   = db.getPool();

    const [[{ total }], rows] = await Promise.all([
      pool.query('SELECT COUNT(*) AS total FROM utilisateurs'),
      pool.query(
        'SELECT id, nom, email, statut, created_at FROM utilisateurs ORDER BY id LIMIT ? OFFSET ?',
        [limit, offset]
      ),
    ]);

    res.json({ status: 'OK', total, limit, offset, data: rows });
  } catch (err) {
    res.status(500).json({ status: 'ERROR', message: err.message });
  }
});

// ── GET /api/users/:id ───────────────────────────────────────────────────────
router.get('/:id', async (req, res) => {
  try {
    const pool  = db.getPool();
    const [rows] = await pool.query(
      'SELECT id, nom, email, statut, created_at, updated_at FROM utilisateurs WHERE id = ?',
      [req.params.id]
    );
    if (!rows.length) return res.status(404).json({ status: 'ERROR', message: 'Utilisateur introuvable' });
    res.json({ status: 'OK', data: rows[0] });
  } catch (err) {
    res.status(500).json({ status: 'ERROR', message: err.message });
  }
});

// ── POST /api/users — créer ──────────────────────────────────────────────────
router.post('/', async (req, res) => {
  const errors = validateUser(req.body);
  if (errors.length) return res.status(400).json({ status: 'ERROR', errors });

  try {
    const pool = db.getPool();
    const [result] = await pool.query(
      'INSERT INTO utilisateurs (nom, email) VALUES (?, ?)',
      [req.body.nom.trim(), req.body.email.toLowerCase().trim()]
    );
    res.status(201).json({ status: 'OK', message: 'Utilisateur créé', id: result.insertId });
  } catch (err) {
    if (err.code === 'ER_DUP_ENTRY') {
      return res.status(409).json({ status: 'ERROR', message: 'Email déjà utilisé' });
    }
    res.status(500).json({ status: 'ERROR', message: err.message });
  }
});

// ── PUT /api/users/:id — modifier ────────────────────────────────────────────
router.put('/:id', async (req, res) => {
  const errors = validateUser(req.body);
  if (errors.length) return res.status(400).json({ status: 'ERROR', errors });

  try {
    const pool = db.getPool();
    const [result] = await pool.query(
      'UPDATE utilisateurs SET nom = ?, email = ?, statut = ? WHERE id = ?',
      [
        req.body.nom.trim(),
        req.body.email.toLowerCase().trim(),
        req.body.statut || 'actif',
        req.params.id,
      ]
    );
    if (!result.affectedRows) return res.status(404).json({ status: 'ERROR', message: 'Utilisateur introuvable' });
    res.json({ status: 'OK', message: 'Utilisateur mis à jour' });
  } catch (err) {
    res.status(500).json({ status: 'ERROR', message: err.message });
  }
});

// ── DELETE /api/users/:id ────────────────────────────────────────────────────
router.delete('/:id', async (req, res) => {
  try {
    const pool = db.getPool();
    const [result] = await pool.query('DELETE FROM utilisateurs WHERE id = ?', [req.params.id]);
    if (!result.affectedRows) return res.status(404).json({ status: 'ERROR', message: 'Utilisateur introuvable' });
    res.json({ status: 'OK', message: 'Utilisateur supprimé' });
  } catch (err) {
    res.status(500).json({ status: 'ERROR', message: err.message });
  }
});

module.exports = router;
