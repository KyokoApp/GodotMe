import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App.tsx'

// Force dark background immediately before React mounts
document.documentElement.style.backgroundColor = '#0a0a0a';
document.body.style.backgroundColor = '#0a0a0a';
document.body.style.color = '#ffffff';

const rootEl = document.getElementById('root');
if (rootEl) {
  rootEl.style.backgroundColor = '#0a0a0a';
  rootEl.style.minHeight = '100vh';
  createRoot(rootEl).render(
    <StrictMode>
      <App />
    </StrictMode>,
  );
}
