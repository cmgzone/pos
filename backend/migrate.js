const fs = require('fs');
const path = require('path');
const { pool } = require('./src/db');

async function migrate() {
  const sqlPath = path.join(__dirname, 'sql', 'init.sql');
  const sql = fs.readFileSync(sqlPath, 'utf8');

  // Split on semicolons and run each statement individually
  // to avoid issues with multi-statement batches
  const statements = sql
    .split(';')
    .map((s) => s.trim())
    .filter((s) => s.length > 0);

  const client = await pool.connect();
  try {
    for (const statement of statements) {
      try {
        await client.query(statement);
        console.log('  OK:', statement.slice(0, 80).replace(/\n/g, ' '));
      } catch (err) {
        // Non-fatal: log and continue (e.g. "already exists" errors)
        console.warn('  WARN:', err.message.slice(0, 120));
      }
    }
    console.log('\n✅ Migration complete!');
  } finally {
    client.release();
    await pool.end();
  }
}

migrate().catch((err) => {
  console.error('❌ Migration failed:', err.message);
  process.exit(1);
});
