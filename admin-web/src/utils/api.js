const runtimeApiBase =
  typeof window !== 'undefined' ? window.PIKI_API_BASE_URL : ''
const buildApiBase = import.meta.env.VITE_API_BASE_URL

export const apiBaseUrl = String(runtimeApiBase || buildApiBase || '')
  .trim()
  .replace(/\/+$/, '')

export function apiUrl(path) {
  const value = String(path || '')
  if (!value.startsWith('/api/')) {
    return value
  }
  return apiBaseUrl ? `${apiBaseUrl}${value}` : value
}

export async function readApiJson(response) {
  const contentType = response.headers.get('content-type') || ''
  if (contentType.toLowerCase().includes('application/json')) {
    return response.json()
  }

  const text = await response.text().catch(() => '')
  const looksLikeHtml = /^\s*<!doctype html|^\s*<html|^\s*</i.test(text)
  if (looksLikeHtml) {
    throw new Error(
      'The admin panel received HTML instead of backend JSON. In Coolify, set the admin service BACKEND_URL or PIKI_API_BASE_URL to https://pikipos.com, then redeploy.',
    )
  }

  throw new Error('The backend returned a non-JSON response.')
}
