import React, { useState, useRef, useCallback, useEffect } from 'react';
import {
  Upload, Download, Share2, RotateCcw, ZoomIn, ZoomOut,
  Sparkles, ImagePlus, ChevronLeft, Check, Plus, Trash2,
  Package, Wand2, Sun, Zap, Flame, MoreVertical,
} from 'lucide-react';

interface StickerMakerPanelProps {
  isOpen: boolean;
  onClose: () => void;
}

type ShapeMode = 'square' | 'circle' | 'rounded';
type FilterMode = 'none' | 'vivid' | 'pop' | 'neon';
type Screen = 'pack' | 'upload' | 'edit' | 'done';

interface StickerItem {
  id: string;
  url: string;
  shape: ShapeMode;
}

const CANVAS_SIZE = 260;
const WA_STICKER_SIZE = 512;       // px — WhatsApp requirement
const WA_TRAY_SIZE    = 96;        // px — WhatsApp requirement
const WA_MAX_STICKER_KB = 100;     // KB — WhatsApp requirement per sticker
const WA_MAX_TRAY_KB    = 50;      // KB — WhatsApp requirement for tray icon
const WA_MIN_STICKERS   = 3;       // WhatsApp minimum
const WA_MAX_STICKERS   = 30;      // WhatsApp maximum

// ─── Logging helper ──────────────────────────────────────────────────────────
const LOG_TAG = '[StickerMaker]';
const log  = (...args: any[]) => console.log (LOG_TAG, ...args);
const warn = (...args: any[]) => console.warn(LOG_TAG, '⚠️', ...args);
const err  = (...args: any[]) => console.error(LOG_TAG, '❌', ...args);

// ─── WhatsApp detection (best-effort in web/Capacitor context) ────────────────
const isWhatsAppInstalled = (): boolean => {
  const ua = navigator.userAgent.toLowerCase();
  // Heuristic: jika running di Android WebView (Capacitor), WA almost always ada
  const isAndroid = /android/.test(ua);
  const isCapacitor = !!(window as any).Capacitor?.isNativePlatform?.();
  log('isWhatsAppInstalled check — android:', isAndroid, 'capacitor:', isCapacitor);
  // Tidak bisa 100% deteksi dari web layer; return true as optimistic assumption
  return isAndroid || isCapacitor;
};

const StickerMakerPanel: React.FC<StickerMakerPanelProps> = ({ isOpen, onClose }) => {
  const [screen, setScreen] = useState<Screen>('upload');
  const [pack, setPack] = useState<StickerItem[]>([]);
  const [packName] = useState('Pack 1');

  // Editor state
  const [image, setImage] = useState<HTMLImageElement | null>(null);
  const [imageDataUrl, setImageDataUrl] = useState<string | null>(null);
  const [shape, setShape] = useState<ShapeMode>('rounded');
  const [filter, setFilter] = useState<FilterMode>('none');
  const [zoom, setZoom] = useState(1);
  const [offsetX, setOffsetX] = useState(0);
  const [offsetY, setOffsetY] = useState(0);
  const [isDragging, setIsDragging] = useState(false);
  const [dragStart, setDragStart] = useState({ x: 0, y: 0 });
  const [stickerUrl, setStickerUrl] = useState<string | null>(null);
  const [sharing, setSharing] = useState(false);
  const [toastMsg, setToastMsg] = useState<string | null>(null);
  const [selectedId, setSelectedId] = useState<string | null>(null);

  // ── Load JSZip from CDN ───────────────────────────────────────────────────
  const loadJSZip = (): Promise<any> =>
    new Promise((resolve, reject) => {
      if ((window as any).JSZip) { resolve((window as any).JSZip); return; }
      const s = document.createElement('script');
      s.src = 'https://cdnjs.cloudflare.com/ajax/libs/jszip/3.10.1/jszip.min.js';
      s.onload  = () => { log('JSZip loaded'); resolve((window as any).JSZip); };
      s.onerror = () => reject(new Error('Gagal load JSZip dari CDN'));
      document.head.appendChild(s);
    });

  const previewCanvasRef = useRef<HTMLCanvasElement>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const showToast = (msg: string) => {
    setToastMsg(msg);
    setTimeout(() => setToastMsg(null), 3000);
  };

  // ─────────────────────────────────────────────────────────────────────────
  //  Canvas draw (unchanged)
  // ─────────────────────────────────────────────────────────────────────────
  const drawPreview = useCallback(() => {
    const canvas = previewCanvasRef.current;
    if (!canvas || !image) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;
    const size = canvas.width;
    ctx.clearRect(0, 0, size, size);
    ctx.save();
    if (shape === 'circle') {
      ctx.beginPath(); ctx.arc(size / 2, size / 2, size / 2, 0, Math.PI * 2); ctx.clip();
    } else if (shape === 'rounded') {
      const r = size * 0.18;
      ctx.beginPath();
      ctx.moveTo(r, 0); ctx.lineTo(size - r, 0); ctx.arcTo(size, 0, size, r, r);
      ctx.lineTo(size, size - r); ctx.arcTo(size, size, size - r, size, r);
      ctx.lineTo(r, size); ctx.arcTo(0, size, 0, size - r, r);
      ctx.lineTo(0, r); ctx.arcTo(0, 0, r, 0, r); ctx.closePath(); ctx.clip();
    }
    const aspect = image.width / image.height;
    let drawW, drawH;
    if (aspect >= 1) { drawH = size * zoom; drawW = drawH * aspect; }
    else { drawW = size * zoom; drawH = drawW / aspect; }
    const dx = (size - drawW) / 2 + offsetX;
    const dy = (size - drawH) / 2 + offsetY;
    if (filter === 'vivid') ctx.filter = 'saturate(1.8) contrast(1.1)';
    else if (filter === 'pop') ctx.filter = 'saturate(2) brightness(1.1) contrast(1.15)';
    else if (filter === 'neon') ctx.filter = 'saturate(3) brightness(1.2) hue-rotate(20deg) contrast(1.2)';
    else ctx.filter = 'none';
    ctx.drawImage(image, dx, dy, drawW, drawH);
    ctx.filter = 'none'; ctx.restore();
    ctx.save();
    ctx.strokeStyle = 'rgba(255,255,255,0.92)'; ctx.lineWidth = size * 0.024;
    const lw = ctx.lineWidth / 2;
    if (shape === 'circle') {
      ctx.beginPath(); ctx.arc(size / 2, size / 2, size / 2 - lw, 0, Math.PI * 2); ctx.stroke();
    } else if (shape === 'rounded') {
      const r = size * 0.18 - lw;
      ctx.beginPath();
      ctx.moveTo(r + lw, lw); ctx.lineTo(size - r - lw, lw); ctx.arcTo(size - lw, lw, size - lw, r + lw, r);
      ctx.lineTo(size - lw, size - r - lw); ctx.arcTo(size - lw, size - lw, size - r - lw, size - lw, r);
      ctx.lineTo(r + lw, size - lw); ctx.arcTo(lw, size - lw, lw, size - r - lw, r);
      ctx.lineTo(lw, r + lw); ctx.arcTo(lw, lw, r + lw, lw, r); ctx.closePath(); ctx.stroke();
    } else { ctx.strokeRect(lw, lw, size - lw * 2, size - lw * 2); }
    ctx.restore();
  }, [image, shape, filter, zoom, offsetX, offsetY]);

  useEffect(() => { drawPreview(); }, [drawPreview]);

  useEffect(() => {
    if (!isOpen) {
      setPack([]); setScreen('upload');
      setImage(null); setImageDataUrl(null);
      setStickerUrl(null); setZoom(1); setOffsetX(0); setOffsetY(0);
      setFilter('none'); setShape('rounded');
    }
  }, [isOpen]);

  const resetEditor = () => {
    setImage(null); setImageDataUrl(null); setStickerUrl(null);
    setZoom(1); setOffsetX(0); setOffsetY(0); setFilter('none'); setShape('rounded');
  };

  const handleFileSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    const url = URL.createObjectURL(file);
    const img = new Image();
    img.onload = () => {
      setImage(img); setImageDataUrl(url);
      setZoom(1); setOffsetX(0); setOffsetY(0); setStickerUrl(null);
      setScreen('edit');
    };
    img.src = url; e.target.value = '';
  };

  const handleMouseDown = (e: React.MouseEvent | React.TouchEvent) => {
    if (!image) return; setIsDragging(true);
    const pos = 'touches' in e ? e.touches[0] : e;
    setDragStart({ x: pos.clientX - offsetX, y: pos.clientY - offsetY });
  };
  const handleMouseMove = (e: React.MouseEvent | React.TouchEvent) => {
    if (!isDragging) return;
    const pos = 'touches' in e ? e.touches[0] : e;
    setOffsetX(pos.clientX - dragStart.x); setOffsetY(pos.clientY - dragStart.y);
  };
  const handleMouseUp = () => setIsDragging(false);

  const generateSticker = () => {
    const canvas = previewCanvasRef.current;
    if (!canvas) return;
    const url = canvas.toDataURL('image/png');
    setStickerUrl(url);
    const newItem: StickerItem = { id: Date.now().toString(), url, shape };
    setPack(prev => [...prev, newItem]);
    setScreen('done');
    showToast('✨ Stiker ditambahkan ke pack!');
  };

  const deleteSticker = (id: string) => {
    setPack(prev => prev.filter(s => s.id !== id));
    setSelectedId(null);
  };

  // ─────────────────────────────────────────────────────────────────────────
  //  Convert dataURL → N×N WebP base64, auto-compress to stay under maxKB
  // ─────────────────────────────────────────────────────────────────────────
  const toWebpBase64 = (
    dataUrl: string,
    size: number,
    maxKB: number,
  ): Promise<string> =>
    new Promise((resolve, reject) => {
      const img = new Image();
      img.onload = () => {
        const c = document.createElement('canvas');
        c.width = size; c.height = size;
        const ctx = c.getContext('2d')!;
        ctx.clearRect(0, 0, size, size);
        // cover-fit so sticker fills the square
        const scale = Math.max(size / img.width, size / img.height);
        const w = img.width * scale, h = img.height * scale;
        ctx.drawImage(img, (size - w) / 2, (size - h) / 2, w, h);

        // Step-down quality until under maxKB
        let quality = 0.90;
        let b64 = c.toDataURL('image/webp', quality).split(',')[1];
        while (b64.length * 0.75 > maxKB * 1024 && quality > 0.20) {
          quality = parseFloat((quality - 0.08).toFixed(2));
          b64 = c.toDataURL('image/webp', quality).split(',')[1];
        }
        const finalKB = Math.round(b64.length * 0.75 / 1024);
        log(`toWebpBase64 ${size}x${size} → ${finalKB}KB (quality=${quality})`);
        if (finalKB > maxKB) {
          warn(`Image still ${finalKB}KB after compression (max ${maxKB}KB). WhatsApp may reject it.`);
        }
        resolve(b64);
      };
      img.onerror = () => reject(new Error('Image load failed in toWebpBase64'));
      img.src = dataUrl;
    });

  // ─────────────────────────────────────────────────────────────────────────
  //  BUILD .wastickers ZIP
  //  Format: Official WhatsApp Sticker Pack API
  //  Ref: https://github.com/WhatsApp/stickers
  // ─────────────────────────────────────────────────────────────────────────
  const buildWastickers = async (): Promise<Blob> => {
    log('buildWastickers() start — pack.length:', pack.length);

    const JSZip = await loadJSZip();
    const zip = new JSZip();

    // ── 1. contents.json (OFFICIAL format dengan sticker_packs wrapper) ────
    //  Bug lama: format flat tanpa sticker_packs → WhatsApp tidak mengenali pack
    //  Fix: gunakan format resmi dengan sticker_packs array + semua field wajib
    const packIdentifier = `kyokobeat_${packName.replace(/\s+/g, '_').toLowerCase()}_${Date.now()}`;
    const stickersJson = pack.map((_, i) => ({
      image_file: `${i + 1}.webp`,
      emojis: ['😊'],
    }));

    const contentsJson = {
      android_play_store_link: '',
      ios_app_store_link: '',
      sticker_packs: [
        {
          identifier:                packIdentifier,       // WAJIB — unik per pack
          name:                      packName,             // WAJIB — nama pack
          publisher:                 'KyokoBeat',          // WAJIB — nama publisher
          tray_image_file:           'tray_icon.webp',     // WAJIB — harus WebP, 96x96
          publisher_email:           '',
          publisher_website:         '',
          privacy_policy_website:    '',
          license_agreement_website: '',
          image_data_version:        '1',
          avoid_cache:               false,
          animated_sticker_pack:     false,
          stickers:                  stickersJson,         // WAJIB — min 3, max 30
        },
      ],
    };

    log('contents.json:\n', JSON.stringify(contentsJson, null, 2));
    zip.file('contents.json', JSON.stringify(contentsJson, null, 2));

    // ── 2. tray_icon.webp — 96×96 WebP, max 50 KB ─────────────────────────
    //  Bug lama: file PNG bernama 'tray.png' → WhatsApp tidak bisa baca
    //  Fix: WebP 96×96, nama persis 'tray_icon.webp' sesuai contents.json
    log('Creating tray_icon.webp (96×96 WebP)...');
    const trayBase64 = await toWebpBase64(pack[0].url, WA_TRAY_SIZE, WA_MAX_TRAY_KB);
    zip.file('tray_icon.webp', trayBase64, { base64: true });
    log('tray_icon.webp done —', Math.round(trayBase64.length * 0.75 / 1024), 'KB');

    // ── 3. Sticker files — 512×512 WebP, max 100 KB each ──────────────────
    for (let i = 0; i < pack.length; i++) {
      log(`Processing sticker ${i + 1}/${pack.length}...`);
      const b64 = await toWebpBase64(pack[i].url, WA_STICKER_SIZE, WA_MAX_STICKER_KB);
      zip.file(`${i + 1}.webp`, b64, { base64: true });
      log(`Sticker ${i + 1}.webp — ${Math.round(b64.length * 0.75 / 1024)}KB`);
    }

    const blob = await zip.generateAsync({ type: 'blob' });
    log('buildWastickers() complete —', Math.round(blob.size / 1024), 'KB total');
    return blob;
  };

  // ─────────────────────────────────────────────────────────────────────────
  //  ADD STICKER PACK TO WHATSAPP
  //  Menggunakan Web Share API (Capacitor Android menggunakan native share sheet)
  //  MIME type: application/x-stickers-android (yang WhatsApp register sebagai handler)
  // ─────────────────────────────────────────────────────────────────────────
  const addStickerPackToWhatsApp = async (blob: Blob): Promise<'success' | 'download' | 'cancelled'> => {
    const fileName = `${packName.replace(/[^a-zA-Z0-9_-]/g, '_')}.wastickers`;
    log('addStickerPackToWhatsApp() — file:', fileName, 'size:', Math.round(blob.size / 1024), 'KB');
    log('WhatsApp installed (estimate):', isWhatsAppInstalled());

    // MIME types dicoba berurutan — WA mendaftar sebagai handler untuk keduanya
    const mimeTypes = [
      'application/x-stickers-android',  // Official WA sticker MIME type
      'application/zip',                  // Fallback karena .wastickers adalah ZIP
    ];

    if (navigator.share) {
      for (const mimeType of mimeTypes) {
        try {
          const file = new File([blob], fileName, { type: mimeType });
          const canShare = navigator.canShare?.({ files: [file] });
          log(`canShare with ${mimeType}:`, canShare);

          if (canShare) {
            log(`Attempting navigator.share with MIME: ${mimeType}`);
            await navigator.share({
              title: packName,
              files: [file],
            });
            log('navigator.share() resolved — user completed share');
            return 'success';
          }
        } catch (e: any) {
          if (e.name === 'AbortError') {
            log('User cancelled share dialog');
            return 'cancelled';
          }
          warn(`Share with ${mimeType} failed:`, e.name, e.message);
        }
      }

      // Last try: share tanpa canShare check (beberapa browser tidak implement canShare)
      try {
        log('Trying share without canShare guard...');
        const file = new File([blob], fileName, { type: 'application/x-stickers-android' });
        await navigator.share({ title: packName, files: [file] });
        return 'success';
      } catch (e: any) {
        if (e.name === 'AbortError') return 'cancelled';
        warn('Final share attempt failed:', e.name, e.message);
      }
    } else {
      log('navigator.share not available — falling back to download');
    }

    // ── Fallback: download file ──────────────────────────────────────────
    log('Fallback: downloading .wastickers file');
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = fileName;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    setTimeout(() => URL.revokeObjectURL(url), 5000);
    log('File downloaded:', fileName);
    return 'download';
  };

  // ─────────────────────────────────────────────────────────────────────────
  //  HANDLE EXPORT — entry point dari tombol
  // ─────────────────────────────────────────────────────────────────────────
  const handleExportPack = async () => {
    log('handleExportPack() — pack.length:', pack.length);

    if (pack.length === 0) {
      warn('Pack kosong, tidak bisa export');
      return;
    }
    if (pack.length < WA_MIN_STICKERS) {
      const msg = `⚠️ Butuh minimal ${WA_MIN_STICKERS} stiker (sekarang ${pack.length})`;
      warn(msg); showToast(msg); return;
    }
    if (pack.length > WA_MAX_STICKERS) {
      const msg = `⚠️ Maksimal ${WA_MAX_STICKERS} stiker per pack (sekarang ${pack.length})`;
      warn(msg); showToast(msg); return;
    }

    setSharing(true);
    showToast('⏳ Membangun sticker pack...');
    log('Validation passed — starting build');

    try {
      const blob = await buildWastickers();
      log('Build success — starting WhatsApp send');
      showToast('📤 Membuka WhatsApp...');

      const result = await addStickerPackToWhatsApp(blob);
      log('addStickerPackToWhatsApp result:', result);

      if (result === 'success') {
        showToast('✅ Pack berhasil dikirim! Tekan "Add" di WhatsApp.');
      } else if (result === 'download') {
        showToast('📥 Diunduh! Buka file .wastickers → pilih WhatsApp → Add stickers');
      }
      // cancelled: tidak perlu toast
    } catch (e: any) {
      err('handleExportPack failed:', e.name, e.message, e.stack);
      showToast(`❌ Gagal: ${e.message}`);
    } finally {
      setSharing(false);
    }
  };

  const borderRadius = (s: ShapeMode) => s === 'circle' ? '50%' : s === 'rounded' ? '28px' : '8px';

  const filters: { key: FilterMode; label: string; icon: React.ReactNode; color: string }[] = [
    { key: 'none',  label: 'Original', icon: <Wand2 size={15} />, color: '#94a3b8' },
    { key: 'vivid', label: 'Vivid',    icon: <Sun   size={15} />, color: '#f59e0b' },
    { key: 'pop',   label: 'Pop',      icon: <Flame size={15} />, color: '#f43f5e' },
    { key: 'neon',  label: 'Neon',     icon: <Zap   size={15} />, color: '#8b5cf6' },
  ];

  const totalSize = (pack.length * 25).toFixed(0);

  // ─────────────────────────────────────────────────────────────────────────
  //  PACK SCREEN
  // ─────────────────────────────────────────────────────────────────────────
  const PackScreen = (
    <div className="fixed inset-0 z-[100] flex flex-col" style={{ background: '#f8fafc' }}>
      {/* Header */}
      <div className="flex-shrink-0 flex items-center justify-between px-4 pt-12 pb-4"
        style={{ background: 'white', borderBottom: '1px solid #e2e8f0' }}>
        <button onClick={onClose}
          className="w-9 h-9 flex items-center justify-center rounded-full transition-all active:scale-90"
          style={{ background: '#f1f5f9' }}>
          <ChevronLeft size={20} color="#475569" />
        </button>
        <div className="flex items-center gap-3">
          {pack.length > 0 && (
            <div className="w-10 h-10 rounded-xl overflow-hidden"
              style={{ border: '2px solid #e2e8f0' }}>
              <img src={pack[0].url} className="w-full h-full object-cover" />
            </div>
          )}
          <div>
            <p className="font-black text-gray-800 text-sm" style={{ fontFamily: "'Nunito', sans-serif" }}>
              {packName}
            </p>
            <p className="text-xs text-gray-400">{pack.length > 0 ? `${totalSize} kB` : 'Kosong'}</p>
          </div>
        </div>
        <button className="w-9 h-9 flex items-center justify-center rounded-full"
          style={{ background: '#f1f5f9' }}>
          <MoreVertical size={18} color="#94a3b8" />
        </button>
      </div>

      {/* Sticker grid */}
      <div className="flex-1 overflow-y-auto p-4">
        {pack.length === 0 ? (
          <div className="flex flex-col items-center justify-center h-full gap-4 py-20">
            <div className="w-20 h-20 rounded-3xl flex items-center justify-center"
              style={{ background: '#f1f5f9', border: '2px dashed #cbd5e1' }}>
              <Package size={32} color="#94a3b8" />
            </div>
            <div className="text-center">
              <p className="font-black text-gray-500 text-base" style={{ fontFamily: "'Nunito', sans-serif" }}>
                Pack masih kosong
              </p>
              <p className="text-sm text-gray-400 mt-1">Tap + untuk tambah stiker pertama</p>
            </div>
          </div>
        ) : (
          <div className="grid grid-cols-3 gap-3">
            {pack.map(sticker => (
              <div key={sticker.id} className="relative aspect-square"
                onClick={() => setSelectedId(selectedId === sticker.id ? null : sticker.id)}>
                <div className="w-full h-full rounded-2xl overflow-hidden transition-all"
                  style={{
                    border: selectedId === sticker.id ? '2.5px solid #00c47c' : '2px solid #e2e8f0',
                    boxShadow: selectedId === sticker.id ? '0 0 0 3px rgba(0,196,124,0.15)' : 'none',
                    background: 'white',
                  }}>
                  <img src={sticker.url} className="w-full h-full object-cover"
                    style={{ borderRadius: borderRadius(sticker.shape) }} />
                </div>
                {selectedId === sticker.id && (
                  <button
                    onClick={(e) => { e.stopPropagation(); deleteSticker(sticker.id); }}
                    className="absolute -top-2 -right-2 w-6 h-6 rounded-full flex items-center justify-center"
                    style={{ background: '#ef4444', boxShadow: '0 2px 8px rgba(239,68,68,0.4)' }}>
                    <Trash2 size={11} color="white" />
                  </button>
                )}
              </div>
            ))}
            {/* Add tile */}
            <button
              onClick={() => { resetEditor(); setScreen('upload'); }}
              className="aspect-square rounded-2xl flex items-center justify-center transition-all active:scale-95"
              style={{ border: '2px dashed #00c47c', background: 'rgba(0,196,124,0.04)' }}>
              <div className="w-10 h-10 rounded-full flex items-center justify-center"
                style={{ background: 'rgba(0,196,124,0.1)' }}>
                <Plus size={22} color="#00c47c" />
              </div>
            </button>
          </div>
        )}
      </div>

      {/* Export button */}
      <div className="flex-shrink-0 p-4 pt-3"
        style={{ background: 'white', borderTop: '1px solid #e2e8f0', paddingBottom: 'max(1rem, env(safe-area-inset-bottom))' }}>
        {pack.length > 0 && (
          <div className="mb-3 px-3 py-2 rounded-xl flex items-start gap-2"
            style={{ background: pack.length < WA_MIN_STICKERS ? 'rgba(245,158,11,0.08)' : 'rgba(0,196,124,0.07)', border: `1px solid ${pack.length < WA_MIN_STICKERS ? 'rgba(245,158,11,0.25)' : 'rgba(0,196,124,0.18)'}` }}>
            <span className="text-sm">{pack.length < WA_MIN_STICKERS ? '⚠️' : '💡'}</span>
            <p className="text-xs leading-relaxed" style={{ color: '#475569' }}>
              {pack.length < WA_MIN_STICKERS
                ? `Tambah ${WA_MIN_STICKERS - pack.length} stiker lagi (min. ${WA_MIN_STICKERS} untuk dikirim ke WA)`
                : <>File <strong>.wastickers</strong> akan dibagikan ke WhatsApp. Tekan <em>"Add"</em> di preview WA untuk menggunakan.</>
              }
            </p>
          </div>
        )}
        {pack.length === 0 ? (
          <button
            onClick={() => { resetEditor(); setScreen('upload'); }}
            className="w-full py-4 flex items-center justify-center gap-2.5 rounded-2xl font-black text-white text-base transition-all active:scale-95"
            style={{
              background: 'linear-gradient(135deg, #00c47c, #00a86b)',
              boxShadow: '0 6px 24px rgba(0,196,124,0.35)',
              fontFamily: "'Nunito', sans-serif",
            }}>
            <Plus size={20} />
            Tambah Stiker
          </button>
        ) : (
          <button
            onClick={handleExportPack}
            disabled={sharing}
            className="w-full py-4 flex items-center justify-center gap-2.5 rounded-2xl font-black text-white text-base transition-all active:scale-95"
            style={{
              background: sharing ? '#94a3b8' : pack.length < WA_MIN_STICKERS ? '#cbd5e1' : 'linear-gradient(135deg, #25d366, #1ebe5b)',
              boxShadow: (sharing || pack.length < WA_MIN_STICKERS) ? 'none' : '0 6px 24px rgba(37,211,102,0.35)',
              fontFamily: "'Nunito', sans-serif",
            }}>
            {sharing
              ? <div className="w-5 h-5 border-2 border-white border-t-transparent rounded-full animate-spin" />
              : <Share2 size={20} />}
            {sharing
              ? 'Menyiapkan...'
              : pack.length < WA_MIN_STICKERS
                ? `Butuh ${WA_MIN_STICKERS - pack.length} stiker lagi...`
                : `Kirim ke WhatsApp (${pack.length} stiker)`}
          </button>
        )}
      </div>
    </div>
  );

  // ─────────────────────────────────────────────────────────────────────────
  //  UPLOAD SCREEN
  // ─────────────────────────────────────────────────────────────────────────
  const UploadScreen = (
    <div className="fixed inset-0 z-[100] flex flex-col" style={{ background: '#f8fafc' }}>
      <div className="flex-shrink-0 flex items-center justify-between px-4 pt-12 pb-4"
        style={{ background: 'linear-gradient(135deg, #00c47c 0%, #00a86b 100%)' }}>
        <button onClick={() => pack.length > 0 ? setScreen('pack') : onClose()}
          className="w-9 h-9 flex items-center justify-center rounded-full transition-all active:scale-90"
          style={{ background: 'rgba(255,255,255,0.2)' }}>
          <ChevronLeft size={20} color="white" />
        </button>
        <h1 className="font-black text-white" style={{ fontSize: 17, fontFamily: "'Nunito', sans-serif" }}>
          Pilih Foto
        </h1>
        <div className="w-9" />
      </div>

      <div className="flex-1 flex flex-col items-center justify-center px-6 gap-5">
        <button
          onClick={() => fileInputRef.current?.click()}
          className="w-full rounded-3xl flex flex-col items-center justify-center py-14 gap-4 transition-all active:scale-[0.98]"
          style={{ background: 'white', border: '2.5px dashed #00c47c', boxShadow: '0 4px 24px rgba(0,196,124,0.08)' }}>
          <div className="w-20 h-20 rounded-3xl flex items-center justify-center"
            style={{ background: 'linear-gradient(135deg, #e8fdf4, #d0fae8)', border: '2px solid rgba(0,196,124,0.2)' }}>
            <ImagePlus size={36} color="#00c47c" />
          </div>
          <div className="text-center">
            <p className="font-black text-gray-800 text-lg" style={{ fontFamily: "'Nunito', sans-serif" }}>
              Pilih dari Galeri
            </p>
            <p className="text-sm text-gray-400 mt-1">JPG, PNG, WEBP</p>
          </div>
          <div className="px-6 py-2.5 rounded-full font-bold text-sm text-white"
            style={{ background: 'linear-gradient(135deg, #00c47c, #00a86b)' }}>
            📷 Buka Galeri
          </div>
        </button>
        <p className="text-xs text-gray-400 text-center">
          {pack.length > 0 ? `Pack kamu sudah punya ${pack.length} stiker` : 'Stiker pertama kamu!'}
        </p>
      </div>
    </div>
  );

  // ─────────────────────────────────────────────────────────────────────────
  //  EDIT SCREEN
  // ─────────────────────────────────────────────────────────────────────────
  const EditScreen = (
    <div className="fixed inset-0 z-[100] flex flex-col" style={{ background: '#f1f5f9' }}>
      {/* Header */}
      <div className="flex-shrink-0 flex items-center justify-between px-4 pt-12 pb-4"
        style={{ background: 'linear-gradient(135deg, #00c47c 0%, #00a86b 100%)' }}>
        <button onClick={() => setScreen('upload')}
          className="w-9 h-9 flex items-center justify-center rounded-full transition-all active:scale-90"
          style={{ background: 'rgba(255,255,255,0.2)' }}>
          <ChevronLeft size={20} color="white" />
        </button>
        <h1 className="font-black text-white" style={{ fontSize: 17, fontFamily: "'Nunito', sans-serif" }}>
          Edit Stiker
        </h1>
        <button onClick={generateSticker}
          className="px-4 py-1.5 rounded-full font-black text-sm transition-all active:scale-95"
          style={{ background: 'white', color: '#00c47c', boxShadow: '0 2px 12px rgba(0,0,0,0.12)' }}>
          Tambah ✓
        </button>
      </div>

      <div className="flex-1 overflow-y-auto">
        {/* Canvas */}
        <div className="flex flex-col items-center py-6 gap-2" style={{ background: 'white' }}>
          <div style={{ filter: 'drop-shadow(0 8px 28px rgba(0,0,0,0.15))' }}>
            <canvas
              ref={previewCanvasRef}
              width={CANVAS_SIZE} height={CANVAS_SIZE}
              className="block select-none"
              style={{
                borderRadius: shape === 'circle' ? '50%' : shape === 'rounded' ? '46px' : '12px',
                background: 'repeating-conic-gradient(#e2e8f0 0% 25%, white 0% 50%) 0 0 / 16px 16px',
                cursor: isDragging ? 'grabbing' : 'grab',
                touchAction: 'none',
                transition: 'border-radius 0.25s ease',
              }}
              onMouseDown={handleMouseDown} onMouseMove={handleMouseMove}
              onMouseUp={handleMouseUp} onMouseLeave={handleMouseUp}
              onTouchStart={handleMouseDown} onTouchMove={handleMouseMove} onTouchEnd={handleMouseUp}
            />
          </div>
          <p className="text-xs text-gray-400">✋ Geser untuk atur posisi</p>
        </div>

        <div className="px-4 py-4 flex flex-col gap-4">
          {/* Zoom */}
          <div className="rounded-2xl p-4" style={{ background: 'white', boxShadow: '0 2px 10px rgba(0,0,0,0.05)' }}>
            <div className="flex items-center justify-between mb-3">
              <span className="text-xs font-black text-gray-400 uppercase tracking-widest">Zoom</span>
              <span className="text-xs font-bold text-green-500">{Math.round(zoom * 100)}%</span>
            </div>
            <div className="flex items-center gap-3">
              <button onClick={() => setZoom(z => Math.max(0.5, parseFloat((z - 0.1).toFixed(2))))}
                className="w-8 h-8 rounded-xl flex items-center justify-center" style={{ background: '#f1f5f9' }}>
                <ZoomOut size={14} color="#64748b" />
              </button>
              <div className="flex-1 relative h-2 rounded-full" style={{ background: '#e2e8f0' }}>
                <div className="absolute inset-y-0 left-0 rounded-full"
                  style={{ width: `${((zoom - 0.5) / 2.5) * 100}%`, background: 'linear-gradient(90deg, #00c47c, #00e58c)' }} />
                <input type="range" min={0.5} max={3} step={0.05} value={zoom}
                  onChange={e => setZoom(parseFloat(e.target.value))}
                  className="absolute inset-0 w-full opacity-0 cursor-pointer h-full" />
              </div>
              <button onClick={() => setZoom(z => Math.min(3, parseFloat((z + 0.1).toFixed(2))))}
                className="w-8 h-8 rounded-xl flex items-center justify-center" style={{ background: '#f1f5f9' }}>
                <ZoomIn size={14} color="#64748b" />
              </button>
              <button onClick={() => { setZoom(1); setOffsetX(0); setOffsetY(0); }}
                className="w-8 h-8 rounded-xl flex items-center justify-center" style={{ background: '#f1f5f9' }}>
                <RotateCcw size={12} color="#64748b" />
              </button>
            </div>
          </div>

          {/* Shape */}
          <div className="rounded-2xl p-4" style={{ background: 'white', boxShadow: '0 2px 10px rgba(0,0,0,0.05)' }}>
            <span className="text-xs font-black text-gray-400 uppercase tracking-widest">Bentuk</span>
            <div className="flex gap-3 mt-3">
              {(['square', 'rounded', 'circle'] as ShapeMode[]).map(s => (
                <button key={s} onClick={() => setShape(s)}
                  className="flex-1 py-3 flex flex-col items-center gap-1.5 transition-all active:scale-95 rounded-2xl"
                  style={{
                    background: shape === s ? 'linear-gradient(135deg, #00c47c, #00a86b)' : '#f8fafc',
                    border: shape === s ? 'none' : '1.5px solid #e2e8f0',
                    boxShadow: shape === s ? '0 4px 14px rgba(0,196,124,0.3)' : 'none',
                  }}>
                  <div className="w-6 h-6 transition-all"
                    style={{
                      background: shape === s ? 'rgba(255,255,255,0.35)' : '#e2e8f0',
                      borderRadius: s === 'circle' ? '50%' : s === 'rounded' ? '7px' : '3px',
                    }} />
                  <span className="text-[11px] font-bold" style={{ color: shape === s ? 'white' : '#64748b' }}>
                    {s === 'square' ? 'Kotak' : s === 'rounded' ? 'Sudut' : 'Bulat'}
                  </span>
                </button>
              ))}
            </div>
          </div>

          {/* Filter */}
          <div className="rounded-2xl p-4" style={{ background: 'white', boxShadow: '0 2px 10px rgba(0,0,0,0.05)' }}>
            <span className="text-xs font-black text-gray-400 uppercase tracking-widest">Filter</span>
            <div className="grid grid-cols-4 gap-2 mt-3">
              {filters.map(f => (
                <button key={f.key} onClick={() => setFilter(f.key)}
                  className="flex flex-col items-center gap-1.5 py-3 rounded-2xl transition-all active:scale-95"
                  style={{
                    background: filter === f.key ? f.color : '#f8fafc',
                    border: filter === f.key ? 'none' : '1.5px solid #e2e8f0',
                    boxShadow: filter === f.key ? `0 4px 14px ${f.color}55` : 'none',
                  }}>
                  <span style={{ color: filter === f.key ? 'white' : f.color }}>{f.icon}</span>
                  <span className="text-[10px] font-bold" style={{ color: filter === f.key ? 'white' : '#64748b' }}>
                    {f.label}
                  </span>
                </button>
              ))}
            </div>
          </div>

          {/* CTA */}
          <button onClick={generateSticker}
            className="w-full py-4 flex items-center justify-center gap-2 rounded-2xl font-black text-white text-base transition-all active:scale-95 mb-4"
            style={{
              background: 'linear-gradient(135deg, #00c47c, #00a86b)',
              boxShadow: '0 6px 24px rgba(0,196,124,0.35)',
              fontFamily: "'Nunito', sans-serif",
            }}>
            <Sparkles size={18} />
            Tambahkan ke Pack
          </button>
        </div>
      </div>
    </div>
  );

  // ─────────────────────────────────────────────────────────────────────────
  //  DONE SCREEN
  // ─────────────────────────────────────────────────────────────────────────
  const DoneScreen = (
    <div className="fixed inset-0 z-[100] flex flex-col" style={{ background: '#f8fafc' }}>
      <div className="flex-shrink-0 flex items-center justify-between px-4 pt-12 pb-4"
        style={{ background: 'linear-gradient(135deg, #00c47c 0%, #00a86b 100%)' }}>
        <button onClick={() => setScreen('pack')}
          className="w-9 h-9 flex items-center justify-center rounded-full"
          style={{ background: 'rgba(255,255,255,0.2)' }}>
          <ChevronLeft size={20} color="white" />
        </button>
        <h1 className="font-black text-white" style={{ fontSize: 17, fontFamily: "'Nunito', sans-serif" }}>
          Buat Stiker
        </h1>
        <div className="flex items-center gap-1">
          {[0,1,2].map(i => (
            <div key={i} className="w-5 h-5 rounded-full flex items-center justify-center text-[10px] font-black"
              style={{ background: i <= 2 ? 'white' : 'rgba(255,255,255,0.3)', color: '#00c47c' }}>
              {i < 2 ? <Check size={10} /> : '3'}
            </div>
          ))}
        </div>
      </div>

      <div className="flex-1 overflow-y-auto flex flex-col items-center px-6 py-8 gap-5">
        <div className="w-16 h-16 rounded-full flex items-center justify-center"
          style={{ background: 'linear-gradient(135deg, #00c47c, #00e58c)', boxShadow: '0 6px 24px rgba(0,196,124,0.4)' }}>
          <Check size={28} color="white" strokeWidth={3} />
        </div>
        <div className="text-center">
          <h2 className="font-black text-gray-800 text-xl" style={{ fontFamily: "'Nunito', sans-serif" }}>
            Stiker Ditambahkan! 🎉
          </h2>
          <p className="text-sm text-gray-400 mt-1">Pack kamu sekarang punya {pack.length} stiker</p>
        </div>

        {/* Preview */}
        {stickerUrl && (
          <div className="w-full rounded-3xl p-5 flex flex-col items-center gap-4"
            style={{ background: 'white', boxShadow: '0 4px 24px rgba(0,0,0,0.07)' }}>
            <img src={stickerUrl} className="w-44 h-44 object-cover"
              style={{ borderRadius: borderRadius(shape) }} />
            {pack.length > 1 && (
              <div className="flex gap-2 flex-wrap justify-center">
                {pack.slice(-4).map(s => (
                  <img key={s.id} src={s.url} className="w-10 h-10 object-cover rounded-xl"
                    style={{ border: '2px solid #e2e8f0' }} />
                ))}
                {pack.length > 4 && (
                  <div className="w-10 h-10 rounded-xl flex items-center justify-center text-xs font-bold text-gray-400"
                    style={{ background: '#f1f5f9', border: '2px solid #e2e8f0' }}>
                    +{pack.length - 4}
                  </div>
                )}
              </div>
            )}
          </div>
        )}

        <div className="w-full flex flex-col gap-3">
          <button onClick={() => { resetEditor(); setScreen('upload'); }}
            className="w-full py-4 flex items-center justify-center gap-2.5 rounded-2xl font-black text-white text-base transition-all active:scale-95"
            style={{
              background: 'linear-gradient(135deg, #00c47c, #00a86b)',
              boxShadow: '0 6px 24px rgba(0,196,124,0.35)',
              fontFamily: "'Nunito', sans-serif",
            }}>
            <Plus size={20} />
            Tambah Stiker Lagi
          </button>

          <button onClick={handleExportPack}
            disabled={sharing}
            className="w-full py-3.5 flex items-center justify-center gap-2.5 rounded-2xl font-bold text-base transition-all active:scale-95"
            style={{
              background: sharing ? '#94a3b8' : 'linear-gradient(135deg, #25d366, #1ebe5b)',
              color: 'white',
              boxShadow: sharing ? 'none' : '0 4px 20px rgba(37,211,102,0.3)',
            }}>
            {sharing
              ? <div className="w-5 h-5 border-2 border-white border-t-transparent rounded-full animate-spin" />
              : <Share2 size={18} />}
            {sharing ? 'Menyiapkan...' : `📲 Kirim ke WhatsApp (${pack.length} stiker)`}
          </button>

          <button onClick={() => setScreen('pack')}
            className="w-full py-3 flex items-center justify-center gap-2 rounded-2xl font-bold text-sm transition-all active:scale-95"
            style={{ background: 'white', color: '#64748b', border: '1.5px solid #e2e8f0' }}>
            📦 Lihat Semua Pack
          </button>
        </div>
      </div>
    </div>
  );

  if (!isOpen) return null;

  return (
    <>
      {screen === 'pack'   && PackScreen}
      {screen === 'upload' && UploadScreen}
      {screen === 'edit'   && EditScreen}
      {screen === 'done'   && DoneScreen}

      <input ref={fileInputRef} type="file" accept="image/*" className="hidden" onChange={handleFileSelect} />

      {toastMsg && (
        <div className="fixed bottom-8 left-1/2 z-[110] px-5 py-3 rounded-2xl text-sm font-semibold text-white whitespace-nowrap"
          style={{
            transform: 'translateX(-50%)',
            background: 'rgba(15,23,42,0.92)',
            backdropFilter: 'blur(12px)',
            boxShadow: '0 4px 24px rgba(0,0,0,0.3)',
            animation: 'toastIn 0.3s ease forwards',
          }}>
          {toastMsg}
        </div>
      )}

      <style>{`
        @import url('https://fonts.googleapis.com/css2?family=Nunito:wght@400;700;800;900&display=swap');
        @keyframes toastIn {
          from { opacity:0; transform:translateX(-50%) translateY(16px); }
          to   { opacity:1; transform:translateX(-50%) translateY(0); }
        }
        input[type="range"]::-webkit-slider-thumb {
          appearance:none; width:16px; height:16px; border-radius:50%;
          background:#00c47c; cursor:pointer; box-shadow:0 2px 8px rgba(0,196,124,0.4);
        }
      `}</style>
    </>
  );
};

export default StickerMakerPanel;
