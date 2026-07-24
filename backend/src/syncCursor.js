function normalizeCursor(value) {
  if (value == null) {
    return null;
  }

  const trimmed = String(value).trim();
  if (!trimmed) {
    return null;
  }
  if (!/^\d+$/.test(trimmed)) {
    const error = new Error('Invalid cursor');
    error.statusCode = 400;
    throw error;
  }

  return BigInt(trimmed).toString();
}

function maxCursor(currentCursor, candidateCursor) {
  const current = normalizeCursor(currentCursor);
  const candidate = normalizeCursor(candidateCursor);

  if (candidate == null) {
    return current;
  }
  if (current == null) {
    return candidate;
  }

  return BigInt(candidate) > BigInt(current) ? candidate : current;
}

module.exports = {
  maxCursor,
  normalizeCursor,
};
