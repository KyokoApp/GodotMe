import React, { useEffect, useRef } from 'react';
import audioManager from '../lib/audio';

interface WaveformVisualizerProps {
  isPlaying: boolean;
}

export default function WaveformVisualizer({ isPlaying }: WaveformVisualizerProps) {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const animationRef = useRef<number | null>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    // Resize canvas to match display width
    const resizeCanvas = () => {
      canvas.width = canvas.parentElement?.clientWidth || 300;
      canvas.height = 40;
    };
    resizeCanvas();
    window.addEventListener('resize', resizeCanvas);

    const draw = () => {
      animationRef.current = requestAnimationFrame(draw);

      const width = canvas.width;
      const height = canvas.height;
      ctx.clearRect(0, 0, width, height);

      const dataArray = audioManager.getAnalyserData();

      if (isPlaying && dataArray) {
        // Draw live frequency spectrum
        const barWidth = (width / dataArray.length) * 1.5;
        let barHeight;
        let x = 0;

        for (let i = 0; i < dataArray.length; i++) {
          barHeight = (dataArray[i] / 255) * height * 0.9;

          // Gradient color from lime green to semi-transparent
          const gradient = ctx.createLinearGradient(0, height, 0, 0);
          gradient.addColorStop(0, '#c8f500');
          gradient.addColorStop(0.5, 'rgba(200, 245, 0, 0.6)');
          gradient.addColorStop(1, 'rgba(200, 245, 0, 0)');

          ctx.fillStyle = gradient;
          
          // Draw rounded bars
          ctx.fillRect(x, height - barHeight, barWidth - 1, barHeight);

          x += barWidth;
        }
      } else {
        // Draw standard subtle wave when paused
        ctx.beginPath();
        ctx.moveTo(0, height / 2);
        
        const amplitude = 3;
        const frequency = 0.05;
        const speed = Date.now() * 0.002;

        for (let x = 0; x < width; x++) {
          const y = height / 2 + Math.sin(x * frequency + speed) * amplitude;
          ctx.lineTo(x, y);
        }

        ctx.strokeStyle = 'rgba(200, 245, 0, 0.3)';
        ctx.lineWidth = 1.5;
        ctx.stroke();
      }
    };

    draw();

    return () => {
      if (animationRef.current) {
        cancelAnimationFrame(animationRef.current);
      }
      window.removeEventListener('resize', resizeCanvas);
    };
  }, [isPlaying]);

  return (
    <div className="w-full h-10 overflow-hidden opacity-80">
      <canvas ref={canvasRef} className="w-full h-full block" />
    </div>
  );
}
