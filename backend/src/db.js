const { Pool } = require('pg');

const { config } = require('./config');

const poolOptions = {
  connectionString: config.databaseUrl,
  max: config.databasePoolMax,
  idleTimeoutMillis: config.databaseIdleTimeoutMs,
  connectionTimeoutMillis: config.databaseConnectionTimeoutMs,
  keepAlive: true,
};

if (config.databaseSsl !== null) {
  poolOptions.ssl = config.databaseSsl
    ? { rejectUnauthorized: config.databaseSslRejectUnauthorized }
    : false;
}

const pool = new Pool(poolOptions);

pool.on('error', (err) => {
  console.error('Unexpected PostgreSQL pool error:', err);
});

async function query(text, params) {
  return pool.query(text, params);
}

async function withTransaction(callback) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await callback(client);
    await client.query('COMMIT');
    return result;
  } catch (error) {
    try {
      await client.query('ROLLBACK');
    } catch (rollbackError) {
      console.error('ROLLBACK failed after transaction error:', rollbackError);
    }
    throw error;
  } finally {
    client.release();
  }
}

async function withReadTransaction(callback) {
  const client = await pool.connect();
  try {
    await client.query(
      'START TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY',
    );
    const result = await callback(client);
    await client.query('COMMIT');
    return result;
  } catch (error) {
    try {
      await client.query('ROLLBACK');
    } catch (rollbackError) {
      console.error('ROLLBACK failed after read transaction error:', rollbackError);
    }
    throw error;
  } finally {
    client.release();
  }
}

module.exports = {
  pool,
  query,
  withTransaction,
  withReadTransaction,
  closePool: async () => {
    await pool.end();
  },
};
