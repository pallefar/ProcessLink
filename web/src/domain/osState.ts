/** OS-backed ProcessLink state. When mounted under /processlink/ the OS
 * session authorizes these reads/writes; standalone preview fails closed to
 * the caller's localStorage fallback. */
export async function loadOsState<T>(key: string): Promise<T | null> {
  try {
    const response = await fetch(`/api/processlink/state?key=${encodeURIComponent(key)}`, {
      credentials: 'same-origin', headers: { accept: 'application/json' },
    })
    if (!response.ok) return null
    const body = await response.json() as { value?: T | null }
    return body.value ?? null
  } catch {
    return null
  }
}

export async function saveOsState(key: string, value: unknown): Promise<boolean> {
  try {
    const response = await fetch('/api/processlink/state', {
      method: 'PUT', credentials: 'same-origin',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ key, value }),
    })
    return response.ok
  } catch {
    return false
  }
}
