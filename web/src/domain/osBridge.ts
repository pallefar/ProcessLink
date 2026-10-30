/** Same-origin OS reads. When ProcessLink is mounted at /processlink/ the OS
 * session cookie applies; standalone previews simply get null. */
export async function osGet<T>(path: string): Promise<T | null> {
  try {
    const response = await fetch(path, { credentials: 'same-origin', headers: { accept: 'application/json' } })
    if (!response.ok) return null
    return await response.json() as T
  } catch {
    return null
  }
}

export interface LiveMap {
  id: string
  label: string
  approved: boolean
  steps: number
  state: string
}

export interface LiveVision {
  strategy?: { body?: { title?: string; fiscalYear?: string | null } }
}

export interface LiveProjects {
  workspaceId: string
  defaultProjectId: string
  projects: Array<{ id: string; label: string; enabled: boolean; isDefault: boolean }>
}

export interface VisionRoadmap {
  records: Array<{ id: string; body?: { title?: string; stage?: string; status?: string } }>
}

export interface DeckForgeDecks {
  items: Array<{ deckId: string; title: string; revision: number; updatedAt: string }>
}
