import React, { useEffect, useRef } from 'react';
import audioManager from '../lib/audio';

interface WaveformVisualizerProps {
  isPlaying: boolean;
}

export default function WaveformVisualizer({ isPlaying }: WaveformVisualizerProps) {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const animationRef = useRef<number | null>(null);
  const smoothRef = useRef<Float32Array>(new Float32Array(64).fill(2));

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const resize = () => {
      canvas.width = canvas.parentElement?.clientWidth || 300;
      canvas.height = 40;
    };
    resize();
    window.addEventListener('resize', resize);

    const draw = () => {
      animationRef.current = requestAnimationFrame(draw);
      const w = canvas.width;
      const h = canvas.height;
      ctx.clearRect(0, 0, w, h);

      const dataArray = audioManager.getAnalyserData();
      const BAR_COUNT = 64;
      const barW = w / BAR_COUNT - 1;

      for (let i = 0; i < BAR_COUNT; i++) {
        let target: number;
        if (isPlaying && dataArray) {
          const bin = Math.floor((i / BAR_COUNT) * dataArray.length);
          target = (dataArray[bin] / 255) * h * 0.92;
        } else {
          const t = Date.now() / 1100;
          target = 2.5 + 2 * Math.abs(Math.sin(t + i * 0.28));
        }

        // Lerp: fast rise, slow fall
        const prev = smoothRef.current[i];
        smoothRef.current[i] = target > prev
          ? prev + (target - prev) * 0.45
          : prev + (target - prev) * 0.12;

        const bh = Math.max(2, smoothRef.current[i]);
        const intensity = bh / (h * 0.92);

        const grad = ctx.createLinearGradient(0, h, 0, h - bh);
        grad.addColorStop(0, `rgba(200,245,0,${0.85 + intensity * 0.15})`);
        grad.addColorStop(0.5, `rgba(180,230,0,${0.5 + intensity * 0.3})`);
        grad.addColorStop(1, `rgba(150,200,0,${0.1 + intensity * 0.2})`);

        ctx.fillStyle = grad;
        const x = i * (barW + 1);
        const radius = Math.min(barW / 2, 2);
        ctx.beginPath();
        ctx.moveTo(x + radius, h - bh);
        ctx.lineTo(x + barW - radius, h - bh);
        ctx.quadraticCurveTo(x + barW, h - bh, x + barW, h - bh + radius);
        ctx.lineTo(x + barW, h);
        ctx.lineTo(x, h);
        ctx.lineTo(x, h - bh + radius);
        ctx.quadraticCurveTo(x, h - bh, x + radius, h - bh);
        ctx.closePath();
        ctx.fill();
      }
    };

    draw();

    return () => {
      if (animationRef.current) cancelAnimationFrame(animationRef.current);
      window.removeEventListener('resize', resize);
    };
  }, [isPlaying]);

  return (
    <div className="w-full overflow-hidden" style={{ height: 40, opacity: 0.85 }}>
      <canvas ref={canvasRef} className="w-full h-full block" />
    </div>
  );
}
