const test = require('node:test');
const assert = require('node:assert/strict');

const { splitSqlStatements } = require('../src/sqlStatements');

test('splitSqlStatements keeps semicolons inside string literals', () => {
  const sql = `
    CREATE TABLE notes (
      id text PRIMARY KEY,
      body text DEFAULT 'hello;world'
    );
    INSERT INTO notes (id, body) VALUES ('1', 'done;still one value');
  `;

  assert.deepEqual(splitSqlStatements(sql), [
    `CREATE TABLE notes (
      id text PRIMARY KEY,
      body text DEFAULT 'hello;world'
    )`,
    `INSERT INTO notes (id, body) VALUES ('1', 'done;still one value')`,
  ]);
});

test('splitSqlStatements ignores semicolons inside comments and dollar quotes', () => {
  const sql = `
    -- create helper; still same statement
    SELECT $$value;inside$$ AS payload;
    /* block comment; same rule */
    SELECT 2;
  `;

  assert.deepEqual(splitSqlStatements(sql), [
    `-- create helper; still same statement
    SELECT $$value;inside$$ AS payload`,
    `/* block comment; same rule */
    SELECT 2`,
  ]);
});
