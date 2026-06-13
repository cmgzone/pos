const { pool, query } = require('./db');

async function main() {
  const result = await query(`
    SELECT
      current_database() AS database_name,
      current_user AS database_user,
      NOW() AS server_time
  `);

  const row = result.rows[0];
  console.log(
    `Connected to PostgreSQL database "${row.database_name}" as "${row.database_user}" at ${new Date(
      row.server_time,
    ).toISOString()}.`,
  );

  await pool.end();
}

main().catch(async (error) => {
  console.error('Failed to connect to PostgreSQL database.');
  console.error(error.message);
  await pool.end().catch(() => {});
  process.exitCode = 1;
});
