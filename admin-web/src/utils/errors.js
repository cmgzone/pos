export function friendlyError(error, fallback = 'Something went wrong. Please try again.') {
  const raw = String(error?.message || error || '').trim()
  if (!raw) return fallback

  const lower = raw.toLowerCase()
  if (
    lower.includes('failed to fetch') ||
    lower.includes('networkerror') ||
    lower.includes('connection refused') ||
    lower.includes('failed host lookup') ||
    lower.includes('socket')
  ) {
    return 'The server could not be reached. Check the connection and try again.'
  }
  if (lower.includes('timeout') || lower.includes('timed out')) {
    return 'The request took too long. Please try again.'
  }
  if (
    lower.includes('received html instead of backend json') ||
    lower.includes('unexpected token') ||
    lower.includes('not valid json') ||
    lower.includes('bad gateway')
  ) {
    return 'The admin panel is not reaching the backend API. In Coolify, set the admin service BACKEND_URL or PIKI_API_BASE_URL to https://pikipos.com, then redeploy.'
  }
  if (lower.includes('401') || lower.includes('unauthorized') || lower.includes('jwt')) {
    return 'Your session has expired. Please sign in again.'
  }
  if (lower.includes('403') || lower.includes('forbidden')) {
    return 'You do not have permission to do that.'
  }
  if (lower.includes('413') || lower.includes('payload too large') || lower.includes('entity too large') || lower.includes('too large')) {
    return 'The file is too large to upload. Use a smaller build, or raise the upload limit on the server.'
  }
  if (
    lower.includes('database') ||
    lower.includes('sql') ||
    lower.includes('stack') ||
    lower.includes('typeerror') ||
    lower.includes('referenceerror') ||
    lower.includes('undefined') ||
    lower.includes('null') ||
    lower.includes('/api/') ||
    lower.includes('http://') ||
    lower.includes('https://')
  ) {
    return fallback
  }

  const cleaned = raw
    .replace(/^Error:\s*/i, '')
    .replace(/^Exception:\s*/i, '')
    .replace(/\s+/g, ' ')
    .trim()

  if (!cleaned || cleaned.length > 180) return fallback
  return /[.!?]$/.test(cleaned) ? cleaned : `${cleaned}.`
}
