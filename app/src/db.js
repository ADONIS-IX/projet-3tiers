'use strict';

const mysql = require('mysql2/promise');

let pool = null;

/**
 * Crée et retourne le pool de connexions MySQL (singleton).
 */
function getPool() {
  if (!pool) {
    pool = mysql.createPool({
      host:               process.env.DB_HOST     || '192.168.10.10',
      port:               parseInt(process.env.DB_PORT || '3306', 10),
      database:           process.env.DB_NAME     || 'appdb',
      user:               process.env.DB_USER     || 'webuser',
      password:           process.env.DB_PASS,
      waitForConnections: true,
      connectionLimit:    10,
      queueLimit:         0,
      connectTimeout:     10000,
      timezone:           '+00:00',
    });

    console.log(`[DB] Pool initialisé → ${process.env.DB_HOST}:${process.env.DB_PORT}/${process.env.DB_NAME}`);
  }
  return pool;
}

/**
 * Teste la connexion à la base de données.
 * Lance une exception si la BD est inaccessible.
 */
async function testConnection() {
  const conn = await getPool().getConnection();
  await conn.ping();
  conn.release();
}

/**
 * Ferme proprement le pool (utilisé lors de l'arrêt du serveur).
 */
async function close() {
  if (pool) {
    await pool.end();
    pool = null;
    console.log('[DB] Pool fermé');
  }
}

module.exports = { getPool, testConnection, close };
