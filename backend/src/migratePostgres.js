const { spawn } = require('node:child_process');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');

const CONFIRMATION = 'copy-neon-to-coolify-postgres';

async function main() {
  const sourceUrl = requiredEnv('SOURCE_DATABASE_URL');
  const targetUrl = requiredEnv('TARGET_DATABASE_URL');
  if (process.env.MIGRATION_CONFIRM !== CONFIRMATION) {
    throw new Error(
      `Set MIGRATION_CONFIRM=${CONFIRMATION} before running the migration.`,
    );
  }
  if (sourceUrl === targetUrl) {
    throw new Error('Source and target database URLs must be different.');
  }

  const dumpPath = path.join(
    os.tmpdir(),
    `piki-pos-postgres-${Date.now()}.dump`,
  );
  try {
    const sourceEnv = postgresConnectionEnv(sourceUrl);
    console.log('Creating a PostgreSQL backup from the source database...');
    await run('pg_dump', [
      '--dbname',
      sourceEnv.PGDATABASE,
      '--format=custom',
      '--no-owner',
      '--no-acl',
      '--file',
      dumpPath,
    ], sourceEnv);

    const targetEnv = postgresConnectionEnv(targetUrl);
    console.log('Restoring the backup into the Coolify PostgreSQL database...');
    await run('pg_restore', [
      '--dbname',
      targetEnv.PGDATABASE,
      '--clean',
      '--if-exists',
      '--no-owner',
      '--no-acl',
      '--exit-on-error',
      dumpPath,
    ], targetEnv);
    console.log('PostgreSQL migration completed successfully.');
  } finally {
    await fs.rm(dumpPath, { force: true });
  }
}

function requiredEnv(name) {
  const value = process.env[name]?.trim();
  if (!value) {
    throw new Error(`${name} is required.`);
  }
  return value;
}

function postgresConnectionEnv(connectionUrl) {
  const url = new URL(connectionUrl);
  if (!['postgres:', 'postgresql:'].includes(url.protocol)) {
    throw new Error('Database URLs must use the postgres:// protocol.');
  }

  const database = decodeURIComponent(url.pathname.replace(/^\/+/, ''));
  if (!url.hostname || !database) {
    throw new Error('Database URLs must include a hostname and database name.');
  }

  const env = {
    PGHOST: url.hostname,
    PGPORT: url.port || '5432',
    PGUSER: decodeURIComponent(url.username),
    PGPASSWORD: decodeURIComponent(url.password),
    PGDATABASE: database,
  };
  const queryEnvironmentVariables = {
    sslmode: 'PGSSLMODE',
    channel_binding: 'PGCHANNELBINDING',
    connect_timeout: 'PGCONNECT_TIMEOUT',
    application_name: 'PGAPPNAME',
    sslrootcert: 'PGSSLROOTCERT',
  };
  for (const [queryName, environmentName] of Object.entries(
    queryEnvironmentVariables,
  )) {
    const value = url.searchParams.get(queryName);
    if (value) {
      env[environmentName] = value;
    }
  }
  return env;
}

function run(command, args, extraEnv = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      stdio: 'inherit',
      env: { ...process.env, ...extraEnv },
    });
    child.on('error', reject);
    child.on('exit', (code) => {
      if (code === 0) {
        resolve();
      } else {
        reject(new Error(`${command} exited with code ${code}.`));
      }
    });
  });
}

if (require.main === module) {
  main().catch((error) => {
    console.error('PostgreSQL migration failed:', error.message);
    process.exitCode = 1;
  });
}

module.exports = { postgresConnectionEnv };
