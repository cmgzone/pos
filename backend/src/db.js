const { neonConfig, Pool } = require('@neondatabase/serverless');
const ws = require('ws');

const { config } = require('./config');

neonConfig.webSocketConstructor = ws;

const pool = new Pool({
  connectionString: config.neonDatabaseUrl,
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
    await client.query('ROLLBACK');
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
    await client.query('ROLLBACK');
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
};
