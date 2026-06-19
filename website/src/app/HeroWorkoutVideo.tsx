"use client";

import { useEffect, useRef } from "react";

const heroVideoVersion = "20260606-rep-badge-v4";

export function HeroWorkoutVideo() {
  const videoRef = useRef<HTMLVideoElement | null>(null);

  useEffect(() => {
    const video = videoRef.current;
    if (!video) {
      return;
    }

    const playWhenAllowed = () => {
      video.muted = true;
      video.defaultMuted = true;
      void video.play().catch(() => {});
    };

    playWhenAllowed();

    const observer = new IntersectionObserver(
      (entries) => {
        if (entries.some((entry) => entry.isIntersecting)) {
          playWhenAllowed();
        }
      },
      { threshold: 0.1 },
    );

    observer.observe(video);
    window.addEventListener("focus", playWhenAllowed);
    document.addEventListener("visibilitychange", playWhenAllowed);

    return () => {
      observer.disconnect();
      window.removeEventListener("focus", playWhenAllowed);
      document.removeEventListener("visibilitychange", playWhenAllowed);
    };
  }, []);

  return (
    <video
      ref={videoRef}
      className="block h-auto w-full"
      autoPlay
      loop
      muted
      playsInline
      preload="auto"
      poster={`/app-assets/product/momentum-app-workout-hero.jpg?v=${heroVideoVersion}`}
      aria-label="Momentum Mac app showing moving workout video with a skeleton tracking overlay and rep count confirmation"
    >
      <source
        src={`/app-assets/product/momentum-app-workout-hero.mp4?v=${heroVideoVersion}`}
        type="video/mp4"
      />
      <source
        src={`/app-assets/product/momentum-app-workout-hero.webm?v=${heroVideoVersion}`}
        type="video/webm"
      />
    </video>
  );
}
