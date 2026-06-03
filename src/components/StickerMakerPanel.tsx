import React, { useState, useRef, useCallback, useEffect } from 'react';
import {
  Upload,
  Download,
  Share2,
  RotateCcw,
  ZoomIn,
  ZoomOut,
  Crop,
  Sparkles,
  X,
  CheckCircle,
  ImagePlus,
  Sticker,
} from 'lucide-react';

interface StickerMakerPanelProps {
  isOpen: boolean;
  onClose: () => void;
}

type ShapeMode = 'square' | 'circle' | 'rounded';
type FilterMode = 'none' | 'vivid' | 'pop' | 'neon';

const STICKER_SIZE = 512;

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

  // Draw preview canvas
  const drawPreview = useCallback(() => {
    const canvas = previewCanvasRef.current;
    if (!canvas || !image) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const size = canvas.width;
    ctx.clearRect(0, 0, size, size);

    // Background transparent
    ctx.fillStyle = 'transparent';

    // Clip shape
    ctx.save();
    if (shape === 'circle') {
      ctx.beginPath();
      ctx.arc(size / 2, size / 2, size / 2, 0, Math.PI * 2);
      ctx.clip();
    } else if (shape === 'rounded') {
      const r = size * 0.15;
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

    // Draw image
    const scale = zoom;
    const iw = image.width * scale;
    const ih = image.height * scale;
    const aspect = image.width / image.height;

    let drawW, drawH;
    if (aspect >= 1) {
      drawH = size * scale;
      drawW = drawH * aspect;
    } else {
      drawW = size * scale;
      drawH = drawW / aspect;
    }

    const dx = (size - drawW) / 2 + offsetX;
    const dy = (size - drawH) / 2 + offsetY;

    // Apply filter
    if (filter === 'vivid') ctx.filter = 'saturate(1.8) contrast(1.1)';
    else if (filter === 'pop') ctx.filter = 'saturate(2) brightness(1.1) contrast(1.15)';
    else if (filter === 'neon') ctx.filter = 'saturate(3) brightness(1.2) hue-rotate(20deg) contrast(1.2)';
    else ctx.filter = 'none';

    ctx.drawImage(image, dx, dy, drawW, drawH);
    ctx.filter = 'none';
    ctx.restore();

    // Neon border for sticker effect
    ctx.save();
    ctx.strokeStyle = 'rgba(255,255,255,0.85)';
    ctx.lineWidth = size * 0.025;
    if (shape === 'circle') {
      ctx.beginPath();
      ctx.arc(size / 2, size / 2, size / 2 - ctx.lineWidth / 2, 0, Math.PI * 2);
      ctx.stroke();
    } else if (shape === 'rounded') {
      const r = size * 0.15;
      const lw = ctx.lineWidth / 2;
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
      ctx.strokeRect(ctx.lineWidth / 2, ctx.lineWidth / 2, size - ctx.lineWidth, size - ctx.lineWidth);
    }
    ctx.restore();
  }, [image, shape, filter, zoom, offsetX, offsetY]);

  useEffect(() => {
    drawPreview();
  }, [drawPreview]);

  // Reset on close
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
      setZoom(1);
      setOffsetX(0);
      setOffsetY(0);
      setStickerReady(false);
      setStickerUrl(null);
    };
    img.src = url;
    e.target.value = '';
  };

  // Drag to pan
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
    const url = canvas.toDataURL('image/png');
    setStickerUrl(url);
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
      // Convert dataURL to blob
      const res = await fetch(stickerUrl);
      const blob = await res.blob();
      const file = new File([blob], 'stiker.png', { type: 'image/png' });

      if (navigator.share && navigator.canShare?.({ files: [file] })) {
        await navigator.share({
          title: 'Stiker KyokoBeat',
          files: [file],
        });
        showToast('✅ Berhasil dibagikan!');
      } else {
        // Fallback: download
        handleDownload();
        showToast('📲 Simpan dulu, lalu kirim ke WA manual ya!');
      }
    } catch (err: any) {
      if (err.name !== 'AbortError') showToast('Gagal berbagi: ' + err.message);
    } finally {
      setSharing(false);
    }
  };

  const CANVAS_SIZE = 260;

  return (
    <>
      {/* Fullscreen panel */}
      <div
        className="fixed inset-0 z-[100] flex flex-col"
        style={{
          background: 'linear-gradient(135deg, #5b21b6 0%, #7c3aed 40%, #6d28d9 100%)',
          transform: isOpen ? 'translateX(0)' : 'translateX(-100%)',
          transition: 'transform 0.35s cubic-bezier(0.4, 0, 0.2, 1)',
        }}
      >
        {/* Decorative noise texture */}
        <div
          className="absolute inset-0 pointer-events-none opacity-[0.04]"
          style={{
            backgroundImage: `url("data:image/svg+xml,%3Csvg viewBox='0 0 200 200' xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.9' numOctaves='4'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)'/%3E%3C/svg%3E")`,
            backgroundSize: '200px 200px',
          }}
        />

        {/* Geometric accent shapes */}
        <div className="absolute top-0 right-0 w-32 h-32 opacity-10">
          <div className="w-full h-full" style={{ background: 'linear-gradient(45deg, #c8f500, transparent)', clipPath: 'polygon(100% 0, 0 0, 100% 100%)' }} />
        </div>
        <div className="absolute bottom-20 left-0 w-24 h-24 opacity-10">
          <div className="w-full h-full" style={{ background: 'linear-gradient(225deg, #c8f500, transparent)', clipPath: 'polygon(0 100%, 0 0, 100% 100%)' }} />
        </div>

        {/* Close tab on right edge */}
        <button
          onClick={onClose}
          className="absolute right-0 top-1/2 -translate-y-1/2 z-10 flex items-center justify-center"
          style={{
            width: 32,
            height: 64,
            background: '#c8f500',
            clipPath: 'polygon(0 0, 100% 25%, 100% 75%, 0 100%)',
            cursor: 'pointer',
          }}
          aria-label="Tutup panel stiker"
        >
          {/* invisible hitbox filler */}
        </button>

        {/* Header */}
        <div className="relative z-10 flex items-center gap-3 px-5 pt-10 pb-4">
          <div className="p-2 rounded-xl" style={{ background: 'rgba(200,245,0,0.15)', border: '1px solid rgba(200,245,0,0.3)' }}>
            <Sticker className="w-5 h-5" style={{ color: '#c8f500' }} />
          </div>
          <div>
            <h1 className="font-bold text-xl text-white tracking-widest uppercase" style={{ fontFamily: 'system-ui, sans-serif', letterSpacing: '0.15em' }}>STIKER MAKER</h1>
            <p className="text-xs" style={{ color: 'rgba(255,255,255,0.55)' }}>Upload foto → jadi stiker WA</p>
          </div>
        </div>

        {/* Content */}
        <div className="relative z-10 flex-1 overflow-y-auto px-5 pb-8 flex flex-col gap-5">

          {/* Upload area */}
          {!imageDataUrl ? (
            <button
              onClick={() => fileInputRef.current?.click()}
              className="flex flex-col items-center justify-center gap-3 rounded-2xl border-2 border-dashed py-10 transition-all active:scale-95"
              style={{ borderColor: 'rgba(200,245,0,0.4)', background: 'rgba(0,0,0,0.2)' }}
            >
              <div className="p-4 rounded-full" style={{ background: 'rgba(200,245,0,0.1)' }}>
                <ImagePlus className="w-8 h-8" style={{ color: '#c8f500' }} />
              </div>
              <div className="text-center">
                <p className="font-bold text-white text-sm uppercase tracking-widest">Pilih Foto</p>
                <p className="text-xs mt-1" style={{ color: 'rgba(255,255,255,0.45)' }}>dari galeri atau kamera</p>
              </div>
            </button>
          ) : (
            <>
              {/* Canvas preview */}
              <div className="flex flex-col items-center gap-2">
                <canvas
                  ref={previewCanvasRef}
                  width={CANVAS_SIZE}
                  height={CANVAS_SIZE}
                  className="rounded-2xl select-none"
                  style={{
                    background: 'repeating-conic-gradient(rgba(255,255,255,0.07) 0% 25%, transparent 0% 50%) 0 0 / 16px 16px',
                    cursor: isDragging ? 'grabbing' : 'grab',
                    touchAction: 'none',
                    boxShadow: '0 0 40px rgba(124,58,237,0.5), 0 0 80px rgba(200,245,0,0.1)',
                  }}
                  onMouseDown={handleMouseDown}
                  onMouseMove={handleMouseMove}
                  onMouseUp={handleMouseUp}
                  onMouseLeave={handleMouseUp}
                  onTouchStart={handleMouseDown}
                  onTouchMove={handleMouseMove}
                  onTouchEnd={handleMouseUp}
                />
                <p className="text-xs" style={{ color: 'rgba(255,255,255,0.4)' }}>Geser untuk mengatur posisi</p>
              </div>

              {/* Zoom controls */}
              <div className="flex items-center gap-3">
                <button
                  onClick={() => setZoom(z => Math.max(0.5, z - 0.1))}
                  className="p-2 rounded-lg transition-all active:scale-90"
                  style={{ background: 'rgba(0,0,0,0.3)', border: '1px solid rgba(255,255,255,0.1)' }}
                >
                  <ZoomOut className="w-4 h-4 text-white" />
                </button>
                <div className="flex-1 relative h-2 rounded-full overflow-hidden" style={{ background: 'rgba(0,0,0,0.3)' }}>
                  <div
                    className="absolute inset-y-0 left-0 rounded-full"
                    style={{ width: `${((zoom - 0.5) / 2.5) * 100}%`, background: '#c8f500' }}
                  />
                  <input
                    type="range"
                    min={0.5} max={3} step={0.05}
                    value={zoom}
                    onChange={e => setZoom(parseFloat(e.target.value))}
                    className="absolute inset-0 w-full opacity-0 cursor-pointer"
                  />
                </div>
                <button
                  onClick={() => setZoom(z => Math.min(3, z + 0.1))}
                  className="p-2 rounded-lg transition-all active:scale-90"
                  style={{ background: 'rgba(0,0,0,0.3)', border: '1px solid rgba(255,255,255,0.1)' }}
                >
                  <ZoomIn className="w-4 h-4 text-white" />
                </button>
                <button
                  onClick={() => { setZoom(1); setOffsetX(0); setOffsetY(0); }}
                  className="p-2 rounded-lg transition-all active:scale-90"
                  style={{ background: 'rgba(0,0,0,0.3)', border: '1px solid rgba(255,255,255,0.1)' }}
                >
                  <RotateCcw className="w-4 h-4 text-white" />
                </button>
              </div>

              {/* Shape selector */}
              <div>
                <p className="text-xs font-bold uppercase tracking-widest mb-2" style={{ color: 'rgba(255,255,255,0.5)' }}>Bentuk Stiker</p>
                <div className="flex gap-2">
                  {(['square', 'rounded', 'circle'] as ShapeMode[]).map(s => (
                    <button
                      key={s}
                      onClick={() => { setShape(s); setStickerReady(false); }}
                      className="flex-1 py-2.5 text-xs font-bold uppercase tracking-wider transition-all active:scale-95"
                      style={{
                        borderRadius: s === 'circle' ? '9999px' : s === 'rounded' ? '12px' : '6px',
                        background: shape === s ? '#c8f500' : 'rgba(0,0,0,0.3)',
                        color: shape === s ? '#1a0a4a' : 'rgba(255,255,255,0.7)',
                        border: shape === s ? '1.5px solid #c8f500' : '1.5px solid rgba(255,255,255,0.1)',
                      }}
                    >
                      {s === 'square' ? 'Kotak' : s === 'rounded' ? 'Bulat Sudut' : 'Lingkaran'}
                    </button>
                  ))}
                </div>
              </div>

              {/* Filter selector */}
              <div>
                <p className="text-xs font-bold uppercase tracking-widest mb-2" style={{ color: 'rgba(255,255,255,0.5)' }}>Filter</p>
                <div className="flex gap-2 overflow-x-auto pb-1">
                  {(['none', 'vivid', 'pop', 'neon'] as FilterMode[]).map(f => (
                    <button
                      key={f}
                      onClick={() => { setFilter(f); setStickerReady(false); }}
                      className="flex-shrink-0 px-4 py-2 text-xs font-bold uppercase tracking-wider rounded-full transition-all active:scale-95"
                      style={{
                        background: filter === f ? '#c8f500' : 'rgba(0,0,0,0.3)',
                        color: filter === f ? '#1a0a4a' : 'rgba(255,255,255,0.7)',
                        border: filter === f ? '1.5px solid #c8f500' : '1.5px solid rgba(255,255,255,0.1)',
                      }}
                    >
                      {f === 'none' ? 'Original' : f === 'vivid' ? 'Vivid' : f === 'pop' ? 'Pop' : '⚡ Neon'}
                    </button>
                  ))}
                </div>
              </div>

              {/* Action buttons */}
              <div className="flex flex-col gap-3 mt-2">
                {/* Generate sticker */}
                <button
                  onClick={generateSticker}
                  className="w-full py-3.5 flex items-center justify-center gap-2 rounded-2xl font-bold uppercase tracking-widest text-sm transition-all active:scale-95"
                  style={{
                    background: '#c8f500',
                    color: '#1a0a4a',
                    boxShadow: '0 0 20px rgba(200,245,0,0.4)',
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
                        background: 'rgba(200,245,0,0.12)',
                        color: '#c8f500',
                        border: '1.5px solid rgba(200,245,0,0.4)',
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
                        background: 'rgba(37,211,102,0.15)',
                        color: '#25d366',
                        border: '1.5px solid rgba(37,211,102,0.4)',
                        opacity: sharing ? 0.7 : 1,
                      }}
                    >
                      {sharing ? (
                        <div className="w-4 h-4 border-2 border-[#25d366] border-t-transparent rounded-full animate-spin" />
                      ) : (
                        <Share2 className="w-4 h-4" />
                      )}
                      {sharing ? 'Membagikan...' : 'Kirim ke WhatsApp'}
                    </button>
                  </>
                )}

                {/* Change photo */}
                <button
                  onClick={() => fileInputRef.current?.click()}
                  className="w-full py-3 flex items-center justify-center gap-2 rounded-2xl text-sm transition-all active:scale-95"
                  style={{
                    background: 'rgba(0,0,0,0.25)',
                    color: 'rgba(255,255,255,0.55)',
                    border: '1px solid rgba(255,255,255,0.1)',
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
        <input
          ref={fileInputRef}
          type="file"
          accept="image/*"
          className="hidden"
          onChange={handleFileSelect}
        />

        {/* Toast */}
        {toastMsg && (
          <div
            className="fixed bottom-8 left-1/2 -translate-x-1/2 z-[110] px-5 py-3 rounded-xl text-sm font-semibold text-white shadow-lg"
            style={{
              background: 'rgba(30,10,70,0.95)',
              border: '1px solid rgba(200,245,0,0.3)',
              backdropFilter: 'blur(10px)',
              animation: 'fadeInUp 0.3s ease',
            }}
          >
            {toastMsg}
          </div>
        )}
      </div>

      <style>{`
        @keyframes fadeInUp {
          from { opacity: 0; transform: translateX(-50%) translateY(10px); }
          to { opacity: 1; transform: translateX(-50%) translateY(0); }
        }
      `}</style>
    </>
  );
};

export default StickerMakerPanel;
