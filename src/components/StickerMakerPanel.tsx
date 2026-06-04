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

  const previewCanvasRef = useRef<HTMLCanvasElement>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const showToast = (msg: string) => {
    setToastMsg(msg);
    setTimeout(() => setToastMsg(null), 2500);
  };

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

  const handleExportPack = async () => {
    if (pack.length === 0) return;
    setSharing(true);
    try {
      const files: File[] = [];
      for (let i = 0; i < pack.length; i++) {
        const res = await fetch(pack[i].url);
        const blob = await res.blob();
        files.push(new File([blob], `stiker-${i + 1}.png`, { type: 'image/png' }));
      }
      if (navigator.share && navigator.canShare?.({ files })) {
        await navigator.share({ title: packName, files });
        showToast('✅ Pack berhasil dikirim!');
      } else {
        // fallback: download first sticker
        const a = document.createElement('a');
        a.href = pack[0].url; a.download = 'sticker-pack.png'; a.click();
        showToast('📲 Simpan lalu kirim ke WA manual ya!');
      }
    } catch (err: any) {
      if (err.name !== 'AbortError') showToast('Gagal: ' + err.message);
    } finally { setSharing(false); }
  };

  const handleShareSingle = async (url: string) => {
    try {
      const res = await fetch(url); const blob = await res.blob();
      const file = new File([blob], 'stiker.png', { type: 'image/png' });
      if (navigator.share && navigator.canShare?.({ files: [file] })) {
        await navigator.share({ title: 'Stiker', files: [file] });
      } else {
        const a = document.createElement('a'); a.href = url; a.download = 'stiker.png'; a.click();
        showToast('💾 Stiker disimpan!');
      }
    } catch {}
  };

  const borderRadius = (s: ShapeMode) => s === 'circle' ? '50%' : s === 'rounded' ? '28px' : '8px';

  const filters: { key: FilterMode; label: string; icon: React.ReactNode; color: string }[] = [
    { key: 'none', label: 'Original', icon: <Wand2 size={15} />, color: '#94a3b8' },
    { key: 'vivid', label: 'Vivid', icon: <Sun size={15} />, color: '#f59e0b' },
    { key: 'pop', label: 'Pop', icon: <Flame size={15} />, color: '#f43f5e' },
    { key: 'neon', label: 'Neon', icon: <Zap size={15} />, color: '#8b5cf6' },
  ];

  const totalSize = (pack.length * 25).toFixed(0);

  // ─────────────────────────────────────────────────────────────────
  //  PACK SCREEN
  // ─────────────────────────────────────────────────────────────────
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
              background: sharing ? '#94a3b8' : 'linear-gradient(135deg, #25d366, #1ebe5b)',
              boxShadow: sharing ? 'none' : '0 6px 24px rgba(37,211,102,0.35)',
              fontFamily: "'Nunito', sans-serif",
            }}>
            {sharing
              ? <div className="w-5 h-5 border-2 border-white border-t-transparent rounded-full animate-spin" />
              : <Share2 size={20} />}
            {sharing ? 'Mengekspor...' : `Export Sticker Pack (${pack.length})`}
          </button>
        )}
      </div>
    </div>
  );

  // ─────────────────────────────────────────────────────────────────
  //  UPLOAD SCREEN
  // ─────────────────────────────────────────────────────────────────
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

  // ─────────────────────────────────────────────────────────────────
  //  EDIT SCREEN
  // ─────────────────────────────────────────────────────────────────
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

  // ─────────────────────────────────────────────────────────────────
  //  DONE SCREEN  
  // ─────────────────────────────────────────────────────────────────
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
        {/* step indicator */}
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

        {/* Preview + pack mini */}
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
            {sharing ? 'Mengekspor...' : `Export Pack (${pack.length} stiker)`}
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
      {screen === 'pack' && PackScreen}
      {screen === 'upload' && UploadScreen}
      {screen === 'edit' && EditScreen}
      {screen === 'done' && DoneScreen}

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
