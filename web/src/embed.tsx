import { StrictMode } from 'react'
import { createRoot, type Root } from 'react-dom/client'
import ProcessLink from './App'
import styles from './styles.css?inline'

export interface MountOptions {
  workspace?: string
  project?: string
}

let root: Root | null = null
let hostEl: HTMLElement | null = null

/** Mount ProcessLink inside the host's shadow root so the OS and the app do
 * not leak CSS or DOM ids into each other. */
export function mount(host: HTMLElement, _options: MountOptions = {}): () => void {
  unmount()
  const shadow = host.shadowRoot ?? host.attachShadow({ mode: 'open' })
  const style = document.createElement('style')
  style.textContent = styles
    .replace(/:root/g, ':host')
    .replace(/html, body, #root/g, ':host, #processlink-root')
    .replace(/(^|\n)body\s*\{/g, '$1#processlink-root {')
  const container = document.createElement('div')
  container.id = 'processlink-root'
  container.style.height = '100%'
  shadow.append(style, container)
  hostEl = host
  root = createRoot(container)
  root.render(<StrictMode><ProcessLink embedded /></StrictMode>)
  return unmount
}

export function unmount(): void {
  root?.unmount()
  root = null
  if (hostEl?.shadowRoot) hostEl.shadowRoot.innerHTML = ''
  hostEl = null
}
