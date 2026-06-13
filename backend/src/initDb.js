const path = require('path');

const { pool } = require('./db');
const { runSqlFile } = require('./sqlStatements');
const { ensureSubscriptionSchema } = require('./subscriptionPlans');
const { ensureCommunicationSchema } = require('./communication');
const { ensurePosPaymentSchema } = require('./posPayments');
const { ensureCatalogSubdomainSchema } = require('./catalogSubdomains');

async function main() {
  const sqlPath = path.resolve(__dirname, '..', 'sql', 'init.sql');
  const client = await pool.connect();

  try {
    await client.query('BEGIN');
    const statementCount = await runSqlFile(client, sqlPath);
    await ensureSubscriptionSchema(client);
    await ensureCommunicationSchema(client);
    await ensurePosPaymentSchema(client);
    await ensureCatalogSubdomainSchema(client);
    await client.query('COMMIT');

    console.log(
      `Initialized Neon schema from ${path.basename(sqlPath)} with ${statementCount} statements.`,
    );
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
    await pool.end();
  }
}

main().catch((error) => {
  console.error('Failed to initialize Neon database.');
  console.error(error.message);
  process.exitCode = 1;
});
