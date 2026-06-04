import React, { useState, useRef, useCallback, useEffect } from 'react';
import {
  Upload,
  Download,
  Share2,
  RotateCcw,
  ZoomIn,
  ZoomOut,
  Sparkles,
  ImagePlus,
  X,
  ChevronLeft,
  Check,
  Wand2,
  Sun,
  Zap,
  Flame,
} from 'lucide-react';

interface StickerMakerPanelProps {
  isOpen: boolean;
  onClose: () => void;
}

type ShapeMode = 'square' | 'circle' | 'rounded';
type FilterMode = 'none' | 'vivid' | 'pop' | 'neon';

const CANVAS_SIZE = 280;

const StickerMakerPanel: React.FC<StickerMakerPanelProps> = ({ isOpen, onClose }) => {
  const [image, setImage] = useState<HTMLImageElement | null>(null);
  const [imageDataUrl, setImageDataUrl] = useState<string | null>(null);
  const [shape, setShape] = useState<ShapeMode>('rounded');
  const [filter, setFilter] = useState<FilterMode>('none');
  const [zoom, setZoom] = useState(1);
  const [offsetX, setOffsetX] = useState(0);
  const [offsetY, setOffsetY] = useState(0);
  const [isDragging, setIsDragging] = useState(false);
  const [dragStart, setDragStart] = useState({ x: 0, y: 0 });
  const [stickerReady, setStickerReady] = useState(false);
  const [stickerUrl, setStickerUrl] = useState<string | null>(null);
  const [sharing, setSharing] = useState(false);
  const [toastMsg, setToastMsg] = useState<string | null>(null);
  const [activeStep, setActiveStep] = useState<'upload' | 'edit' | 'done'>('upload');

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
      ctx.beginPath();
      ctx.arc(size / 2, size / 2, size / 2, 0, Math.PI * 2);
      ctx.clip();
    } else if (shape === 'rounded') {
      const r = size * 0.18;
      ctx.beginPath();
      ctx.moveTo(r, 0); ctx.lineTo(size - r, 0);
      ctx.arcTo(size, 0, size, r, r); ctx.lineTo(size, size - r);
      ctx.arcTo(size, size, size - r, size, r); ctx.lineTo(r, size);
      ctx.arcTo(0, size, 0, size - r, r); ctx.lineTo(0, r);
      ctx.arcTo(0, 0, r, 0, r); ctx.closePath(); ctx.clip();
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
    ctx.filter = 'none';
    ctx.restore();

    // White border
    ctx.save();
    ctx.strokeStyle = 'rgba(255,255,255,0.92)';
    ctx.lineWidth = size * 0.024;
    const lw = ctx.lineWidth / 2;
    if (shape === 'circle') {
      ctx.beginPath();
      ctx.arc(size / 2, size / 2, size / 2 - lw, 0, Math.PI * 2);
      ctx.stroke();
    } else if (shape === 'rounded') {
      const r = size * 0.18 - lw;
      ctx.beginPath();
      ctx.moveTo(r + lw, lw); ctx.lineTo(size - r - lw, lw);
      ctx.arcTo(size - lw, lw, size - lw, r + lw, r); ctx.lineTo(size - lw, size - r - lw);
      ctx.arcTo(size - lw, size - lw, size - r - lw, size - lw, r); ctx.lineTo(r + lw, size - lw);
      ctx.arcTo(lw, size - lw, lw, size - r - lw, r); ctx.lineTo(lw, r + lw);
      ctx.arcTo(lw, lw, r + lw, lw, r); ctx.closePath(); ctx.stroke();
    } else {
      ctx.strokeRect(lw, lw, size - lw * 2, size - lw * 2);
    }
    ctx.restore();
  }, [image, shape, filter, zoom, offsetX, offsetY]);

  useEffect(() => { drawPreview(); }, [drawPreview]);

  useEffect(() => {
    if (!isOpen) {
      setImage(null); setImageDataUrl(null);
      setStickerReady(false); setStickerUrl(null);
      setZoom(1); setOffsetX(0); setOffsetY(0);
      setFilter('none'); setShape('rounded');
      setActiveStep('upload');
    }
  }, [isOpen]);

  const handleFileSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    const url = URL.createObjectURL(file);
    const img = new Image();
    img.onload = () => {
      setImage(img); setImageDataUrl(url);
      setZoom(1); setOffsetX(0); setOffsetY(0);
      setStickerReady(false); setStickerUrl(null);
      setActiveStep('edit');
    };
    img.src = url;
    e.target.value = '';
  };

  const handleMouseDown = (e: React.MouseEvent | React.TouchEvent) => {
    if (!image) return;
    setIsDragging(true);
    const pos = 'touches' in e ? e.touches[0] : e;
    setDragStart({ x: pos.clientX - offsetX, y: pos.clientY - offsetY });
  };
  const handleMouseMove = (e: React.MouseEvent | React.TouchEvent) => {
    if (!isDragging) return;
    const pos = 'touches' in e ? e.touches[0] : e;
    setOffsetX(pos.clientX - dragStart.x);
    setOffsetY(pos.clientY - dragStart.y);
  };
  const handleMouseUp = () => setIsDragging(false);

  const generateSticker = () => {
    const canvas = previewCanvasRef.current;
    if (!canvas) return;
    setStickerUrl(canvas.toDataURL('image/png'));
    setStickerReady(true);
    setActiveStep('done');
    showToast('✨ Stiker siap digunakan!');
  };

  const handleDownload = () => {
    if (!stickerUrl) return;
    const a = document.createElement('a');
    a.href = stickerUrl; a.download = `stiker-${Date.now()}.png`; a.click();
    showToast('💾 Tersimpan ke galeri!');
  };

  const handleShareWA = async () => {
    if (!stickerUrl) return;
    setSharing(true);
    try {
      const res = await fetch(stickerUrl);
      const blob = await res.blob();
      const file = new File([blob], 'stiker.png', { type: 'image/png' });
      if (navigator.share && navigator.canShare?.({ files: [file] })) {
        await navigator.share({ title: 'StickerVibe', files: [file] });
        showToast('✅ Berhasil dibagikan!');
      } else {
        handleDownload();
        showToast('📲 Simpan lalu kirim manual ya!');
      }
    } catch (err: any) {
      if (err.name !== 'AbortError') showToast('Gagal: ' + err.message);
    } finally { setSharing(false); }
  };

  const shapes: { key: ShapeMode; label: string; preview: string }[] = [
    { key: 'square', label: 'Kotak', preview: '⬛' },
    { key: 'rounded', label: 'Sudut', preview: '⬜' },
    { key: 'circle', label: 'Bulat', preview: '⚫' },
  ];

  const filters: { key: FilterMode; label: string; icon: React.ReactNode; color: string }[] = [
    { key: 'none', label: 'Original', icon: <Wand2 size={16} />, color: '#94a3b8' },
    { key: 'vivid', label: 'Vivid', icon: <Sun size={16} />, color: '#f59e0b' },
    { key: 'pop', label: 'Pop', icon: <Flame size={16} />, color: '#f43f5e' },
    { key: 'neon', label: 'Neon', icon: <Zap size={16} />, color: '#8b5cf6' },
  ];

  const steps = ['Upload', 'Edit', 'Selesai'];
  const stepIndex = activeStep === 'upload' ? 0 : activeStep === 'edit' ? 1 : 2;

  return (
    <>
      <div
        className="fixed inset-0 z-[100] flex flex-col"
        style={{
          background: '#f8fafc',
          transform: isOpen ? 'translateY(0)' : 'translateY(100%)',
          transition: 'transform 0.42s cubic-bezier(0.32, 0.72, 0, 1)',
        }}
      >

        {/* ── HEADER ── */}
        <div
          className="flex-shrink-0 px-4 pt-12 pb-4"
          style={{
            background: 'linear-gradient(135deg, #00c47c 0%, #00a86b 100%)',
          }}
        >
          {/* Back + Title */}
          <div className="flex items-center justify-between mb-5">
            <button
              onClick={onClose}
              className="w-9 h-9 flex items-center justify-center rounded-full transition-all active:scale-90"
              style={{ background: 'rgba(255,255,255,0.2)' }}
            >
              <ChevronLeft size={20} color="white" />
            </button>
            <h1
              className="font-black text-white tracking-tight"
              style={{ fontSize: 18, fontFamily: "'Nunito', sans-serif" }}
            >
              Buat Stiker
            </h1>
            {activeStep === 'edit' ? (
              <button
                onClick={generateSticker}
                className="px-4 py-1.5 rounded-full font-bold text-sm transition-all active:scale-95"
                style={{
                  background: 'white',
                  color: '#00c47c',
                  boxShadow: '0 2px 12px rgba(0,0,0,0.15)',
                }}
              >
                Buat ✨
              </button>
            ) : (
              <div className="w-9" />
            )}
          </div>

          {/* Step indicator */}
          <div className="flex items-center gap-0">
            {steps.map((step, i) => (
              <React.Fragment key={step}>
                <div className="flex flex-col items-center gap-1">
                  <div
                    className="w-7 h-7 rounded-full flex items-center justify-center text-xs font-black transition-all"
                    style={{
                      background: i <= stepIndex ? 'white' : 'rgba(255,255,255,0.3)',
                      color: i <= stepIndex ? '#00c47c' : 'rgba(255,255,255,0.6)',
                    }}
                  >
                    {i < stepIndex ? <Check size={12} /> : i + 1}
                  </div>
                  <span
                    className="text-[10px] font-bold"
                    style={{ color: i <= stepIndex ? 'white' : 'rgba(255,255,255,0.5)' }}
                  >
                    {step}
                  </span>
                </div>
                {i < steps.length - 1 && (
                  <div
                    className="flex-1 h-0.5 mb-4 mx-1 transition-all"
                    style={{ background: i < stepIndex ? 'white' : 'rgba(255,255,255,0.3)' }}
                  />
                )}
              </React.Fragment>
            ))}
          </div>
        </div>

        {/* ── SCROLLABLE BODY ── */}
        <div className="flex-1 overflow-y-auto" style={{ background: '#f1f5f9' }}>

          {/* ── UPLOAD STATE ── */}
          {!imageDataUrl && (
            <div className="flex flex-col items-center justify-center h-full px-6 py-10 gap-6">
              {/* Illustration area */}
              <div
                className="w-full rounded-3xl flex flex-col items-center justify-center py-14 gap-4 transition-all active:scale-[0.98]"
                style={{
                  background: 'white',
                  border: '2.5px dashed #00c47c',
                  boxShadow: '0 4px 24px rgba(0,196,124,0.08)',
                }}
                onClick={() => fileInputRef.current?.click()}
              >
                <div
                  className="w-20 h-20 rounded-3xl flex items-center justify-center"
                  style={{
                    background: 'linear-gradient(135deg, #e8fdf4, #d0fae8)',
                    border: '2px solid rgba(0,196,124,0.2)',
                  }}
                >
                  <ImagePlus size={36} color="#00c47c" />
                </div>
                <div className="text-center">
                  <p className="font-black text-gray-800 text-lg" style={{ fontFamily: "'Nunito', sans-serif" }}>
                    Pilih Foto
                  </p>
                  <p className="text-sm text-gray-400 mt-1">dari galeri atau kamera kamu</p>
                </div>
                <div
                  className="px-6 py-2.5 rounded-full font-bold text-sm text-white"
                  style={{ background: 'linear-gradient(135deg, #00c47c, #00a86b)' }}
                >
                  📷 Buka Galeri
                </div>
              </div>

              <p className="text-xs text-gray-400 text-center">
                Mendukung JPG, PNG, WEBP • Ukuran maks 10MB
              </p>
            </div>
          )}

          {/* ── EDIT STATE ── */}
          {imageDataUrl && activeStep !== 'done' && (
            <div className="flex flex-col gap-0">

              {/* Canvas area */}
              <div
                className="flex flex-col items-center py-6 gap-3"
                style={{ background: 'white' }}
              >
                {/* Canvas wrapper with shadow */}
                <div
                  className="relative"
                  style={{
                    filter: 'drop-shadow(0 8px 32px rgba(0,0,0,0.18)) drop-shadow(0 2px 8px rgba(0,0,0,0.1))',
                  }}
                >
                  <canvas
                    ref={previewCanvasRef}
                    width={CANVAS_SIZE}
                    height={CANVAS_SIZE}
                    className="block select-none"
                    style={{
                      borderRadius: shape === 'circle' ? '50%' : shape === 'rounded' ? '48px' : '12px',
                      background: 'repeating-conic-gradient(#e2e8f0 0% 25%, white 0% 50%) 0 0 / 16px 16px',
                      cursor: isDragging ? 'grabbing' : 'grab',
                      touchAction: 'none',
                      transition: 'border-radius 0.3s ease',
                    }}
                    onMouseDown={handleMouseDown}
                    onMouseMove={handleMouseMove}
                    onMouseUp={handleMouseUp}
                    onMouseLeave={handleMouseUp}
                    onTouchStart={handleMouseDown}
                    onTouchMove={handleMouseMove}
                    onTouchEnd={handleMouseUp}
                  />
                </div>
                <p className="text-xs text-gray-400">✋ Geser untuk atur posisi gambar</p>
              </div>

              {/* Controls */}
              <div className="px-4 py-5 flex flex-col gap-5" style={{ background: '#f1f5f9' }}>

                {/* Zoom bar */}
                <div
                  className="rounded-2xl p-4 flex flex-col gap-3"
                  style={{ background: 'white', boxShadow: '0 2px 12px rgba(0,0,0,0.05)' }}
                >
                  <div className="flex items-center justify-between">
                    <span className="text-xs font-black text-gray-500 uppercase tracking-widest">Zoom</span>
                    <span className="text-xs font-bold text-green-500">{Math.round(zoom * 100)}%</span>
                  </div>
                  <div className="flex items-center gap-3">
                    <button
                      onClick={() => setZoom(z => Math.max(0.5, parseFloat((z - 0.1).toFixed(2))))}
                      className="w-8 h-8 rounded-xl flex items-center justify-center transition-all active:scale-90"
                      style={{ background: '#f1f5f9' }}
                    >
                      <ZoomOut size={15} color="#64748b" />
                    </button>
                    <div className="flex-1 relative h-2 rounded-full" style={{ background: '#e2e8f0' }}>
                      <div
                        className="absolute inset-y-0 left-0 rounded-full transition-all"
                        style={{
                          width: `${((zoom - 0.5) / 2.5) * 100}%`,
                          background: 'linear-gradient(90deg, #00c47c, #00e58c)',
                        }}
                      />
                      <input
                        type="range" min={0.5} max={3} step={0.05} value={zoom}
                        onChange={e => { setZoom(parseFloat(e.target.value)); setStickerReady(false); }}
                        className="absolute inset-0 w-full opacity-0 cursor-pointer h-full"
                      />
                    </div>
                    <button
                      onClick={() => setZoom(z => Math.min(3, parseFloat((z + 0.1).toFixed(2))))}
                      className="w-8 h-8 rounded-xl flex items-center justify-center transition-all active:scale-90"
                      style={{ background: '#f1f5f9' }}
                    >
                      <ZoomIn size={15} color="#64748b" />
                    </button>
                    <button
                      onClick={() => { setZoom(1); setOffsetX(0); setOffsetY(0); setStickerReady(false); }}
                      className="w-8 h-8 rounded-xl flex items-center justify-center transition-all active:scale-90"
                      style={{ background: '#f1f5f9' }}
                    >
                      <RotateCcw size={13} color="#64748b" />
                    </button>
                  </div>
                </div>

                {/* Shape selector */}
                <div
                  className="rounded-2xl p-4 flex flex-col gap-3"
                  style={{ background: 'white', boxShadow: '0 2px 12px rgba(0,0,0,0.05)' }}
                >
                  <span className="text-xs font-black text-gray-500 uppercase tracking-widest">Bentuk</span>
                  <div className="flex gap-3">
                    {shapes.map(s => (
                      <button
                        key={s.key}
                        onClick={() => { setShape(s.key); setStickerReady(false); }}
                        className="flex-1 py-3 flex flex-col items-center gap-1.5 transition-all active:scale-95"
                        style={{
                          borderRadius: '16px',
                          background: shape === s.key ? 'linear-gradient(135deg, #00c47c, #00a86b)' : '#f8fafc',
                          border: shape === s.key ? 'none' : '1.5px solid #e2e8f0',
                          boxShadow: shape === s.key ? '0 4px 16px rgba(0,196,124,0.3)' : 'none',
                        }}
                      >
                        <div
                          className="w-7 h-7 transition-all"
                          style={{
                            background: shape === s.key ? 'rgba(255,255,255,0.3)' : '#e2e8f0',
                            borderRadius: s.key === 'circle' ? '50%' : s.key === 'rounded' ? '8px' : '4px',
                          }}
                        />
                        <span
                          className="text-xs font-bold"
                          style={{ color: shape === s.key ? 'white' : '#64748b' }}
                        >
                          {s.label}
                        </span>
                      </button>
                    ))}
                  </div>
                </div>

                {/* Filter selector */}
                <div
                  className="rounded-2xl p-4 flex flex-col gap-3"
                  style={{ background: 'white', boxShadow: '0 2px 12px rgba(0,0,0,0.05)' }}
                >
                  <span className="text-xs font-black text-gray-500 uppercase tracking-widest">Filter</span>
                  <div className="grid grid-cols-4 gap-2">
                    {filters.map(f => (
                      <button
                        key={f.key}
                        onClick={() => { setFilter(f.key); setStickerReady(false); }}
                        className="flex flex-col items-center gap-1.5 py-3 rounded-2xl transition-all active:scale-95"
                        style={{
                          background: filter === f.key ? f.color : '#f8fafc',
                          border: filter === f.key ? 'none' : '1.5px solid #e2e8f0',
                          boxShadow: filter === f.key ? `0 4px 16px ${f.color}55` : 'none',
                        }}
                      >
                        <span style={{ color: filter === f.key ? 'white' : f.color }}>
                          {f.icon}
                        </span>
                        <span
                          className="text-[10px] font-bold"
                          style={{ color: filter === f.key ? 'white' : '#64748b' }}
                        >
                          {f.label}
                        </span>
                      </button>
                    ))}
                  </div>
                </div>

                {/* Change photo */}
                <button
                  onClick={() => fileInputRef.current?.click()}
                  className="w-full py-3 flex items-center justify-center gap-2 rounded-2xl text-sm font-bold transition-all active:scale-95"
                  style={{
                    background: 'white',
                    color: '#64748b',
                    border: '1.5px solid #e2e8f0',
                  }}
                >
                  <Upload size={15} />
                  Ganti Foto
                </button>

                {/* Generate sticker CTA */}
                <button
                  onClick={generateSticker}
                  className="w-full py-4 flex items-center justify-center gap-2 rounded-2xl font-black text-white text-base transition-all active:scale-95"
                  style={{
                    background: 'linear-gradient(135deg, #00c47c 0%, #00a86b 100%)',
                    boxShadow: '0 6px 24px rgba(0,196,124,0.4), 0 2px 8px rgba(0,196,124,0.2)',
                    letterSpacing: '0.02em',
                    fontFamily: "'Nunito', sans-serif",
                  }}
                >
                  <Sparkles size={18} />
                  Buat Stiker
                </button>
              </div>
            </div>
          )}

          {/* ── DONE STATE ── */}
          {activeStep === 'done' && stickerUrl && (
            <div className="flex flex-col items-center px-6 py-8 gap-6">

              {/* Success badge */}
              <div
                className="w-16 h-16 rounded-full flex items-center justify-center"
                style={{
                  background: 'linear-gradient(135deg, #00c47c, #00e58c)',
                  boxShadow: '0 6px 24px rgba(0,196,124,0.4)',
                }}
              >
                <Check size={28} color="white" strokeWidth={3} />
              </div>

              <div className="text-center">
                <h2 className="font-black text-gray-800 text-xl" style={{ fontFamily: "'Nunito', sans-serif" }}>
                  Stiker Siap! 🎉
                </h2>
                <p className="text-sm text-gray-400 mt-1">
                  Simpan atau bagikan stiker kamu
                </p>
              </div>

              {/* Sticker preview */}
              <div
                className="p-3 rounded-3xl"
                style={{
                  background: 'white',
                  boxShadow: '0 8px 32px rgba(0,0,0,0.12)',
                }}
              >
                <img
                  src={stickerUrl}
                  alt="Stiker"
                  className="w-48 h-48 object-cover"
                  style={{
                    borderRadius: shape === 'circle' ? '50%' : shape === 'rounded' ? '36px' : '8px',
                  }}
                />
              </div>

              {/* Actions */}
              <div className="w-full flex flex-col gap-3">
                <button
                  onClick={handleShareWA}
                  disabled={sharing}
                  className="w-full py-4 flex items-center justify-center gap-2.5 rounded-2xl font-black text-white text-base transition-all active:scale-95"
                  style={{
                    background: sharing ? '#94a3b8' : 'linear-gradient(135deg, #25d366, #1ebe5b)',
                    boxShadow: sharing ? 'none' : '0 6px 24px rgba(37,211,102,0.4)',
                    fontFamily: "'Nunito', sans-serif",
                  }}
                >
                  {sharing
                    ? <div className="w-5 h-5 border-2 border-white border-t-transparent rounded-full animate-spin" />
                    : <Share2 size={18} />}
                  {sharing ? 'Membagikan...' : 'Kirim ke WhatsApp'}
                </button>

                <button
                  onClick={handleDownload}
                  className="w-full py-3.5 flex items-center justify-center gap-2.5 rounded-2xl font-bold text-sm transition-all active:scale-95"
                  style={{
                    background: 'white',
                    color: '#00c47c',
                    border: '2px solid #00c47c',
                    boxShadow: '0 2px 12px rgba(0,196,124,0.12)',
                  }}
                >
                  <Download size={16} />
                  Simpan ke Galeri
                </button>

                <button
                  onClick={() => { setStickerReady(false); setActiveStep('edit'); }}
                  className="w-full py-3 flex items-center justify-center gap-2 rounded-2xl font-bold text-sm transition-all active:scale-95"
                  style={{ background: '#f1f5f9', color: '#64748b' }}
                >
                  ✏️ Edit Lagi
                </button>
              </div>
            </div>
          )}
        </div>
      </div>

      {/* Hidden file input */}
      <input ref={fileInputRef} type="file" accept="image/*" className="hidden" onChange={handleFileSelect} />

      {/* Toast */}
      {toastMsg && (
        <div
          className="fixed bottom-8 left-1/2 z-[110] px-5 py-3 rounded-2xl text-sm font-semibold text-white whitespace-nowrap"
          style={{
            transform: 'translateX(-50%)',
            background: 'rgba(15,23,42,0.92)',
            backdropFilter: 'blur(12px)',
            boxShadow: '0 4px 24px rgba(0,0,0,0.3)',
            animation: 'toastIn 0.3s ease forwards',
          }}
        >
          {toastMsg}
        </div>
      )}

      <style>{`
        @import url('https://fonts.googleapis.com/css2?family=Nunito:wght@400;700;800;900&display=swap');
        @keyframes toastIn {
          from { opacity: 0; transform: translateX(-50%) translateY(16px); }
          to   { opacity: 1; transform: translateX(-50%) translateY(0); }
        }
        input[type="range"]::-webkit-slider-thumb { appearance: none; width: 16px; height: 16px; border-radius: 50%; background: #00c47c; cursor: pointer; box-shadow: 0 2px 8px rgba(0,196,124,0.4); }
      `}</style>
    </>
  );
};

export default StickerMakerPanel;
