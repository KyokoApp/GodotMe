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
  Sticker,
} from 'lucide-react';

interface StickerMakerPanelProps {
  isOpen: boolean;
  onClose: () => void;
}

type ShapeMode = 'square' | 'circle' | 'rounded';
type FilterMode = 'none' | 'vivid' | 'pop' | 'neon';

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
      const r = size * 0.16;
      ctx.beginPath();
      ctx.moveTo(r, 0);
      ctx.lineTo(size - r, 0);
      ctx.arcTo(size, 0, size, r, r);
      ctx.lineTo(size, size - r);
      ctx.arcTo(size, size, size - r, size, r);
      ctx.lineTo(r, size);
      ctx.arcTo(0, size, 0, size - r, r);
      ctx.lineTo(0, r);
      ctx.arcTo(0, 0, r, 0, r);
      ctx.closePath();
      ctx.clip();
    }

    const aspect = image.width / image.height;
    let drawW, drawH;
    if (aspect >= 1) {
      drawH = size * zoom;
      drawW = drawH * aspect;
    } else {
      drawW = size * zoom;
      drawH = drawW / aspect;
    }

    const dx = (size - drawW) / 2 + offsetX;
    const dy = (size - drawH) / 2 + offsetY;

    if (filter === 'vivid') ctx.filter = 'saturate(1.8) contrast(1.1)';
    else if (filter === 'pop') ctx.filter = 'saturate(2) brightness(1.1) contrast(1.15)';
    else if (filter === 'neon') ctx.filter = 'saturate(3) brightness(1.2) hue-rotate(20deg) contrast(1.2)';
    else ctx.filter = 'none';

    ctx.drawImage(image, dx, dy, drawW, drawH);
    ctx.filter = 'none';
    ctx.restore();

    // White border stroke
    ctx.save();
    ctx.strokeStyle = 'rgba(255,255,255,0.9)';
    ctx.lineWidth = size * 0.022;
    const lw = ctx.lineWidth / 2;
    if (shape === 'circle') {
      ctx.beginPath();
      ctx.arc(size / 2, size / 2, size / 2 - lw, 0, Math.PI * 2);
      ctx.stroke();
    } else if (shape === 'rounded') {
      const r = size * 0.16 - lw;
      ctx.beginPath();
      ctx.moveTo(r + lw, lw);
      ctx.lineTo(size - r - lw, lw);
      ctx.arcTo(size - lw, lw, size - lw, r + lw, r);
      ctx.lineTo(size - lw, size - r - lw);
      ctx.arcTo(size - lw, size - lw, size - r - lw, size - lw, r);
      ctx.lineTo(r + lw, size - lw);
      ctx.arcTo(lw, size - lw, lw, size - r - lw, r);
      ctx.lineTo(lw, r + lw);
      ctx.arcTo(lw, lw, r + lw, lw, r);
      ctx.closePath();
      ctx.stroke();
    } else {
      ctx.strokeRect(lw, lw, size - lw * 2, size - lw * 2);
    }
    ctx.restore();
  }, [image, shape, filter, zoom, offsetX, offsetY]);

  useEffect(() => { drawPreview(); }, [drawPreview]);

  useEffect(() => {
    if (!isOpen) {
      setImage(null);
      setImageDataUrl(null);
      setStickerReady(false);
      setStickerUrl(null);
      setZoom(1);
      setOffsetX(0);
      setOffsetY(0);
      setFilter('none');
      setShape('rounded');
    }
  }, [isOpen]);

  const handleFileSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    const url = URL.createObjectURL(file);
    const img = new Image();
    img.onload = () => {
      setImage(img);
      setImageDataUrl(url);
      setZoom(1); setOffsetX(0); setOffsetY(0);
      setStickerReady(false); setStickerUrl(null);
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
    showToast('✅ Stiker siap!');
  };

  const handleDownload = () => {
    if (!stickerUrl) return;
    const a = document.createElement('a');
    a.href = stickerUrl;
    a.download = `kyokobeat-stiker-${Date.now()}.png`;
    a.click();
    showToast('💾 Stiker disimpan!');
  };

  const handleShareWA = async () => {
    if (!stickerUrl) return;
    setSharing(true);
    try {
      const res = await fetch(stickerUrl);
      const blob = await res.blob();
      const file = new File([blob], 'stiker.png', { type: 'image/png' });
      if (navigator.share && navigator.canShare?.({ files: [file] })) {
        await navigator.share({ title: 'Stiker KyokoBeat', files: [file] });
        showToast('✅ Berhasil dibagikan!');
      } else {
        handleDownload();
        showToast('📲 Simpan dulu, lalu kirim ke WA manual ya!');
      }
    } catch (err: any) {
      if (err.name !== 'AbortError') showToast('Gagal berbagi: ' + err.message);
    } finally {
      setSharing(false);
    }
  };

  const CANVAS_SIZE = 256;

  return (
    <>
      {/* Fullscreen panel */}
      <div
        className="fixed inset-0 z-[100] flex flex-col overflow-hidden"
        style={{
          background: '#5b21b6',
          transform: isOpen ? 'translateX(0)' : 'translateX(-100%)',
          transition: 'transform 0.38s cubic-bezier(0.4, 0, 0.2, 1)',
        }}
      >
        {/* Rich gradient overlay */}
        <div
          className="absolute inset-0 pointer-events-none"
          style={{
            background: 'radial-gradient(ellipse 80% 60% at 20% 10%, rgba(139,92,246,0.7) 0%, transparent 60%), radial-gradient(ellipse 60% 50% at 80% 80%, rgba(109,40,217,0.6) 0%, transparent 60%), linear-gradient(160deg, #4c1d95 0%, #5b21b6 40%, #6d28d9 100%)',
          }}
        />

        {/* Top geometric accent */}
        <div className="absolute top-0 right-8 w-0 h-0 pointer-events-none" style={{
          borderLeft: '60px solid transparent',
          borderRight: '0px solid transparent',
          borderTop: '60px solid rgba(200,245,0,0.08)',
        }} />
        <div className="absolute top-0 right-0 w-0 h-0 pointer-events-none" style={{
          borderLeft: '90px solid transparent',
          borderRight: '0px solid transparent',
          borderTop: '90px solid rgba(200,245,0,0.05)',
        }} />

        {/* Bottom geometric accent */}
        <div className="absolute bottom-0 left-0 w-0 h-0 pointer-events-none" style={{
          borderRight: '70px solid transparent',
          borderLeft: '0px solid transparent',
          borderBottom: '70px solid rgba(200,245,0,0.06)',
        }} />

        {/* ── CLOSE TAB: smooth SVG arrow on RIGHT edge ── */}
        <button
          onClick={onClose}
          aria-label="Tutup panel stiker"
          className="absolute right-0 top-1/2 z-10 p-0 border-0 bg-transparent transition-transform active:scale-90"
          style={{
            transform: 'translateY(-50%)',
            cursor: 'pointer',
            filter: 'drop-shadow(-2px 0 8px rgba(200,245,0,0.5))',
          }}
        >
          <svg width="22" height="60" viewBox="0 0 22 60" fill="none" xmlns="http://www.w3.org/2000/svg">
            <path d="M0,0 L22,30 L0,60 Z" fill="#c8f500"/>
          </svg>
        </button>

        {/* Header */}
        <div className="relative z-10 flex items-center gap-3 px-5 pt-12 pb-5">
          <div
            className="p-2.5 rounded-xl flex-shrink-0"
            style={{
              background: 'rgba(200,245,0,0.15)',
              border: '1.5px solid rgba(200,245,0,0.35)',
              boxShadow: '0 0 16px rgba(200,245,0,0.15)',
            }}
          >
            <Sticker className="w-5 h-5" style={{ color: '#c8f500' }} />
          </div>
          <div>
            <h1
              className="font-black text-white tracking-[0.12em] uppercase"
              style={{ fontSize: 20, letterSpacing: '0.12em', textShadow: '0 0 20px rgba(200,245,0,0.2)' }}
            >
              STIKER MAKER
            </h1>
            <p className="text-xs mt-0.5" style={{ color: 'rgba(255,255,255,0.5)' }}>
              Upload foto → edit → kirim ke WA
            </p>
          </div>
        </div>

        {/* Divider */}
        <div className="relative z-10 mx-5 mb-4 h-px" style={{ background: 'linear-gradient(90deg, rgba(200,245,0,0.3), rgba(200,245,0,0.05))' }} />

        {/* Scrollable content */}
        <div className="relative z-10 flex-1 overflow-y-auto px-5 pb-10 flex flex-col gap-5">

          {/* Upload area */}
          {!imageDataUrl ? (
            <button
              onClick={() => fileInputRef.current?.click()}
              className="flex flex-col items-center justify-center gap-4 rounded-2xl border-2 border-dashed py-12 transition-all active:scale-[0.98]"
              style={{
                borderColor: 'rgba(200,245,0,0.35)',
                background: 'rgba(0,0,0,0.18)',
                boxShadow: 'inset 0 0 30px rgba(0,0,0,0.15)',
              }}
            >
              <div
                className="p-4 rounded-2xl"
                style={{
                  background: 'rgba(200,245,0,0.12)',
                  border: '1.5px solid rgba(200,245,0,0.25)',
                  boxShadow: '0 0 20px rgba(200,245,0,0.1)',
                }}
              >
                <ImagePlus className="w-8 h-8" style={{ color: '#c8f500' }} />
              </div>
              <div className="text-center">
                <p
                  className="font-black uppercase tracking-[0.15em] text-white"
                  style={{ fontSize: 14, textShadow: '0 0 10px rgba(200,245,0,0.3)' }}
                >
                  PILIH FOTO
                </p>
                <p className="text-xs mt-1" style={{ color: 'rgba(255,255,255,0.4)' }}>
                  dari galeri atau kamera
                </p>
              </div>
            </button>
          ) : (
            <>
              {/* Canvas preview */}
              <div className="flex flex-col items-center gap-2">
                <div
                  className="rounded-2xl p-1"
                  style={{
                    background: 'rgba(0,0,0,0.25)',
                    boxShadow: '0 0 40px rgba(109,40,217,0.4), 0 0 80px rgba(200,245,0,0.08), inset 0 1px 0 rgba(255,255,255,0.1)',
                  }}
                >
                  <canvas
                    ref={previewCanvasRef}
                    width={CANVAS_SIZE}
                    height={CANVAS_SIZE}
                    className="rounded-xl block select-none"
                    style={{
                      background: 'repeating-conic-gradient(rgba(255,255,255,0.06) 0% 25%, transparent 0% 50%) 0 0 / 14px 14px',
                      cursor: isDragging ? 'grabbing' : 'grab',
                      touchAction: 'none',
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
                <p className="text-[11px]" style={{ color: 'rgba(255,255,255,0.35)' }}>
                  ✋ Geser untuk atur posisi
                </p>
              </div>

              {/* Zoom */}
              <div
                className="flex items-center gap-3 px-3 py-2.5 rounded-xl"
                style={{ background: 'rgba(0,0,0,0.2)', border: '1px solid rgba(255,255,255,0.08)' }}
              >
                <button
                  onClick={() => setZoom(z => Math.max(0.5, parseFloat((z - 0.1).toFixed(2))))}
                  className="p-1.5 rounded-lg transition-all active:scale-90"
                  style={{ background: 'rgba(255,255,255,0.08)' }}
                >
                  <ZoomOut className="w-4 h-4 text-white" />
                </button>
                <div className="flex-1 relative h-1.5 rounded-full" style={{ background: 'rgba(255,255,255,0.12)' }}>
                  <div
                    className="absolute inset-y-0 left-0 rounded-full"
                    style={{ width: `${((zoom - 0.5) / 2.5) * 100}%`, background: 'linear-gradient(90deg, #a855f7, #c8f500)' }}
                  />
                  <input
                    type="range" min={0.5} max={3} step={0.05} value={zoom}
                    onChange={e => { setZoom(parseFloat(e.target.value)); setStickerReady(false); }}
                    className="absolute inset-0 w-full opacity-0 cursor-pointer h-full"
                  />
                </div>
                <button
                  onClick={() => setZoom(z => Math.min(3, parseFloat((z + 0.1).toFixed(2))))}
                  className="p-1.5 rounded-lg transition-all active:scale-90"
                  style={{ background: 'rgba(255,255,255,0.08)' }}
                >
                  <ZoomIn className="w-4 h-4 text-white" />
                </button>
                <button
                  onClick={() => { setZoom(1); setOffsetX(0); setOffsetY(0); setStickerReady(false); }}
                  className="p-1.5 rounded-lg transition-all active:scale-90"
                  style={{ background: 'rgba(255,255,255,0.08)' }}
                >
                  <RotateCcw className="w-3.5 h-3.5 text-white" />
                </button>
              </div>

              {/* Shape */}
              <div>
                <p className="text-[11px] font-bold uppercase tracking-[0.15em] mb-2" style={{ color: 'rgba(255,255,255,0.45)' }}>
                  Bentuk
                </p>
                <div className="flex gap-2">
                  {(['square', 'rounded', 'circle'] as ShapeMode[]).map(s => (
                    <button
                      key={s}
                      onClick={() => { setShape(s); setStickerReady(false); }}
                      className="flex-1 py-2.5 text-xs font-bold uppercase tracking-wider transition-all active:scale-95"
                      style={{
                        borderRadius: s === 'circle' ? '9999px' : s === 'rounded' ? '14px' : '6px',
                        background: shape === s
                          ? 'linear-gradient(135deg, #c8f500, #a3e000)'
                          : 'rgba(0,0,0,0.25)',
                        color: shape === s ? '#1a0a4a' : 'rgba(255,255,255,0.6)',
                        border: shape === s ? '1.5px solid #c8f500' : '1.5px solid rgba(255,255,255,0.1)',
                        boxShadow: shape === s ? '0 0 12px rgba(200,245,0,0.3)' : 'none',
                      }}
                    >
                      {s === 'square' ? 'Kotak' : s === 'rounded' ? 'Sudut' : 'Bulat'}
                    </button>
                  ))}
                </div>
              </div>

              {/* Filter */}
              <div>
                <p className="text-[11px] font-bold uppercase tracking-[0.15em] mb-2" style={{ color: 'rgba(255,255,255,0.45)' }}>
                  Filter
                </p>
                <div className="flex gap-2 overflow-x-auto pb-1">
                  {(['none', 'vivid', 'pop', 'neon'] as FilterMode[]).map(f => (
                    <button
                      key={f}
                      onClick={() => { setFilter(f); setStickerReady(false); }}
                      className="flex-shrink-0 px-4 py-2 text-xs font-bold uppercase tracking-wider rounded-full transition-all active:scale-95"
                      style={{
                        background: filter === f
                          ? 'linear-gradient(135deg, #c8f500, #a3e000)'
                          : 'rgba(0,0,0,0.25)',
                        color: filter === f ? '#1a0a4a' : 'rgba(255,255,255,0.6)',
                        border: filter === f ? '1.5px solid #c8f500' : '1.5px solid rgba(255,255,255,0.1)',
                        boxShadow: filter === f ? '0 0 12px rgba(200,245,0,0.3)' : 'none',
                      }}
                    >
                      {f === 'none' ? 'Original' : f === 'vivid' ? 'Vivid' : f === 'pop' ? 'Pop' : '⚡ Neon'}
                    </button>
                  ))}
                </div>
              </div>

              {/* Actions */}
              <div className="flex flex-col gap-3 mt-1">
                <button
                  onClick={generateSticker}
                  className="w-full py-3.5 flex items-center justify-center gap-2 rounded-2xl font-black uppercase tracking-[0.12em] text-sm transition-all active:scale-95"
                  style={{
                    background: 'linear-gradient(135deg, #c8f500, #a3e000)',
                    color: '#1a0a4a',
                    boxShadow: '0 4px 20px rgba(200,245,0,0.35), 0 0 0 1px rgba(200,245,0,0.2)',
                  }}
                >
                  <Sparkles className="w-4 h-4" />
                  Buat Stiker
                </button>

                {stickerReady && (
                  <>
                    <button
                      onClick={handleDownload}
                      className="w-full py-3 flex items-center justify-center gap-2 rounded-2xl font-bold uppercase tracking-wider text-sm transition-all active:scale-95"
                      style={{
                        background: 'rgba(200,245,0,0.1)',
                        color: '#c8f500',
                        border: '1.5px solid rgba(200,245,0,0.35)',
                        boxShadow: 'inset 0 1px 0 rgba(200,245,0,0.1)',
                      }}
                    >
                      <Download className="w-4 h-4" />
                      Simpan ke Galeri
                    </button>

                    <button
                      onClick={handleShareWA}
                      disabled={sharing}
                      className="w-full py-3 flex items-center justify-center gap-2 rounded-2xl font-bold uppercase tracking-wider text-sm transition-all active:scale-95"
                      style={{
                        background: 'rgba(37,211,102,0.12)',
                        color: '#25d366',
                        border: '1.5px solid rgba(37,211,102,0.35)',
                        opacity: sharing ? 0.7 : 1,
                      }}
                    >
                      {sharing
                        ? <div className="w-4 h-4 border-2 border-[#25d366] border-t-transparent rounded-full animate-spin" />
                        : <Share2 className="w-4 h-4" />}
                      {sharing ? 'Membagikan...' : 'Kirim ke WhatsApp'}
                    </button>
                  </>
                )}

                <button
                  onClick={() => fileInputRef.current?.click()}
                  className="w-full py-2.5 flex items-center justify-center gap-2 rounded-xl text-sm transition-all active:scale-95"
                  style={{
                    background: 'rgba(0,0,0,0.2)',
                    color: 'rgba(255,255,255,0.45)',
                    border: '1px solid rgba(255,255,255,0.08)',
                  }}
                >
                  <Upload className="w-4 h-4" />
                  Ganti Foto
                </button>
              </div>
            </>
          )}
        </div>

        {/* Hidden file input */}
        <input ref={fileInputRef} type="file" accept="image/*" className="hidden" onChange={handleFileSelect} />

        {/* Toast */}
        {toastMsg && (
          <div
            className="fixed bottom-8 left-1/2 -translate-x-1/2 z-[110] px-5 py-3 rounded-2xl text-sm font-semibold text-white whitespace-nowrap"
            style={{
              background: 'rgba(30,10,70,0.92)',
              border: '1.5px solid rgba(200,245,0,0.3)',
              backdropFilter: 'blur(12px)',
              boxShadow: '0 4px 24px rgba(0,0,0,0.4)',
              animation: 'sbFadeUp 0.3s ease forwards',
            }}
          >
            {toastMsg}
          </div>
        )}
      </div>

      <style>{`
        @keyframes sbFadeUp {
          from { opacity: 0; transform: translateX(-50%) translateY(12px); }
          to   { opacity: 1; transform: translateX(-50%) translateY(0); }
        }
      `}</style>
    </>
  );
};

export default StickerMakerPanel;
