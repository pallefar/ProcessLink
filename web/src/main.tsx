import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import ProcessLink from './App'
import './styles.css'

const root = document.getElementById('root')
if (!root) throw new Error('Missing #root')

createRoot(root).render(
  <StrictMode>
    <ProcessLink />
  </StrictMode>,
)
