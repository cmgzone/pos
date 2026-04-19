const fs = require('fs');

function splitSqlStatements(sqlText) {
  const statements = [];
  let current = '';
  let index = 0;
  let inSingleQuote = false;
  let inDoubleQuote = false;
  let inLineComment = false;
  let inBlockComment = false;
  let dollarQuoteTag = null;

  while (index < sqlText.length) {
    const char = sqlText[index];
    const nextChar = sqlText[index + 1];

    if (inLineComment) {
      current += char;
      index += 1;
      if (char === '\n') {
        inLineComment = false;
      }
      continue;
    }

    if (inBlockComment) {
      if (char === '*' && nextChar === '/') {
        current += '*/';
        index += 2;
        inBlockComment = false;
        continue;
      }

      current += char;
      index += 1;
      continue;
    }

    if (dollarQuoteTag != null) {
      if (sqlText.startsWith(dollarQuoteTag, index)) {
        current += dollarQuoteTag;
        index += dollarQuoteTag.length;
        dollarQuoteTag = null;
        continue;
      }

      current += char;
      index += 1;
      continue;
    }

    if (inSingleQuote) {
      current += char;
      index += 1;

      if (char === '\'' && nextChar === '\'') {
        current += nextChar;
        index += 1;
        continue;
      }

      if (char === '\'') {
        inSingleQuote = false;
      }

      continue;
    }

    if (inDoubleQuote) {
      current += char;
      index += 1;

      if (char === '"' && nextChar === '"') {
        current += nextChar;
        index += 1;
        continue;
      }

      if (char === '"') {
        inDoubleQuote = false;
      }

      continue;
    }

    if (char === '-' && nextChar === '-') {
      current += '--';
      index += 2;
      inLineComment = true;
      continue;
    }

    if (char === '/' && nextChar === '*') {
      current += '/*';
      index += 2;
      inBlockComment = true;
      continue;
    }

    if (char === '\'') {
      current += char;
      index += 1;
      inSingleQuote = true;
      continue;
    }

    if (char === '"') {
      current += char;
      index += 1;
      inDoubleQuote = true;
      continue;
    }

    if (char === '$') {
      const match = sqlText.slice(index).match(/^\$\$|^\$[A-Za-z_][A-Za-z0-9_]*\$/);
      if (match) {
        dollarQuoteTag = match[0];
        current += dollarQuoteTag;
        index += dollarQuoteTag.length;
        continue;
      }
    }

    if (char === ';') {
      const statement = current.trim();
      if (statement) {
        statements.push(statement);
      }
      current = '';
      index += 1;
      continue;
    }

    current += char;
    index += 1;
  }

  const trailingStatement = current.trim();
  if (trailingStatement) {
    statements.push(trailingStatement);
  }

  return statements;
}

async function runSqlFile(client, filePath) {
  const sqlText = fs.readFileSync(filePath, 'utf8');
  const statements = splitSqlStatements(sqlText);

  for (const statement of statements) {
    await client.query(statement);
  }

  return statements.length;
}

module.exports = {
  runSqlFile,
  splitSqlStatements,
};
