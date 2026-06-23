import { existsSync, readFileSync, readdirSync, statSync } from "fs";
import path from "path";

export type Landmark = {
  x: number;
  y: number;
  z?: number;
  visibility?: number;
  presence?: number;
};

export type MotionFrame = {
  frame_id?: number;
  timestamp_ms?: number;
  image_size?: [number, number];
  landmarks: Record<string, Landmark>;
};

export type MotionReviewMedia = {
  detectorVideoUrl: string | null;
  contactSheetUrl: string | null;
  sourceVideoUrl: string | null;
  detectorVideoBytes: number | null;
  contactSheetBytes: number | null;
  sourceVideoBytes: number | null;
};

export type MotionReviewExercise = {
  id: string;
  name: string;
  gateStatus: "guide_ready" | "reference_capture_required" | "unclassified";
  sourceKind: string;
  acceptanceStatus: string;
  measurementStatus: string;
  captureStatus: string;
  requiredView: string;
  requiredLandmarks: string[];
  formCues: string[];
  target: string;
  trace: MotionFrame[];
  frameCount: number;
  durationMs: number;
  landmarkCount: number;
  media: MotionReviewMedia;
  validation: Array<{
    label: string;
    value: string;
    status: "pass" | "warn" | "missing" | "info";
  }>;
  missing: string[];
  nextReview: string;
};

export type MotionReviewData = {
  generatedAt: string;
  summary: {
    totalExercises: number;
    guideReady: number;
    referenceCaptureRequired: number;
    playableTraces: number;
    detectorReviews: number;
    contactSheets: number;
  };
  exercises: MotionReviewExercise[];
};

export type MotionMediaAsset = "contact-sheet" | "detector-video" | "source-video";

export type MotionMediaFile = {
  path: string;
  contentType: string;
};

type JsonRecord = Record<string, unknown>;

const repoRoot = path.resolve(process.cwd(), "..");
const presetsDir = path.join(repoRoot, "Sources/CamiFitApp/Resources/Presets");
const motionDemosDir = path.join(repoRoot, "Sources/CamiFitApp/Resources/MotionDemos");
const profilePath = path.join(repoRoot, "scripts/motion_reference/exercise_motion_profiles.json");
const appGatePath = path.join(repoRoot, "Sources/CamiFitApp/AppExerciseTrackingGate.swift");
const reviewDir = path.join(repoRoot, "tmp/motion-review");

function isRecord(value: unknown): value is JsonRecord {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function readJson(pathname: string): JsonRecord | null {
  if (!existsSync(pathname)) {
    return null;
  }

  try {
    const parsed: unknown = JSON.parse(readFileSync(pathname, "utf8"));
    return isRecord(parsed) ? parsed : null;
  } catch {
    return null;
  }
}

function stringValue(value: unknown, fallback = "missing"): string {
  return typeof value === "string" && value.trim() ? value.trim() : fallback;
}

function stringArray(value: unknown): string[] {
  if (!Array.isArray(value)) {
    return [];
  }

  return value.filter((item): item is string => typeof item === "string");
}

function nestedRecord(source: JsonRecord | null, key: string): JsonRecord | null {
  if (!source) {
    return null;
  }

  const value = source[key];
  return isRecord(value) ? value : null;
}

function nestedString(source: JsonRecord | null, keys: string[], fallback = "missing"): string {
  let current: JsonRecord | null = source;
  for (let index = 0; index < keys.length - 1; index += 1) {
    current = nestedRecord(current, keys[index]);
  }

  return current ? stringValue(current[keys[keys.length - 1]], fallback) : fallback;
}

function numberValue(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function readProfiles(): Map<string, JsonRecord> {
  const root = readJson(profilePath);
  const profiles = Array.isArray(root?.profiles) ? root.profiles : [];
  const map = new Map<string, JsonRecord>();

  profiles.forEach((profile) => {
    if (!isRecord(profile)) {
      return;
    }

    const exerciseId = stringValue(profile.exercise_id, "");
    if (exerciseId) {
      map.set(exerciseId, profile);
    }
  });

  return map;
}

function readPresets(): Map<string, JsonRecord> {
  const map = new Map<string, JsonRecord>();
  if (!existsSync(presetsDir)) {
    return map;
  }

  readdirSync(presetsDir)
    .filter((filename) => filename.endsWith(".json"))
    .forEach((filename) => {
      const preset = readJson(path.join(presetsDir, filename));
      const id = stringValue(preset?.id, filename.replace(/\.json$/, ""));
      if (preset && id) {
        map.set(id, preset);
      }
    });

  return map;
}

function readSwiftSet(setName: string): Set<string> {
  if (!existsSync(appGatePath)) {
    return new Set();
  }

  const source = readFileSync(appGatePath, "utf8");
  const escapedName = setName.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const match = source.match(new RegExp(`static let ${escapedName}: Set<String> = \\[([\\s\\S]*?)\\]`));
  if (!match) {
    return new Set();
  }

  return new Set([...match[1].matchAll(/"([^"]+)"/g)].map((item) => item[1]));
}

function statBytes(pathname: string): number | null {
  if (!existsSync(pathname)) {
    return null;
  }

  try {
    return statSync(pathname).size;
  } catch {
    return null;
  }
}

function safeExerciseId(exerciseId: string): boolean {
  return /^[a-z0-9_]+$/.test(exerciseId);
}

function resolveRepoPath(relativePath: string): string | null {
  const resolved = path.resolve(repoRoot, relativePath);
  if (resolved === repoRoot || resolved.startsWith(`${repoRoot}${path.sep}`)) {
    return resolved;
  }

  return null;
}

function contentTypeForPath(pathname: string): string {
  const extension = path.extname(pathname).toLowerCase();
  if (extension === ".png") {
    return "image/png";
  }
  if (extension === ".jpg" || extension === ".jpeg") {
    return "image/jpeg";
  }
  if (extension === ".webm") {
    return "video/webm";
  }
  if (extension === ".mp4" || extension === ".m4v") {
    return "video/mp4";
  }
  return "application/octet-stream";
}

function manifestPath(exerciseId: string): string {
  return path.join(motionDemosDir, `${exerciseId}.manifest.json`);
}

function tracePath(exerciseId: string): string {
  return path.join(motionDemosDir, `${exerciseId}.jsonl`);
}

function reviewAssetPath(exerciseId: string, filename: string): string {
  return path.join(reviewDir, exerciseId, filename);
}

export function resolveMotionMediaFile(
  exerciseId: string,
  asset: MotionMediaAsset,
): MotionMediaFile | null {
  if (!safeExerciseId(exerciseId)) {
    return null;
  }

  if (asset === "contact-sheet") {
    const pathname = reviewAssetPath(exerciseId, "contact_sheet.png");
    return existsSync(pathname) ? { path: pathname, contentType: "image/png" } : null;
  }

  if (asset === "detector-video") {
    const pathname = reviewAssetPath(exerciseId, "mediapipe_skeleton_review.mp4");
    return existsSync(pathname) ? { path: pathname, contentType: "video/mp4" } : null;
  }

  const manifest = readJson(manifestPath(exerciseId));
  const sourceVideo = stringValue(manifest?.source_video, "");
  const resolved = sourceVideo ? resolveRepoPath(sourceVideo) : null;
  if (!resolved || !existsSync(resolved)) {
    return null;
  }

  return { path: resolved, contentType: contentTypeForPath(resolved) };
}

function mediaForExercise(exerciseId: string): MotionReviewMedia {
  const detectorVideo = resolveMotionMediaFile(exerciseId, "detector-video");
  const contactSheet = resolveMotionMediaFile(exerciseId, "contact-sheet");
  const sourceVideo = resolveMotionMediaFile(exerciseId, "source-video");

  return {
    detectorVideoUrl: detectorVideo
      ? `/motion-review/api/media/${exerciseId}/detector-video`
      : null,
    contactSheetUrl: contactSheet
      ? `/motion-review/api/media/${exerciseId}/contact-sheet`
      : null,
    sourceVideoUrl: sourceVideo
      ? `/motion-review/api/media/${exerciseId}/source-video`
      : null,
    detectorVideoBytes: detectorVideo ? statBytes(detectorVideo.path) : null,
    contactSheetBytes: contactSheet ? statBytes(contactSheet.path) : null,
    sourceVideoBytes: sourceVideo ? statBytes(sourceVideo.path) : null,
  };
}

function readTrace(exerciseId: string): MotionFrame[] {
  const pathname = tracePath(exerciseId);
  if (!existsSync(pathname)) {
    return [];
  }

  return readFileSync(pathname, "utf8")
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean)
    .flatMap((line) => {
      try {
        const parsed: unknown = JSON.parse(line);
        if (!isRecord(parsed) || !isRecord(parsed.landmarks)) {
          return [];
        }

        return [
          {
            frame_id: numberValue(parsed.frame_id) ?? undefined,
            timestamp_ms: numberValue(parsed.timestamp_ms) ?? undefined,
            image_size: Array.isArray(parsed.image_size)
              ? [Number(parsed.image_size[0]), Number(parsed.image_size[1])]
              : undefined,
            landmarks: parsed.landmarks as Record<string, Landmark>,
          },
        ];
      } catch {
        return [];
      }
    });
}

function traceStats(trace: MotionFrame[]) {
  const firstTimestamp = trace[0]?.timestamp_ms ?? 0;
  const lastTimestamp = trace[trace.length - 1]?.timestamp_ms ?? firstTimestamp;
  const landmarkCount = trace.reduce(
    (current, frame) => Math.max(current, Object.keys(frame.landmarks).length),
    0,
  );

  return {
    frameCount: trace.length,
    durationMs: Math.max(0, lastTimestamp - firstTimestamp),
    landmarkCount,
  };
}

function validationStatus(value: string): "pass" | "warn" | "missing" | "info" {
  const normalized = value.toLowerCase();
  if (normalized.includes("pass") || normalized.includes("accept")) {
    return "pass";
  }
  if (normalized === "missing" || normalized.includes("not_applicable")) {
    return "missing";
  }
  if (normalized.includes("fail") || normalized.includes("blocked") || normalized.includes("pending")) {
    return "warn";
  }
  return "info";
}

function buildValidation(manifest: JsonRecord | null, profile: JsonRecord | null) {
  const acceptanceStatus = stringValue(manifest?.acceptance_status, "missing");
  const visualReview = nestedString(manifest, ["visual_review", "status"], "missing");
  const engineReplay = nestedString(manifest, ["engine_replay", "status"], "missing");
  const liveAppReview = nestedString(manifest, ["live_app_review", "status"], "missing");
  const measurementStatus = stringValue(profile?.measurement_status, "missing");

  return [
    {
      label: "Manifest",
      value: acceptanceStatus,
      status: validationStatus(acceptanceStatus),
    },
    {
      label: "Visual review",
      value: visualReview,
      status: validationStatus(visualReview),
    },
    {
      label: "Engine replay",
      value: engineReplay,
      status: validationStatus(engineReplay),
    },
    {
      label: "Live app",
      value: liveAppReview,
      status: validationStatus(liveAppReview),
    },
    {
      label: "Measurement",
      value: measurementStatus,
      status: validationStatus(measurementStatus),
    },
  ] satisfies MotionReviewExercise["validation"];
}

function nextReviewForExercise(
  gateStatus: MotionReviewExercise["gateStatus"],
  hasTrace: boolean,
  hasDetectorVideo: boolean,
  acceptanceStatus: string,
): string {
  if (!hasTrace) {
    return "Capture or normalize a playable JSONL trace before judging the app motion.";
  }
  if (!hasDetectorVideo) {
    return "Generate a MediaPipe detector review video so the trace can be compared against source detection.";
  }
  if (gateStatus === "reference_capture_required") {
    return "Review detector media, then either promote after strict provenance or keep recommendation-only.";
  }
  if (!acceptanceStatus.toLowerCase().includes("accepted")) {
    return "Reconcile the manifest acceptance status before release claims.";
  }
  return "Phone-review the 3D loop and detector clip for anatomy, phase, contact, and rep-count consistency.";
}

function collectMissing(
  gateStatus: MotionReviewExercise["gateStatus"],
  trace: MotionFrame[],
  media: MotionReviewMedia,
  manifest: JsonRecord | null,
): string[] {
  const missing: string[] = [];

  if (!trace.length) {
    missing.push("playable JSONL");
  }
  if (!manifest) {
    missing.push("motion manifest");
  }
  if (!media.detectorVideoUrl) {
    missing.push("detector review video");
  }
  if (!media.contactSheetUrl) {
    missing.push("detector contact sheet");
  }
  if (!media.sourceVideoUrl) {
    missing.push("local source video artifact");
  }
  if (gateStatus === "reference_capture_required") {
    missing.push("guide-ready promotion");
  }

  return missing;
}

function targetLabel(preset: JsonRecord | null): string {
  const rep = nestedRecord(preset, "rep");
  const hold = nestedRecord(preset, "hold");
  const set = nestedRecord(preset, "set");
  const targetReps = numberValue(set?.target_reps);

  if (targetReps !== null) {
    return `${targetReps} reps`;
  }
  if (rep) {
    return "rep-based";
  }
  if (hold) {
    return "hold-based";
  }
  return "not specified";
}

function formCues(preset: JsonRecord | null): string[] {
  const rules = Array.isArray(preset?.form_rules) ? preset.form_rules : [];
  return rules
    .filter(isRecord)
    .map((rule) => stringValue(rule.cue, ""))
    .filter(Boolean);
}

function titleFromId(exerciseId: string): string {
  return exerciseId
    .split("_")
    .filter(Boolean)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ");
}

function exerciseSortRank(exercise: MotionReviewExercise): number {
  if (exercise.trace.length && exercise.media.detectorVideoUrl) {
    return 0;
  }
  if (exercise.gateStatus === "guide_ready" && exercise.trace.length) {
    return 1;
  }
  if (exercise.media.detectorVideoUrl || exercise.media.contactSheetUrl) {
    return 2;
  }
  if (exercise.gateStatus === "guide_ready") {
    return 3;
  }
  return 4;
}

export function getMotionReviewData(): MotionReviewData {
  const presets = readPresets();
  const profiles = readProfiles();
  const guideReady = readSwiftSet("guideReadyPresetIDs");
  const referenceCaptureRequired = readSwiftSet("referenceCaptureRequiredPresetIDs");
  const playableIds = existsSync(motionDemosDir)
    ? new Set(
        readdirSync(motionDemosDir)
          .filter((filename) => filename.endsWith(".jsonl"))
          .map((filename) => filename.replace(/\.jsonl$/, "")),
      )
    : new Set<string>();
  const manifestIds = existsSync(motionDemosDir)
    ? new Set(
        readdirSync(motionDemosDir)
          .filter((filename) => filename.endsWith(".manifest.json"))
          .map((filename) => filename.replace(/\.manifest\.json$/, "")),
      )
    : new Set<string>();
  const reviewIds = existsSync(reviewDir)
    ? new Set(
        readdirSync(reviewDir, { withFileTypes: true })
          .filter((entry) => entry.isDirectory() && safeExerciseId(entry.name))
          .map((entry) => entry.name),
      )
    : new Set<string>();
  const exerciseIds = [
    ...new Set([
      ...presets.keys(),
      ...profiles.keys(),
      ...guideReady,
      ...referenceCaptureRequired,
      ...playableIds,
      ...manifestIds,
      ...reviewIds,
    ]),
  ].sort();

  const exercises = exerciseIds.map((id): MotionReviewExercise => {
    const preset = presets.get(id) ?? null;
    const profile = profiles.get(id) ?? null;
    const manifest = readJson(manifestPath(id));
    const trace = readTrace(id);
    const stats = traceStats(trace);
    const media = mediaForExercise(id);
    const gateStatus = guideReady.has(id)
      ? "guide_ready"
      : referenceCaptureRequired.has(id)
        ? "reference_capture_required"
        : "unclassified";
    const sourceKind = stringValue(manifest?.source_kind, stringValue(profile?.viewer_status, "missing"));
    const acceptanceStatus = stringValue(manifest?.acceptance_status, "missing");
    const capture = nestedRecord(profile, "capture");
    const setup = nestedRecord(preset, "setup");

    return {
      id,
      name: stringValue(preset?.name, titleFromId(id)),
      gateStatus,
      sourceKind,
      acceptanceStatus,
      measurementStatus: stringValue(profile?.measurement_status, "missing"),
      captureStatus: stringValue(capture?.status, "missing"),
      requiredView: stringValue(setup?.required_view, stringValue(capture?.required_view, "missing")),
      requiredLandmarks: stringArray(setup?.required_landmarks),
      formCues: formCues(preset),
      target: targetLabel(preset),
      trace,
      ...stats,
      media,
      validation: buildValidation(manifest, profile),
      missing: collectMissing(gateStatus, trace, media, manifest),
      nextReview: nextReviewForExercise(
        gateStatus,
        trace.length > 0,
        Boolean(media.detectorVideoUrl),
        acceptanceStatus,
      ),
    };
  });

  exercises.sort((left, right) => {
    return exerciseSortRank(left) - exerciseSortRank(right) || left.name.localeCompare(right.name);
  });

  return {
    generatedAt: new Date().toISOString(),
    summary: {
      totalExercises: exercises.length,
      guideReady: exercises.filter((exercise) => exercise.gateStatus === "guide_ready").length,
      referenceCaptureRequired: exercises.filter(
        (exercise) => exercise.gateStatus === "reference_capture_required",
      ).length,
      playableTraces: exercises.filter((exercise) => exercise.trace.length > 0).length,
      detectorReviews: exercises.filter((exercise) => Boolean(exercise.media.detectorVideoUrl)).length,
      contactSheets: exercises.filter((exercise) => Boolean(exercise.media.contactSheetUrl)).length,
    },
    exercises,
  };
}
