const fs = require('fs');
const path = require('path');

const { pool } = require('./src/db');
const { splitSqlStatements } = require('./src/sqlStatements');

async function migrate() {
  const sqlPath = path.join(__dirname, 'sql', 'init.sql');
  const sql = fs.readFileSync(sqlPath, 'utf8');
  const statements = splitSqlStatements(sql);

  const client = await pool.connect();
  try {
    for (const statement of statements) {
      try {
        await client.query(statement);
        console.log('  OK:', statement.slice(0, 80).replace(/\n/g, ' '));
      } catch (error) {
        console.warn('  WARN:', error.message.slice(0, 120));
      }
    }

    console.log('\nMigration complete.');
  } finally {
    client.release();
    await pool.end();
  }
}

migrate().catch((error) => {
  console.error('Migration failed:', error.message);
  process.exit(1);
});
