import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App.tsx'

// TEMP DEBUG: konsol mini di layar buat liat console.log/error langsung di HP,
// gak butuh laptop / chrome://inspect. Muncul tombol kecil ngambang di pojok.
// HAPUS 2 BARIS INI (import + init) SETELAH SELESAI DEBUG NOTIFIKASI.
import eruda from 'eruda'
eruda.init()

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
)
