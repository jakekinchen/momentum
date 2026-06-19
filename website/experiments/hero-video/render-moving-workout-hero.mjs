#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import path from "node:path";

const repoRoot = path.resolve(import.meta.dirname, "../../..");
const websiteRoot = path.join(repoRoot, "website");
const outputRoot = path.join(websiteRoot, "output", "hero-video");
const publicProductRoot = path.join(
  websiteRoot,
  "public",
  "app-assets",
  "product",
);

const baseScreenshot = path.join(
  repoRoot,
  "dist",
  "qa-screenshots",
  "2026-06-06-01-baseline.png",
);
const lungeSourceVideo = path.join(
  repoRoot,
  "dist",
  "motion-reference",
  "bodyweight_lunge",
  "source",
  "commons-forward-lunge.webm",
);
const rawPoseTrace = path.join(
  repoRoot,
  "dist",
  "motion-reference",
  "bodyweight_lunge",
  "commons_forward_lunge_30_36",
  "raw_mediapipe.jsonl",
);

const baseImage = path.join(outputRoot, "app-clean-base.png");
const surfaceFramesDir = path.join(outputRoot, "workout-surface");
const skeletonSvgDir = path.join(outputRoot, "skeleton-svg");
const skeletonPngDir = path.join(outputRoot, "skeleton-png");
const masterVideo = path.join(outputRoot, "momentum-app-workout-hero-master.mp4");
const finalMp4 = path.join(publicProductRoot, "momentum-app-workout-hero.mp4");
const finalWebm = path.join(publicProductRoot, "momentum-app-workout-hero.webm");
const posterImage = path.join(publicProductRoot, "momentum-app-workout-hero.jpg");
const badgeFont = "/System/Library/Fonts/Supplemental/Arial.ttf";

const fps = 15;
const durationSeconds = 6;
const frameCount = fps * durationSeconds;
const clipStartSeconds = 30;
const surface = {
  width: 1178,
  height: 552,
  x: 305,
  y: 121,
};
const source = {
  width: 1920,
  height: 1080,
};
const scaledSourceHeight = (surface.width * source.height) / source.width;
const croppedTop = (scaledSourceHeight - surface.height) / 2;

const poseConnections = [
  [11, 12],
  [11, 13],
  [13, 15],
  [15, 17],
  [15, 19],
  [15, 21],
  [17, 19],
  [12, 14],
  [14, 16],
  [16, 18],
  [16, 20],
  [16, 22],
  [18, 20],
  [11, 23],
  [12, 24],
  [23, 24],
  [23, 25],
  [25, 27],
  [27, 29],
  [29, 31],
  [27, 31],
  [24, 26],
  [26, 28],
  [28, 30],
  [30, 32],
  [28, 32],
];

const dotIndices = [...new Set(poseConnections.flat())];
const smoothing = {
  medianWindow: 5,
  // 5-point quadratic Savitzky-Golay coefficients. At 15 fps this uses a
  // centered 333 ms window, so it removes shimmer without visible phase lag.
  savitzkyGolay: [-3 / 35, 12 / 35, 17 / 35, 12 / 35, -3 / 35],
  smoothMix: 0.88,
};
const repBadge = {
  x: 828,
  y: 104,
  width: 252,
  height: 116,
  transitionFrame: 62,
  pulseFrames: 18,
};

function run(command, args) {
  const result = spawnSync(command, args, {
    cwd: repoRoot,
    encoding: "utf8",
    stdio: "inherit",
  });

  if (result.status !== 0) {
    throw new Error(`${command} ${args.join(" ")} failed`);
  }
}

function assertInput(filePath) {
  if (!existsSync(filePath)) {
    throw new Error(`Missing input: ${filePath}`);
  }
}

function ensureCleanDir(dirPath) {
  rmSync(dirPath, { recursive: true, force: true });
  mkdirSync(dirPath, { recursive: true });
}

function svgEscape(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function pointFor(landmark) {
  return {
    x: landmark.x * surface.width,
    y: landmark.y * scaledSourceHeight - croppedTop,
    confidence: Math.max(
      0.42,
      Math.min(1, Math.max(landmark.visibility ?? 0, landmark.presence ?? 0)),
    ),
  };
}

function clampedValue(series, index) {
  return series[Math.max(0, Math.min(series.length - 1, index))];
}

function median(values) {
  return [...values].sort((a, b) => a - b)[Math.floor(values.length / 2)];
}

function medianDespike(series) {
  const radius = Math.floor(smoothing.medianWindow / 2);

  return series.map((_value, index) =>
    median(
      Array.from({ length: smoothing.medianWindow }, (_unused, offset) =>
        clampedValue(series, index + offset - radius),
      ),
    ),
  );
}

function savitzkyGolay(series) {
  const radius = Math.floor(smoothing.savitzkyGolay.length / 2);

  return series.map((value, index) => {
    const smoothed = smoothing.savitzkyGolay.reduce(
      (sum, coefficient, coefficientIndex) =>
        sum + coefficient * clampedValue(series, index + coefficientIndex - radius),
      0,
    );

    return value * (1 - smoothing.smoothMix) + smoothed * smoothing.smoothMix;
  });
}

function smoothSeries(series) {
  return savitzkyGolay(medianDespike(series));
}

function smoothPoseFrames(frames) {
  const smoothedFrames = frames.map((frame) => ({
    ...frame,
    landmarks: frame.landmarks.map((landmark) => ({ ...landmark })),
  }));

  for (let landmarkIndex = 0; landmarkIndex < 33; landmarkIndex += 1) {
    for (const axis of ["x", "y", "z"]) {
      const smoothedAxis = smoothSeries(
        frames.map((frame) => frame.landmarks[landmarkIndex][axis]),
      );

      smoothedAxis.forEach((value, frameIndex) => {
        smoothedFrames[frameIndex].landmarks[landmarkIndex][axis] = value;
      });
    }
  }

  return smoothedFrames;
}

function lineSvg(a, b) {
  const opacity = Math.min(a.confidence, b.confidence);
  const points = `${a.x.toFixed(1)},${a.y.toFixed(1)} ${b.x.toFixed(1)},${b.y.toFixed(1)}`;

  return `
    <polyline points="${points}" fill="none" stroke="#16f3d7" stroke-width="13" stroke-linecap="round" stroke-linejoin="round" filter="url(#softGlow)" opacity="${(opacity * 0.3).toFixed(3)}" />
    <polyline points="${points}" fill="none" stroke="#dffdf8" stroke-width="5.5" stroke-linecap="round" stroke-linejoin="round" opacity="${(0.5 + opacity * 0.45).toFixed(3)}" />
  `;
}

function dotSvg(point) {
  return `
    <circle cx="${point.x.toFixed(1)}" cy="${point.y.toFixed(1)}" r="8.5" fill="#31ffdc" filter="url(#softGlow)" opacity="${(point.confidence * 0.34).toFixed(3)}" />
    <circle cx="${point.x.toFixed(1)}" cy="${point.y.toFixed(1)}" r="4.5" fill="#f7fffb" stroke="#35ffdd" stroke-width="1.7" opacity="${(0.58 + point.confidence * 0.36).toFixed(3)}" />
  `;
}

function repBadgeSvg(frameIndex) {
  const isRepCounted = frameIndex >= repBadge.transitionFrame;
  const pulseProgress = isRepCounted
    ? Math.min(1, (frameIndex - repBadge.transitionFrame) / repBadge.pulseFrames)
    : 1;
  const pulseOpacity = isRepCounted ? Math.max(0, (1 - pulseProgress) * 0.62) : 0;
  const successOpacity = isRepCounted ? 0.95 : 0;
  const restingAccentOpacity = isRepCounted ? 0.85 : 0.35;
  const count = isRepCounted ? "3" : "2";
  const countX = repBadge.x + 61;
  const countY = repBadge.y + 63;
  const pulseRadius = 39 + pulseProgress * 20;
  const infoX = repBadge.x + 132;
  const successSvg = isRepCounted
    ? `
      <rect x="${infoX}" y="${repBadge.y + 75}" width="92" height="27" rx="13.5" fill="#35f4b6" opacity="${successOpacity.toFixed(3)}" />
      <text x="${infoX + 46}" y="${repBadge.y + 94}" font-family="Arial" font-size="13.5" font-weight="800" text-anchor="middle" fill="#05221b" opacity="${successOpacity.toFixed(3)}">+1 REP</text>
    `
    : "";

  return `
    <g>
      <rect x="${repBadge.x}" y="${repBadge.y}" width="${repBadge.width}" height="${repBadge.height}" rx="18" fill="#07110f" opacity="0.86" filter="url(#badgeShadow)" />
      <rect x="${repBadge.x + 1}" y="${repBadge.y + 1}" width="${repBadge.width - 2}" height="${repBadge.height - 2}" rx="17" fill="none" stroke="#34f4d1" stroke-width="1.8" opacity="${restingAccentOpacity.toFixed(3)}" />
      <circle cx="${countX}" cy="${countY}" r="${pulseRadius.toFixed(1)}" fill="none" stroke="#35f4b6" stroke-width="${(7 - pulseProgress * 3.8).toFixed(1)}" opacity="${pulseOpacity.toFixed(3)}" />
      <circle cx="${countX}" cy="${countY}" r="39" fill="#0df0bc" opacity="${isRepCounted ? 0.17 : 0.08}" />
      <circle cx="${countX}" cy="${countY}" r="39" fill="none" stroke="#34f4d1" stroke-width="1.4" opacity="0.28" />
      <line x1="${repBadge.x + 113}" y1="${repBadge.y + 24}" x2="${repBadge.x + 113}" y2="${repBadge.y + 94}" stroke="#dffdf8" stroke-width="1" opacity="0.16" />
      <text x="${countX}" y="${countY + 17}" font-family="Arial" font-size="58" font-weight="800" text-anchor="middle" fill="#f6fffb">${count}</text>
      <text x="${infoX}" y="${repBadge.y + 35}" font-family="Arial" font-size="16" font-weight="800" letter-spacing="3.2" fill="#9af9e4" opacity="0.92">REPS</text>
      <text x="${infoX}" y="${repBadge.y + 65}" font-family="Arial" font-size="23" font-weight="800" fill="#effffb">/ 10</text>
      ${successSvg}
    </g>
  `;
}

function renderSkeletonFrame(frame, frameNumber) {
  const landmarks = frame.landmarks.map(pointFor);
  const limbSvg = poseConnections
    .map(([a, b]) => lineSvg(landmarks[a], landmarks[b]))
    .join("\n");
  const jointsSvg = dotIndices.map((index) => dotSvg(landmarks[index])).join("\n");
  const repSvg = repBadgeSvg(frameNumber);

  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="${surface.width}" height="${surface.height}" viewBox="0 0 ${surface.width} ${surface.height}">
  <title>${svgEscape(`Momentum workout skeleton frame ${frameNumber}`)}</title>
  <defs>
    <filter id="softGlow" x="-20%" y="-20%" width="140%" height="140%">
      <feGaussianBlur stdDeviation="3.5" result="blur" />
      <feColorMatrix in="blur" type="matrix" values="0 0 0 0 0.18 0 0 0 0 1 0 0 0 0 0.86 0 0 0 1 0" result="glow" />
      <feMerge>
        <feMergeNode in="glow" />
        <feMergeNode in="SourceGraphic" />
      </feMerge>
    </filter>
    <filter id="badgeShadow" x="-20%" y="-20%" width="140%" height="150%">
      <feDropShadow dx="0" dy="8" stdDeviation="10" flood-color="#000000" flood-opacity="0.38" />
    </filter>
  </defs>
  <g>
${limbSvg}
${jointsSvg}
${repSvg}
  </g>
</svg>
`;
}

function renderSkeletonFrames() {
  const frames = readFileSync(rawPoseTrace, "utf8")
    .trim()
    .split("\n")
    .map((line) => JSON.parse(line))
    .filter((frame) => frame.type === "pose" && frame.landmarks?.length >= 33)
    .slice(0, frameCount);

  if (frames.length !== frameCount) {
    throw new Error(`Expected ${frameCount} pose frames, found ${frames.length}`);
  }

  const smoothedFrames = smoothPoseFrames(frames);

  smoothedFrames.forEach((frame, index) => {
    const frameNumber = String(index + 1).padStart(4, "0");
    const svgPath = path.join(skeletonSvgDir, `frame_${frameNumber}.svg`);
    const pngPath = path.join(skeletonPngDir, `frame_${frameNumber}.png`);

    writeFileSync(svgPath, renderSkeletonFrame(frame, index), "utf8");
    run("magick", ["-background", "none", "-font", badgeFont, svgPath, pngPath]);
  });
}

function main() {
  [baseScreenshot, lungeSourceVideo, rawPoseTrace].forEach(assertInput);
  ensureCleanDir(outputRoot);
  mkdirSync(surfaceFramesDir, { recursive: true });
  mkdirSync(skeletonSvgDir, { recursive: true });
  mkdirSync(skeletonPngDir, { recursive: true });
  mkdirSync(publicProductRoot, { recursive: true });

  run("magick", [baseScreenshot, "-resize", "1800x", baseImage]);
  run("ffmpeg", [
    "-y",
    "-ss",
    String(clipStartSeconds),
    "-t",
    String(durationSeconds),
    "-i",
    lungeSourceVideo,
    "-an",
    "-vf",
    `fps=${fps},scale=${surface.width}:${surface.height}:force_original_aspect_ratio=increase,crop=${surface.width}:${surface.height},eq=brightness=-0.025:contrast=1.06:saturation=0.92`,
    "-q:v",
    "3",
    path.join(surfaceFramesDir, "frame_%04d.jpg"),
  ]);
  renderSkeletonFrames();
  run("ffmpeg", [
    "-y",
    "-loop",
    "1",
    "-framerate",
    String(fps),
    "-i",
    baseImage,
    "-framerate",
    String(fps),
    "-i",
    path.join(surfaceFramesDir, "frame_%04d.jpg"),
    "-framerate",
    String(fps),
    "-i",
    path.join(skeletonPngDir, "frame_%04d.png"),
    "-filter_complex",
    `[0:v]trim=duration=${durationSeconds},setpts=PTS-STARTPTS[base];[1:v]setpts=PTS-STARTPTS[surface];[2:v]setpts=PTS-STARTPTS[rig];[surface][rig]overlay=0:0:format=auto[tracked];[base][tracked]overlay=${surface.x}:${surface.y}:shortest=1,format=yuv420p[v]`,
    "-map",
    "[v]",
    "-r",
    String(fps),
    "-t",
    String(durationSeconds),
    masterVideo,
  ]);
  run("ffmpeg", [
    "-y",
    "-i",
    masterVideo,
    "-an",
    "-c:v",
    "libx264",
    "-preset",
    "medium",
    "-crf",
    "24",
    "-movflags",
    "+faststart",
    "-pix_fmt",
    "yuv420p",
    finalMp4,
  ]);
  run("ffmpeg", [
    "-y",
    "-i",
    masterVideo,
    "-an",
    "-c:v",
    "libvpx-vp9",
    "-b:v",
    "0",
    "-crf",
    "36",
    "-deadline",
    "good",
    "-cpu-used",
    "3",
    "-row-mt",
    "1",
    "-pix_fmt",
    "yuv420p",
    finalWebm,
  ]);
  run("ffmpeg", [
    "-y",
    "-i",
    masterVideo,
    "-frames:v",
    "1",
    "-update",
    "1",
    "-q:v",
    "3",
    posterImage,
  ]);

  console.log(`Rendered ${frameCount} frames`);
  console.log(`MP4: ${finalMp4}`);
  console.log(`WebM: ${finalWebm}`);
  console.log(`Poster: ${posterImage}`);
}

main();
