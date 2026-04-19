function normalizeCursor(value) {
  if (value == null) {
    return null;
  }

  const trimmed = String(value).trim();
  if (!trimmed) {
    return null;
  }
  if (!/^\d+$/.test(trimmed)) {
    throw new Error('Invalid cursor');
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
