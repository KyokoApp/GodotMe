import { useState, useEffect, useRef } from "react";

const COVER = "https://raw.githubusercontent.com/Crashmant/rizky/main/uploads/1780465102494-416.jpeg";
const BAR_COUNT = 64;
const CX = 155, CY = 155, R_INNER = 90;

function formatTime(s) {
  if (!s || isNaN(s)) return "0:00";
  const m = Math.floor(s / 60);
  const sec = Math.floor(s % 60);
  return `${m}:${sec.toString().padStart(2, "0")}`;
}

export default function KyokoBeatPlayer() {
  const [playing, setPlaying] = useState(false);
  const [progress, setProgress] = useState(0);
  const [duration, setDuration] = useState(0);
  const [volume, setVolume] = useState(0.85);
  const [liked, setLiked] = useState(false);
  const [shuffle, setShuffle] = useState(false);
  const [repeat, setRepeat] = useState(false);
  const [trackName, setTrackName] = useState("Fond Memories");
  const [artist, setArtist] = useState("Unknown Artist");
  const [bars, setBars] = useState(() => new Array(BAR_COUNT).fill(2));
  const [dragging, setDragging] = useState(false);

  const audioRef = useRef(null);
  const audioCtxRef = useRef(null);
  const analyserRef = useRef(null);
  const sourceRef = useRef(null);
  const rafRef = useRef(null);
  const smoothBarsRef = useRef(new Float32Array(BAR_COUNT).fill(2));
  const progressBarRef = useRef(null);
  const volumeBarRef = useRef(null);

  // Setup analyser
  const setupAudioContext = (audioEl) => {
    if (audioCtxRef.current) return;
    const ctx = new (window.AudioContext || window.webkitAudioContext)();
    const analyser = ctx.createAnalyser();
    analyser.fftSize = 256;
    analyser.smoothingTimeConstant = 0.75;
    const source = ctx.createMediaElementSource(audioEl);
    source.connect(analyser);
    analyser.connect(ctx.destination);
    audioCtxRef.current = ctx;
    analyserRef.current = analyser;
    sourceRef.current = source;
  };

  // Animation loop
  useEffect(() => {
    const tick = () => {
      rafRef.current = requestAnimationFrame(tick);
      if (!analyserRef.current) {
        // idle breathe
        const t = Date.now() / 1000;
        const next = smoothBarsRef.current.map((_, i) => {
          const wave = 2 + 2 * Math.abs(Math.sin(t * 0.4 + i * 0.25));
          smoothBarsRef.current[i] += (wave - smoothBarsRef.current[i]) * 0.06;
          return smoothBarsRef.current[i];
        });
        setBars([...next]);
        return;
      }
      const dataArray = new Uint8Array(analyserRef.current.frequencyBinCount);
      analyserRef.current.getByteFrequencyData(dataArray);
      const binCount = dataArray.length;
      for (let i = 0; i < BAR_COUNT; i++) {
        const start = Math.floor((i / BAR_COUNT) * binCount);
        const end = Math.floor(((i + 1) / BAR_COUNT) * binCount);
        let sum = 0;
        for (let j = start; j < end; j++) sum += dataArray[j];
        const avg = sum / (end - start) || 0;
        const target = playing ? (avg / 255) * 58 + 2 : 2 + 1.5 * Math.abs(Math.sin(Date.now() / 1200 + i * 0.3));
        smoothBarsRef.current[i] += (target - smoothBarsRef.current[i]) * (playing ? 0.3 : 0.06);
      }
      setBars([...smoothBarsRef.current]);
    };
    rafRef.current = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(rafRef.current);
  }, [playing]);

  // Progress update
  useEffect(() => {
    const audio = audioRef.current;
    if (!audio) return;
    const onTime = () => { if (!dragging) setProgress(audio.currentTime); };
    const onLoad = () => setDuration(audio.duration);
    const onEnd = () => { setPlaying(false); setProgress(0); };
    audio.addEventListener("timeupdate", onTime);
    audio.addEventListener("loadedmetadata", onLoad);
    audio.addEventListener("ended", onEnd);
    return () => {
      audio.removeEventListener("timeupdate", onTime);
      audio.removeEventListener("loadedmetadata", onLoad);
      audio.removeEventListener("ended", onEnd);
    };
  }, [dragging]);

  const togglePlay = async () => {
    const audio = audioRef.current;
    if (!audio.src && !audio.srcObject) return;
    setupAudioContext(audio);
    if (audioCtxRef.current?.state === "suspended") await audioCtxRef.current.resume();
    if (playing) { audio.pause(); setPlaying(false); }
    else { await audio.play(); setPlaying(true); }
  };

  const handleFileUpload = (e) => {
    const file = e.target.files[0];
    if (!file) return;
    const url = URL.createObjectURL(file);
    const audio = audioRef.current;
    // Reset ctx so it gets re-created for new source
    if (audioCtxRef.current) {
      audioCtxRef.current.close();
      audioCtxRef.current = null;
      analyserRef.current = null;
      sourceRef.current = null;
    }
    audio.src = url;
    audio.load();
    setTrackName(file.name.replace(/\.[^/.]+$/, "").slice(0, 30));
    setArtist("Local File");
    setProgress(0);
    setPlaying(false);
  };

  const seekTo = (clientX) => {
    if (!progressBarRef.current || !duration) return;
    const rect = progressBarRef.current.getBoundingClientRect();
    const ratio = Math.max(0, Math.min(1, (clientX - rect.left) / rect.width));
    const newTime = ratio * duration;
    audioRef.current.currentTime = newTime;
    setProgress(newTime);
  };

  const setVol = (clientX) => {
    if (!volumeBarRef.current) return;
    const rect = volumeBarRef.current.getBoundingClientRect();
    const v = Math.max(0, Math.min(1, (clientX - rect.left) / rect.width));
    audioRef.current.volume = v;
    setVolume(v);
  };

  const pct = duration ? (progress / duration) * 100 : 0;

  return (
    <div style={{
      minHeight: "100vh",
      background: "radial-gradient(ellipse at 50% 0%, #0f1a00 0%, #050508 55%)",
      display: "flex", flexDirection: "column",
      alignItems: "center", justifyContent: "center",
      fontFamily: "'Rajdhani', sans-serif",
      userSelect: "none",
    }}>
      <audio ref={audioRef} volume={volume} />

      <style>{`
        @import url('https://fonts.googleapis.com/css2?family=Orbitron:wght@600;800&family=Rajdhani:wght@400;500;600&display=swap');
        * { box-sizing: border-box; margin: 0; padding: 0; }

        .card {
          width: 320px;
          background: linear-gradient(170deg, #0c0c14 0%, #080810 100%);
          border: 1px solid rgba(200,245,0,0.1);
          border-radius: 28px;
          padding: 22px 20px 20px;
          box-shadow: 0 0 80px rgba(200,245,0,0.05), 0 30px 80px rgba(0,0,0,0.7),
                      inset 0 1px 0 rgba(200,245,0,0.07);
          position: relative;
          overflow: hidden;
        }
        .card::after {
          content:''; position:absolute;
          inset:0; border-radius:28px;
          background: radial-gradient(ellipse at 50% -10%, rgba(200,245,0,0.04) 0%, transparent 60%);
          pointer-events:none;
        }

        .topbar {
          display:flex; align-items:center; justify-content:space-between;
          margin-bottom:16px;
        }
        .ghost-btn {
          background:none; border:none; cursor:pointer;
          color:rgba(200,245,0,0.45); transition:color 0.2s;
          display:flex; align-items:center; justify-content:center;
          width:28px; height:28px; border-radius:8px;
        }
        .ghost-btn:hover { color:#c8f500; }
        .src-label { text-align:center; }
        .src-from { font-size:9px; letter-spacing:2px; color:rgba(255,255,255,0.25); text-transform:uppercase; }
        .src-name { font-size:11px; color:rgba(255,255,255,0.55); font-weight:600; }

        /* Spectrum area */
        .vis-wrap {
          position:relative; display:flex;
          align-items:center; justify-content:center;
          height:310px; margin-bottom:16px;
        }
        .album-circle {
          position:absolute;
          width:178px; height:178px;
          border-radius:50%; overflow:hidden;
          border:2px solid rgba(200,245,0,0.2);
          box-shadow: 0 0 0 6px rgba(200,245,0,0.04), 0 0 40px rgba(200,245,0,0.1);
          z-index:2;
          animation: spinAlbum 22s linear infinite;
          animation-play-state: paused;
        }
        .album-circle.spinning { animation-play-state: running; }
        .album-circle img { width:100%; height:100%; object-fit:cover; border-radius:50%; }
        @keyframes spinAlbum { to { transform:rotate(360deg); } }

        /* Glow pulse ring */
        .pulse-ring {
          position:absolute; width:196px; height:196px;
          border-radius:50%;
          border:1px solid rgba(200,245,0,0.15);
          animation:pulseRing 2s ease-in-out infinite;
          animation-play-state:paused;
          z-index:1;
        }
        .pulse-ring.active { animation-play-state:running; }
        @keyframes pulseRing {
          0%,100% { transform:scale(1); opacity:0.15; }
          50% { transform:scale(1.04); opacity:0.35; }
        }

        /* Track info */
        .track-row {
          display:flex; align-items:center; justify-content:space-between;
          margin-bottom:16px; padding:0 2px;
        }
        .track-title {
          font-family:'Orbitron',monospace;
          font-size:13px; font-weight:800;
          color:#fff; letter-spacing:0.3px;
          white-space:nowrap; overflow:hidden; text-overflow:ellipsis;
          max-width:210px;
        }
        .track-artist { font-size:11px; color:rgba(255,255,255,0.38); margin-top:2px; }
        .heart-btn {
          background:none; border:none; cursor:pointer;
          font-size:19px; color:rgba(255,255,255,0.25);
          transition:all 0.2s; flex-shrink:0;
        }
        .heart-btn.on { color:#c8f500; filter:drop-shadow(0 0 5px #c8f500aa); }

        /* Seek bar */
        .seek-wrap { padding:0 2px; margin-bottom:4px; }
        .seek-track {
          width:100%; height:3px;
          background:rgba(255,255,255,0.07);
          border-radius:99px; cursor:pointer;
          position:relative;
        }
        .seek-fill {
          height:100%;
          background:linear-gradient(90deg,#c8f500,#a8e000);
          border-radius:99px; position:relative;
          box-shadow:0 0 10px rgba(200,245,0,0.5);
        }
        .seek-fill::after {
          content:''; position:absolute;
          right:-5px; top:50%; transform:translateY(-50%);
          width:11px; height:11px;
          background:#c8f500; border-radius:50%;
          box-shadow:0 0 10px rgba(200,245,0,0.9);
        }
        .seek-times {
          display:flex; justify-content:space-between;
          font-size:10px; color:rgba(255,255,255,0.3);
          margin-top:7px; font-variant-numeric:tabular-nums;
        }

        /* Controls */
        .controls {
          display:flex; align-items:center; justify-content:space-between;
          padding:14px 2px 16px;
        }
        .ctl {
          background:none; border:none; cursor:pointer;
          color:rgba(255,255,255,0.3); padding:8px;
          border-radius:50%; transition:all 0.18s;
          display:flex; align-items:center; justify-content:center;
        }
        .ctl:hover { color:rgba(255,255,255,0.65); }
        .ctl.on { color:#c8f500; filter:drop-shadow(0 0 4px #c8f500); }
        .ctl svg { width:19px; height:19px; fill:currentColor; }
        .play-circle {
          width:56px; height:56px; border-radius:50%;
          background:#fff; border:none; cursor:pointer;
          display:flex; align-items:center; justify-content:center;
          box-shadow:0 0 24px rgba(200,245,0,0.25), 0 6px 20px rgba(0,0,0,0.5);
          transition:all 0.15s;
        }
        .play-circle:hover { transform:scale(1.07); box-shadow:0 0 35px rgba(200,245,0,0.4), 0 6px 22px rgba(0,0,0,0.55); }
        .play-circle:active { transform:scale(0.94); }
        .play-circle svg { width:22px; height:22px; fill:#0a0a0a; }

        /* Volume */
        .vol-row {
          display:flex; align-items:center; gap:10px;
          padding:0 2px; margin-bottom:14px;
        }
        .vol-icon { font-size:13px; color:rgba(255,255,255,0.28); }
        .vol-track {
          flex:1; height:3px; background:rgba(255,255,255,0.07);
          border-radius:99px; cursor:pointer; position:relative;
        }
        .vol-fill {
          height:100%; background:rgba(255,255,255,0.28);
          border-radius:99px; position:relative;
        }
        .vol-fill::after {
          content:''; position:absolute;
          right:-4px; top:50%; transform:translateY(-50%);
          width:9px; height:9px;
          background:#fff; border-radius:50%;
        }

        /* Upload button */
        .upload-label {
          display:flex; align-items:center; justify-content:center; gap:7px;
          width:100%; padding:9px;
          border:1px dashed rgba(200,245,0,0.2);
          border-radius:12px; cursor:pointer;
          color:rgba(200,245,0,0.5);
          font-family:'Rajdhani',sans-serif;
          font-size:12px; font-weight:600; letter-spacing:1px;
          text-transform:uppercase;
          transition:all 0.2s;
          background:rgba(200,245,0,0.02);
        }
        .upload-label:hover {
          border-color:rgba(200,245,0,0.5);
          color:#c8f500;
          background:rgba(200,245,0,0.05);
        }
        .upload-input { display:none; }
      `}</style>

      <div className="card">
        {/* Top */}
        <div className="topbar">
          <button className="ghost-btn">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><path d="M7.41 15.41L12 10.83l4.59 4.58L18 14l-6-6-6 6z"/></svg>
          </button>
          <div className="src-label">
            <div className="src-from">Memutar Dari</div>
            <div className="src-name">KyokoBeat</div>
          </div>
          <button className="ghost-btn">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><path d="M12 8c1.1 0 2-.9 2-2s-.9-2-2-2-2 .9-2 2 .9 2 2 2zm0 2c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2zm0 6c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2z"/></svg>
          </button>
        </div>

        {/* Visualizer + Album Art */}
        <div className="vis-wrap">
          <svg width="310" height="310" viewBox="0 0 310 310" style={{ position:"absolute", top:0, left:0 }}>
            <defs>
              <radialGradient id="barGrad" cx="50%" cy="50%" r="50%">
                <stop offset="0%" stopColor="#c8f500" stopOpacity="0.9"/>
                <stop offset="100%" stopColor="#80c200" stopOpacity="0.3"/>
              </radialGradient>
            </defs>
            {bars.map((h, i) => {
              const angle = (i / BAR_COUNT) * Math.PI * 2 - Math.PI / 2;
              const clamped = Math.max(2, Math.min(h, 62));
              const x1 = CX + R_INNER * Math.cos(angle);
              const y1 = CY + R_INNER * Math.sin(angle);
              const x2 = CX + (R_INNER + clamped) * Math.cos(angle);
              const y2 = CY + (R_INNER + clamped) * Math.sin(angle);
              const t = clamped / 62;
              const r = Math.round(150 + t * 50);
              const g = Math.round(230 + t * 25);
              const a = 0.25 + t * 0.75;
              return (
                <line
                  key={i}
                  x1={x1} y1={y1} x2={x2} y2={y2}
                  stroke={`rgba(${r},${g},0,${a})`}
                  strokeWidth={t > 0.7 ? 2.8 : 2}
                  strokeLinecap="round"
                />
              );
            })}
          </svg>

          <div className={`pulse-ring${playing ? " active" : ""}`} />

          <div className={`album-circle${playing ? " spinning" : ""}`}>
            <img
              src={COVER}
              alt="cover"
              onError={e => {
                e.target.onerror = null;
                e.target.style.background = "#0d0d14";
                e.target.src = "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 178 178'%3E%3Ccircle cx='89' cy='89' r='89' fill='%230d0d14'/%3E%3Ccircle cx='89' cy='89' r='36' fill='none' stroke='%23c8f500' stroke-width='2' opacity='0.3'/%3E%3Ccircle cx='89' cy='89' r='9' fill='%23c8f500' opacity='0.5'/%3E%3C/svg%3E";
              }}
            />
          </div>
        </div>

        {/* Track info */}
        <div className="track-row">
          <div>
            <div className="track-title">{trackName}</div>
            <div className="track-artist">{artist}</div>
          </div>
          <button className={`heart-btn${liked?" on":""}`} onClick={() => setLiked(l=>!l)}>
            {liked ? "♥" : "♡"}
          </button>
        </div>

        {/* Seek */}
        <div className="seek-wrap">
          <div
            ref={progressBarRef}
            className="seek-track"
            onClick={e => seekTo(e.clientX)}
            onMouseDown={e => { setDragging(true); seekTo(e.clientX); }}
            onMouseMove={e => { if (dragging) seekTo(e.clientX); }}
            onMouseUp={() => setDragging(false)}
            onMouseLeave={() => setDragging(false)}
          >
            <div className="seek-fill" style={{ width: `${pct}%` }} />
          </div>
          <div className="seek-times">
            <span>{formatTime(progress)}</span>
            <span>{formatTime(duration)}</span>
          </div>
        </div>

        {/* Controls */}
        <div className="controls">
          <button className={`ctl${shuffle?" on":""}`} onClick={()=>setShuffle(s=>!s)}>
            <svg viewBox="0 0 24 24"><path d="M17 4l4 4-4 4V9h-1.5c-.83 0-1.5.35-2.12.96L12 11.33 10.62 9.96C9.99 9.34 9.17 9 8.5 9H4V7h4.5c1.17 0 2.18.48 2.95 1.24L12.88 9.6l1.56-1.56c.28-.28.59-.54.93-.74C16.01 6.49 17 5.33 17 4zm-9.5 8c.67 0 1.47.27 2.1.9l1.4 1.38 1.4-1.38c.63-.63 1.43-.9 2.1-.9H17v-1l4 4-4 4v-3h-2.5c-1.17 0-2.18-.48-2.95-1.24L10 13.4l-1.55 1.56C7.81 15.67 6.8 16 5.5 16H2v-2h3.5c.67 0 1.47-.27 2.1-.9L9 11.72l-.5-.5C7.99 10.74 7.23 10.5 6.5 10.5H2V8h4.5c1.17 0 2.18.48 2.95 1.24l.05.06z"/></svg>
          </button>
          <button className="ctl" onClick={()=>{if(audioRef.current)audioRef.current.currentTime=0;}}>
            <svg viewBox="0 0 24 24"><path d="M6 6h2v12H6zm3.5 6l8.5 6V6z"/></svg>
          </button>
          <button className="play-circle" onClick={togglePlay}>
            {playing
              ? <svg viewBox="0 0 24 24"><path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z"/></svg>
              : <svg viewBox="0 0 24 24"><path d="M8 5v14l11-7z"/></svg>
            }
          </button>
          <button className="ctl" onClick={()=>{if(audioRef.current){audioRef.current.currentTime=duration||0;}}}>
            <svg viewBox="0 0 24 24"><path d="M6 18l8.5-6L6 6v12zM16 6v12h2V6h-2z"/></svg>
          </button>
          <button className={`ctl${repeat?" on":""}`} onClick={()=>setRepeat(r=>!r)}>
            <svg viewBox="0 0 24 24"><path d="M7 7h10v3l4-4-4-4v3H5v6h2V7zm10 10H7v-3l-4 4 4 4v-3h12v-6h-2v4z"/></svg>
          </button>
        </div>

        {/* Volume */}
        <div className="vol-row">
          <span className="vol-icon">🔈</span>
          <div
            ref={volumeBarRef}
            className="vol-track"
            onClick={e => setVol(e.clientX)}
          >
            <div className="vol-fill" style={{ width:`${volume*100}%` }} />
          </div>
          <span className="vol-icon">🔊</span>
        </div>

        {/* Upload */}
        <label className="upload-label">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><path d="M9 16h6v-6h4l-7-7-7 7h4zm-4 2h14v2H5z"/></svg>
          Upload Audio
          <input
            type="file"
            accept="audio/*"
            className="upload-input"
            onChange={handleFileUpload}
          />
        </label>
      </div>
    </div>
  );
}
