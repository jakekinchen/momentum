import { existsSync, readFileSync, readdirSync, statSync } from "fs";
import path from "path";

import motionReviewSnapshot from "@/data/motionReviewSnapshot.json";

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
  evidence: MotionReviewEvidence;
  factory: MotionFactoryReadiness;
};

export type MotionReviewData = {
  generatedAt: string;
  summary: {
    totalExercises: number;
    guideReady: number;
    validationReady: number;
    referenceCaptureRequired: number;
    playableTraces: number;
    detectorReviews: number;
    contactSheets: number;
    blockedFromGuideReady: number;
    tierCounts: Record<MotionPromotionTier, number>;
  };
  exercises: MotionReviewExercise[];
};

export type MotionPromotionTier =
  | "recommendation-only"
  | "source-candidate"
  | "detector-reviewable"
  | "avatar-demo-candidate"
  | "guide-ready"
  | "validation-ready";

export type FactoryConceptStatus = "missing" | "present" | "passed" | "invalid" | "failed";

export type MotionFactoryConcept = {
  key: string;
  label: string;
  status: FactoryConceptStatus;
  decision: string;
  reasons: string[];
  requiredFor: string[];
};

export type MotionFactoryReadiness = {
  promotionTier: MotionPromotionTier;
  tierIndex: number;
  guideReady: boolean;
  validationReady: boolean;
  guideReadyBlockers: string[];
  validationReadyBlockers: string[];
  warnings: string[];
  nextAction: string;
  currentSignals: {
    appGate: string;
    referenceStatus: string;
    captureStatus: string;
    normalizerStatus: string;
    manifestStatus: string;
    playableJsonl: boolean;
    localOnlyArtifacts: string[];
  };
  concepts: MotionFactoryConcept[];
};

export type MotionReviewEvidence = {
  capturePlan: {
    priority: number | null;
    requiredView: string;
    reason: string;
    promotionRule: string;
  };
  source: {
    kind: string;
    label: string;
    videoPath: string;
    license: string;
    attribution: string;
  };
  captureSession: {
    present: boolean;
    sourceKind: string;
    cameraView: string;
    fps: string;
    resolution: string;
    equipment: string;
    license: string;
    reviewerNotes: string;
  };
  visualReview: {
    present: boolean;
    status: string;
    evidence: string;
    reviewer: string;
    reviewedAt: string;
    failureReasons: string[];
  };
};

export type MotionMediaAsset = "contact-sheet" | "detector-video" | "source-video";

export type MotionMediaFile = {
  path: string;
  contentType: string;
};

type JsonRecord = Record<string, unknown>;

const promotionTiers: MotionPromotionTier[] = [
  "recommendation-only",
  "source-candidate",
  "detector-reviewable",
  "avatar-demo-candidate",
  "guide-ready",
  "validation-ready",
];

const passedReviewStatuses = new Set(["passed", "reviewed"]);
const passedScorecardStatuses = new Set(["passed", "reviewed"]);

const captureSessionRequiredFields = [
  "source_kind",
  "camera_view",
  "fps",
  "resolution",
  "equipment",
  "license",
  "reviewer_notes",
];

const detectorScorecardRequiredMetrics = [
  "frame_coverage",
  "mean_visibility",
  "detector_disagreement",
  "identity_flip_count",
  "temporal_jitter",
  "rejected_frame_windows",
];

const kinematicScorecardRequiredMetrics = [
  "limb_length_stability",
  "joint_angle_limits",
  "smoothness_jerk",
  "loop_boundary_delta",
  "contact_lock_delta",
  "phase_monotonicity",
];

const repoRoot = path.resolve(process.cwd(), "..");
const presetsDir = path.join(repoRoot, "Sources/CamiFitApp/Resources/Presets");
const motionDemosDir = path.join(repoRoot, "Sources/CamiFitApp/Resources/MotionDemos");
const profilePath = path.join(repoRoot, "scripts/motion_reference/exercise_motion_profiles.json");
const captureTargetsPath = path.join(repoRoot, "scripts/motion_reference/templates/next_capture_targets.json");
const appGatePath = path.join(repoRoot, "Sources/CamiFitApp/AppExerciseTrackingGate.swift");
const reviewDir = path.join(repoRoot, "tmp/motion-review");
const publicReviewDir = path.join(process.cwd(), "public/motion-review-assets");
const detectorReviewFilenames = [
  "mediapipe_trace_review.mp4",
  "mediapipe_skeleton_review.mp4",
] as const;

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

function lowerStatus(value: unknown): string {
  return typeof value === "string" ? value.trim().toLowerCase() : "";
}

function hasPresentValue(value: unknown): boolean {
  if (typeof value === "string") {
    return Boolean(value.trim());
  }
  if (Array.isArray(value)) {
    return value.length > 0;
  }
  return value !== null && value !== undefined;
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

function nestedValue(source: JsonRecord | null, keys: string[]): unknown {
  let current: JsonRecord | null = source;
  for (let index = 0; index < keys.length - 1; index += 1) {
    current = nestedRecord(current, keys[index]);
  }

  return current ? current[keys[keys.length - 1]] : undefined;
}

function numberValue(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function displayValue(value: unknown, fallback = "missing"): string {
  if (typeof value === "number" && Number.isFinite(value)) {
    return String(value);
  }
  return stringValue(value, fallback);
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

function readCapturePlans(): Map<string, JsonRecord> {
  const root = readJson(captureTargetsPath);
  const promotionRule = stringValue(root?.promotion_rule, "");
  const targets = Array.isArray(root?.targets) ? root.targets : [];
  const map = new Map<string, JsonRecord>();

  targets.forEach((target) => {
    if (!isRecord(target)) {
      return;
    }

    const exerciseId = stringValue(target.exercise_id, "");
    if (exerciseId) {
      map.set(exerciseId, { ...target, promotion_rule: promotionRule });
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

function httpMediaUrl(value: unknown): string | null {
  const candidate = stringValue(value, "");
  if (!candidate) {
    return null;
  }

  try {
    const parsed = new URL(candidate);
    return parsed.protocol === "http:" || parsed.protocol === "https:" ? parsed.toString() : null;
  } catch {
    return null;
  }
}

function sourceVideoArtifactBytes(manifest: JsonRecord | null): number | null {
  return numberValue(nestedValue(manifest, ["artifact_integrity", "source_video", "bytes"]));
}

function snapshotMediaRedirect(exerciseId: string): string | null {
  const snapshot = motionReviewSnapshot as unknown;
  if (!isRecord(snapshot) || !Array.isArray(snapshot.exercises)) {
    return null;
  }

  const exercise = snapshot.exercises.find((item): item is JsonRecord => (
    isRecord(item) && item.id === exerciseId
  ));
  const media = nestedRecord(exercise ?? null, "media");
  return httpMediaUrl(media?.sourceVideoUrl);
}

function readLinkedRecord(manifest: JsonRecord | null, inlineKey: string, pathKeys: string[]): JsonRecord | null {
  const inline = nestedRecord(manifest, inlineKey);
  if (inline) {
    return inline;
  }

  for (const key of pathKeys) {
    const value = stringValue(manifest?.[key], "");
    if (!value) {
      continue;
    }
    const resolved = resolveRepoPath(value);
    if (!resolved) {
      continue;
    }
    const linked = readJson(resolved);
    if (linked) {
      return linked;
    }
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

function localOnlyArtifactPaths(manifest: JsonRecord | null): string[] {
  if (!manifest) {
    return [];
  }

  const paths = new Set<string>();
  [
    manifest.source_video,
    manifest.raw_trace,
    manifest.output_trace,
    manifest.candidate_trace,
    manifest.golden_trace,
    manifest.capture_session_path,
    manifest.capture_session_file,
    manifest.detector_agreement_scorecard_path,
    manifest.kinematic_scorecard_path,
  ].forEach((value) => {
    if (typeof value === "string" && (value === "dist" || value.startsWith("dist/"))) {
      paths.add(value);
    }
  });

  return [...paths];
}

function reviewAssetPath(exerciseId: string, filename: string): string {
  return path.join(reviewDir, exerciseId, filename);
}

function publicReviewAssetPath(exerciseId: string, filename: string): string {
  return path.join(publicReviewDir, exerciseId, filename);
}

function publicReviewAssetUrl(exerciseId: string, filename: string): string {
  return `/motion-review-assets/${exerciseId}/${filename}`;
}

function firstExistingReviewAsset(
  exerciseId: string,
  assetPath: (id: string, filename: string) => string,
): { path: string; filename: string } | null {
  if (!safeExerciseId(exerciseId)) {
    return null;
  }

  for (const filename of detectorReviewFilenames) {
    const pathname = assetPath(exerciseId, filename);
    if (existsSync(pathname)) {
      return { path: pathname, filename };
    }
  }

  return null;
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
    const reviewAsset = firstExistingReviewAsset(exerciseId, reviewAssetPath);
    return reviewAsset ? { path: reviewAsset.path, contentType: "video/mp4" } : null;
  }

  const manifest = readJson(manifestPath(exerciseId));
  const sourceVideo = stringValue(manifest?.source_video, "");
  const resolved = sourceVideo ? resolveRepoPath(sourceVideo) : null;
  if (!resolved || !existsSync(resolved)) {
    return null;
  }

  return { path: resolved, contentType: contentTypeForPath(resolved) };
}

export function resolveMotionMediaRedirect(
  exerciseId: string,
  asset: MotionMediaAsset,
): string | null {
  if (!safeExerciseId(exerciseId) || asset !== "source-video") {
    return null;
  }

  const manifest = readJson(manifestPath(exerciseId));
  return httpMediaUrl(manifest?.source_media_url) ?? snapshotMediaRedirect(exerciseId);
}

function mediaForExercise(exerciseId: string): MotionReviewMedia {
  const manifest = readJson(manifestPath(exerciseId));
  const publicDetectorVideo = firstExistingReviewAsset(exerciseId, publicReviewAssetPath);
  const detectorVideo = resolveMotionMediaFile(exerciseId, "detector-video");
  const contactSheet = resolveMotionMediaFile(exerciseId, "contact-sheet");
  const sourceVideo = resolveMotionMediaFile(exerciseId, "source-video");
  const sourceMediaUrl = resolveMotionMediaRedirect(exerciseId, "source-video");

  return {
    detectorVideoUrl: publicDetectorVideo
      ? publicReviewAssetUrl(exerciseId, publicDetectorVideo.filename)
      : detectorVideo
        ? `/motion-review/api/media/${exerciseId}/detector-video`
        : null,
    contactSheetUrl: contactSheet
      ? `/motion-review/api/media/${exerciseId}/contact-sheet`
      : null,
    sourceVideoUrl: sourceMediaUrl ?? (
      sourceVideo
        ? `/motion-review/api/media/${exerciseId}/source-video`
        : null
    ),
    detectorVideoBytes: publicDetectorVideo
      ? statBytes(publicDetectorVideo.path)
      : detectorVideo
        ? statBytes(detectorVideo.path)
        : null,
    contactSheetBytes: contactSheet ? statBytes(contactSheet.path) : null,
    sourceVideoBytes: sourceVideo ? statBytes(sourceVideo.path) : sourceVideoArtifactBytes(manifest),
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
    return "Generate a review video so the trace can be checked on the gallery surface.";
  }
  if (gateStatus === "reference_capture_required") {
    return "Review the trace media, then either promote after strict provenance or keep recommendation-only.";
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
    missing.push("review video");
  }
  if (!media.contactSheetUrl) {
    missing.push("review contact sheet");
  }
  if (!media.sourceVideoUrl) {
    missing.push("local source video artifact");
  }
  if (gateStatus === "reference_capture_required") {
    missing.push("guide-ready promotion");
  }

  return missing;
}

function concept(
  key: string,
  label: string,
  status: FactoryConceptStatus,
  reasons: string[],
  requiredFor: string[],
  decision: string = status,
): MotionFactoryConcept {
  return {
    key,
    label,
    status,
    decision,
    reasons,
    requiredFor,
  };
}

function captureSessionConcept(manifest: JsonRecord | null): MotionFactoryConcept {
  if (!manifest) {
    return concept(
      "capture_session_metadata",
      "Capture session",
      "missing",
      ["missing_motion_manifest"],
      ["validation-ready"],
    );
  }

  const inline = readLinkedRecord(manifest, "capture_session", [
    "capture_session_path",
    "capture_session_file",
  ]);
  if (!inline) {
    return concept(
      "capture_session_metadata",
      "Capture session",
      "missing",
      ["missing_capture_session_metadata"],
      ["validation-ready"],
    );
  }

  const missingFields = captureSessionRequiredFields.filter((field) => !hasPresentValue(inline[field]));
  return concept(
    "capture_session_metadata",
    "Capture session",
    missingFields.length ? "invalid" : "present",
    missingFields.map((field) => `missing_capture_session_field:${field}`),
    ["validation-ready"],
    stringValue(inline.source_kind, missingFields.length ? "invalid" : "present"),
  );
}

function scorecardConcept(
  manifest: JsonRecord | null,
  key: string,
  label: string,
  requiredMetrics: string[],
): MotionFactoryConcept {
  if (!manifest) {
    return concept(key, label, "missing", ["missing_motion_manifest"], ["validation-ready"]);
  }

  const inline = nestedRecord(manifest, key);
  const nestedKey = key.replace(/_scorecard$/, "");
  const fromScorecards = nestedRecord(nestedRecord(manifest, "scorecards"), nestedKey);
  const payload = inline ?? fromScorecards;
  if (!payload) {
    return concept(key, label, "missing", [`missing_${key}`], ["validation-ready"]);
  }

  const status = lowerStatus(payload.status);
  const metrics = nestedRecord(payload, "metrics");
  const missingMetrics = requiredMetrics.filter((field) => !metrics || !(field in metrics));
  const reasons = [
    ...missingMetrics.map((field) => `missing_scorecard_metric:${field}`),
    ...(passedScorecardStatuses.has(status) ? [] : [`scorecard_status_not_passed:${status || "missing"}`]),
  ];

  return concept(
    key,
    label,
    reasons.length ? "invalid" : "passed",
    reasons,
    ["validation-ready"],
    status || "missing",
  );
}

function visualReviewConcept(manifest: JsonRecord | null): MotionFactoryConcept {
  if (!manifest) {
    return concept(
      "human_visual_review_decision",
      "Human visual review",
      "missing",
      ["missing_motion_manifest"],
      ["guide-ready", "validation-ready"],
      "missing",
    );
  }

  const visualReview = readLinkedRecord(manifest, "visual_review", [
    "visual_review_path",
    "visual_review_file",
  ]);
  if (!visualReview) {
    return concept(
      "human_visual_review_decision",
      "Human visual review",
      "missing",
      ["missing_visual_review_decision"],
      ["guide-ready", "validation-ready"],
      "missing",
    );
  }

  const decision = lowerStatus(visualReview.status);
  const reasons = [
    ...(passedReviewStatuses.has(decision)
      ? []
      : [`visual_review_status_not_passed:${decision || "missing"}`]),
    ...(stringValue(visualReview.evidence, "") ? [] : ["missing_visual_review_evidence"]),
  ];
  const status = decision === "failed" ? "failed" : reasons.length ? "invalid" : "passed";
  return concept(
    "human_visual_review_decision",
    "Human visual review",
    status,
    reasons,
    ["guide-ready", "validation-ready"],
    decision || "missing",
  );
}

function formatResolution(value: unknown): string {
  if (isRecord(value)) {
    const width = numberValue(value.width);
    const height = numberValue(value.height);
    if (width && height) {
      return `${width}x${height}`;
    }
  }
  return stringValue(value, "missing");
}

function evidenceForExercise(
  manifest: JsonRecord | null,
  capturePlan: JsonRecord | null,
): MotionReviewEvidence {
  const captureSession = readLinkedRecord(manifest, "capture_session", [
    "capture_session_path",
    "capture_session_file",
  ]);
  const visualReview = readLinkedRecord(manifest, "visual_review", [
    "visual_review_path",
    "visual_review_file",
  ]);
  const failureReasons = Array.isArray(visualReview?.failure_reasons)
    ? visualReview.failure_reasons.filter((item): item is string => typeof item === "string")
    : [];

  return {
    capturePlan: {
      priority: numberValue(capturePlan?.capture_priority),
      requiredView: stringValue(capturePlan?.required_view, "missing"),
      reason: stringValue(capturePlan?.reason, "missing"),
      promotionRule: stringValue(capturePlan?.promotion_rule, "missing"),
    },
    source: {
      kind: stringValue(manifest?.source_kind, "missing"),
      label: stringValue(manifest?.source_label, "missing"),
      videoPath: stringValue(manifest?.source_video, "missing"),
      license: stringValue(manifest?.source_license, "missing"),
      attribution: stringValue(manifest?.source_attribution, "missing"),
    },
    captureSession: {
      present: Boolean(captureSession),
      sourceKind: stringValue(captureSession?.source_kind, "missing"),
      cameraView: stringValue(captureSession?.camera_view, "missing"),
      fps: displayValue(captureSession?.fps),
      resolution: formatResolution(captureSession?.resolution),
      equipment: stringValue(captureSession?.equipment, "missing"),
      license: stringValue(captureSession?.license, "missing"),
      reviewerNotes: stringValue(captureSession?.reviewer_notes, "missing"),
    },
    visualReview: {
      present: Boolean(visualReview),
      status: stringValue(visualReview?.status, "missing"),
      evidence: stringValue(visualReview?.evidence, "missing"),
      reviewer: stringValue(visualReview?.reviewer, "missing"),
      reviewedAt: stringValue(visualReview?.reviewed_at, "missing"),
      failureReasons,
    },
  };
}

function runtimeValidationConcept(manifest: JsonRecord | null): MotionFactoryConcept {
  if (!manifest) {
    return concept(
      "runtime_validation_set",
      "Runtime validation",
      "missing",
      ["missing_motion_manifest"],
      ["validation-ready"],
    );
  }

  const payload = nestedRecord(manifest, "runtime_validation_set") ?? nestedRecord(manifest, "validation_set");
  if (!payload) {
    return concept(
      "runtime_validation_set",
      "Runtime validation",
      "missing",
      ["missing_runtime_validation_set"],
      ["validation-ready"],
    );
  }

  const status = lowerStatus(payload.status);
  const clipCount = numberValue(payload.clip_count);
  const reasons = [
    ...(passedScorecardStatuses.has(status)
      ? []
      : [`runtime_validation_set_status_not_passed:${status || "missing"}`]),
    ...(clipCount !== null && clipCount >= 5
      ? []
      : ["runtime_validation_set_requires_at_least_5_clips"]),
  ];
  return concept(
    "runtime_validation_set",
    "Runtime validation",
    reasons.length ? "invalid" : "passed",
    reasons,
    ["validation-ready"],
    status || "missing",
  );
}

function factoryConcepts(manifest: JsonRecord | null): MotionFactoryConcept[] {
  return [
    captureSessionConcept(manifest),
    scorecardConcept(
      manifest,
      "detector_agreement_scorecard",
      "Detector agreement",
      detectorScorecardRequiredMetrics,
    ),
    scorecardConcept(
      manifest,
      "kinematic_scorecard",
      "Kinematic scorecard",
      kinematicScorecardRequiredMetrics,
    ),
    visualReviewConcept(manifest),
    runtimeValidationConcept(manifest),
  ];
}

function manifestHasAny(manifest: JsonRecord | null, fields: string[]): boolean {
  if (!manifest) {
    return false;
  }

  return fields.some((field) => hasPresentValue(nestedValue(manifest, field.split("."))));
}

function profileHasSourceSearch(profile: JsonRecord | null): boolean {
  if (!profile) {
    return false;
  }

  const capture = nestedRecord(profile, "capture");
  return [profile, capture].some((source) => {
    if (!source) {
      return false;
    }

    return (
      Array.isArray(source.rejected_candidates) ||
      isRecord(source.rejected_sources) ||
      stringValue(source.source_page, "") !== "" ||
      stringValue(source.source_media_url, "") !== "" ||
      stringValue(source.clip, "") !== ""
    );
  });
}

function hasSourceCandidate(manifest: JsonRecord | null, profile: JsonRecord | null, hasProfile: boolean): boolean {
  return (
    manifestHasAny(manifest, [
      "source_page",
      "source_media_url",
      "source_video",
      "source_label",
      "rejected_candidates",
      "rejected_sources",
    ]) ||
    profileHasSourceSearch(profile) ||
    hasProfile
  );
}

function hasDetectorReviewableArtifact(manifest: JsonRecord | null): boolean {
  return manifestHasAny(manifest, [
    "raw_trace",
    "raw_review",
    "raw_review_sheet",
    "detector_agreement_scorecard",
    "detector_agreement_scorecard_path",
    "scorecards.detector_agreement",
  ]);
}

function hasAvatarCandidate(
  trace: MotionFrame[],
  manifest: JsonRecord | null,
): boolean {
  return (
    trace.length > 0 ||
    manifestHasAny(manifest, [
      "output_trace",
      "viewer_command",
      "kinematic_scorecard",
      "kinematic_scorecard_path",
      "scorecards.kinematic",
    ])
  );
}

function guideReadyBlockers({
  gateStatus,
  trace,
  demoStatus,
  manifest,
  hasProfile,
  concepts,
  captureStatus,
  manifestStatus,
}: {
  gateStatus: MotionReviewExercise["gateStatus"];
  trace: MotionFrame[];
  demoStatus: string;
  manifest: JsonRecord | null;
  hasProfile: boolean;
  concepts: MotionFactoryConcept[];
  captureStatus: string;
  manifestStatus: string;
}): string[] {
  const blockers = new Set<string>();
  if (gateStatus === "reference_capture_required") {
    blockers.add("reference_capture_required_gate");
  }
  if (!hasProfile) {
    blockers.add("missing_motion_profile");
  }
  if (trace.length > 0 && demoStatus === "invalid") {
    blockers.add("invalid_playable_jsonl");
  }
  if (gateStatus === "guide_ready" && !trace.length) {
    blockers.add("guide_ready_missing_playable_jsonl");
  }
  if (!manifest && (trace.length > 0 || gateStatus === "guide_ready")) {
    blockers.add("missing_motion_manifest");
  }

  const visual = concepts.find((item) => item.key === "human_visual_review_decision");
  if (visual && (hasAvatarCandidate(trace, manifest) || gateStatus === "guide_ready")) {
    if (visual.status === "failed") {
      blockers.add("visual_review_failed");
    } else if (visual.status !== "passed") {
      visual.reasons.forEach((reason) => blockers.add(reason));
    }
  }

  const normalizedManifestStatus = manifestStatus.toLowerCase();
  if (normalizedManifestStatus.startsWith("blocked") || normalizedManifestStatus.startsWith("rejected")) {
    blockers.add(`manifest_acceptance_not_promotable:${normalizedManifestStatus}`);
  }
  if (captureStatus === "pending_license_review") {
    blockers.add("pending_source_license_review");
  }
  if (captureStatus === "pending_first_party_capture" || captureStatus === "pending_licensed_reference_clip") {
    blockers.add(captureStatus);
  }

  return [...blockers].sort();
}

function validationReadyBlockers({
  promotionTier,
  guideBlockers,
  concepts,
  localOnlyArtifacts,
}: {
  promotionTier: MotionPromotionTier;
  guideBlockers: string[];
  concepts: MotionFactoryConcept[];
  localOnlyArtifacts: string[];
}): string[] {
  const blockers = new Set<string>();
  if (promotionTier !== "guide-ready" || guideBlockers.length > 0) {
    blockers.add("not_guide_ready");
  }

  concepts.forEach((item) => {
    const passes = item.status === "passed" || item.status === "present";
    if (!passes) {
      item.reasons.forEach((reason) => blockers.add(reason));
    }
  });

  if (localOnlyArtifacts.length > 0) {
    blockers.add("local_only_source_chain_artifacts");
  }

  return [...blockers].sort();
}

function promotionTier({
  gateStatus,
  trace,
  manifest,
  profile,
  hasProfile,
  guideBlockers,
}: {
  gateStatus: MotionReviewExercise["gateStatus"];
  trace: MotionFrame[];
  manifest: JsonRecord | null;
  profile: JsonRecord | null;
  hasProfile: boolean;
  guideBlockers: string[];
}): MotionPromotionTier {
  if (gateStatus === "guide_ready" && guideBlockers.length === 0) {
    return "guide-ready";
  }
  if (hasAvatarCandidate(trace, manifest)) {
    return "avatar-demo-candidate";
  }
  if (hasDetectorReviewableArtifact(manifest)) {
    return "detector-reviewable";
  }
  if (hasSourceCandidate(manifest, profile, hasProfile)) {
    return "source-candidate";
  }
  return "recommendation-only";
}

function nextFactoryAction(
  tier: MotionPromotionTier,
  guideBlockers: string[],
  validationBlockers: string[],
  nextReview: string,
): string {
  if (tier === "validation-ready") {
    return "Ready for app guide claims and validation claims. Keep monitoring runtime clips as the exercise ships.";
  }
  if (tier === "guide-ready") {
    if (validationBlockers.includes("local_only_source_chain_artifacts")) {
      return "Keep app guide-ready, then backfill durable artifact storage, capture-session metadata, detector agreement, kinematic scoring, and runtime validation clips.";
    }
    return "Backfill factory scorecards and validation clips before calling this validation-ready.";
  }
  if (guideBlockers.includes("visual_review_failed")) {
    return "Replace the failed avatar/source candidate and record a new passed visual-review decision before guide promotion.";
  }
  if (guideBlockers.includes("reference_capture_required_gate")) {
    return nextReview;
  }
  if (guideBlockers.length > 0) {
    return `Resolve guide blockers: ${guideBlockers.join(", ")}`;
  }
  return nextReview;
}

function buildFactoryReadiness({
  gateStatus,
  trace,
  manifest,
  profile,
  hasProfile,
  demoStatus,
  captureStatus,
  normalizerStatus,
  manifestStatus,
  referenceStatus,
  localOnlyArtifacts,
  missing,
  nextReview,
}: {
  gateStatus: MotionReviewExercise["gateStatus"];
  trace: MotionFrame[];
  manifest: JsonRecord | null;
  profile: JsonRecord | null;
  hasProfile: boolean;
  demoStatus: string;
  captureStatus: string;
  normalizerStatus: string;
  manifestStatus: string;
  referenceStatus: string;
  localOnlyArtifacts: string[];
  missing: string[];
  nextReview: string;
}): MotionFactoryReadiness {
  const concepts = factoryConcepts(manifest);
  const guideBlockers = guideReadyBlockers({
    gateStatus,
    trace,
    demoStatus,
    manifest,
    hasProfile,
    concepts,
    captureStatus,
    manifestStatus,
  });
  const tier = promotionTier({
    gateStatus,
    trace,
    manifest,
    profile,
    hasProfile,
    guideBlockers,
  });
  const validationBlockers = validationReadyBlockers({
    promotionTier: tier,
    guideBlockers,
    concepts,
    localOnlyArtifacts,
  });
  const validationReady = tier === "guide-ready" && validationBlockers.length === 0;
  const finalTier = validationReady ? "validation-ready" : tier;

  return {
    promotionTier: finalTier,
    tierIndex: promotionTiers.indexOf(finalTier),
    guideReady: tier === "guide-ready" && guideBlockers.length === 0,
    validationReady,
    guideReadyBlockers: guideBlockers,
    validationReadyBlockers: validationBlockers,
    warnings: missing,
    nextAction: nextFactoryAction(finalTier, guideBlockers, validationBlockers, nextReview),
    currentSignals: {
      appGate: gateStatus,
      referenceStatus,
      captureStatus,
      normalizerStatus,
      manifestStatus,
      playableJsonl: trace.length > 0,
      localOnlyArtifacts,
    },
    concepts,
  };
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

function snapshotMotionReviewData(): MotionReviewData | null {
  const snapshot = motionReviewSnapshot as unknown as MotionReviewData;
  return Array.isArray(snapshot.exercises) && snapshot.exercises.length ? snapshot : null;
}

function getFileSystemMotionReviewData(): MotionReviewData {
  const presets = readPresets();
  const profiles = readProfiles();
  const capturePlans = readCapturePlans();
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
      ...capturePlans.keys(),
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
    const capturePlan = capturePlans.get(id) ?? null;
    const manifest = readJson(manifestPath(id));
    const trace = readTrace(id);
    const stats = traceStats(trace);
    const media = mediaForExercise(id);
    const evidence = evidenceForExercise(manifest, capturePlan);
    const gateStatus = guideReady.has(id)
      ? "guide_ready"
      : referenceCaptureRequired.has(id)
        ? "reference_capture_required"
        : "unclassified";
    const sourceKind = stringValue(manifest?.source_kind, stringValue(profile?.viewer_status, "missing"));
    const acceptanceStatus = stringValue(manifest?.acceptance_status, "missing");
    const referenceStatus = stringValue(manifest?.reference_status, stringValue(profile?.viewer_status, "missing"));
    const capture = nestedRecord(profile, "capture");
    const normalizer = nestedRecord(profile, "normalizer");
    const setup = nestedRecord(preset, "setup");
    const demoStatus = trace.length ? "ok" : "missing";
    const missing = collectMissing(gateStatus, trace, media, manifest);
    const nextReview = nextReviewForExercise(
      gateStatus,
      trace.length > 0,
      Boolean(media.detectorVideoUrl),
      acceptanceStatus,
    );
    const captureStatus = stringValue(capture?.status, "missing");
    const normalizerStatus = stringValue(normalizer?.status, "missing");
    const localOnlyArtifacts = localOnlyArtifactPaths(manifest);
    const factory = buildFactoryReadiness({
      gateStatus,
      trace,
      manifest,
      profile,
      hasProfile: Boolean(profile),
      demoStatus,
      captureStatus,
      normalizerStatus,
      manifestStatus: acceptanceStatus,
      referenceStatus,
      localOnlyArtifacts,
      missing,
      nextReview,
    });

    return {
      id,
      name: stringValue(preset?.name, titleFromId(id)),
      gateStatus,
      sourceKind,
      acceptanceStatus,
      measurementStatus: stringValue(profile?.measurement_status, "missing"),
      captureStatus,
      requiredView: stringValue(setup?.required_view, stringValue(capture?.required_view, "missing")),
      requiredLandmarks: stringArray(setup?.required_landmarks),
      formCues: formCues(preset),
      target: targetLabel(preset),
      trace,
      ...stats,
      media,
      validation: buildValidation(manifest, profile),
      missing,
      nextReview,
      evidence,
      factory,
    };
  });

  exercises.sort((left, right) => {
    return exerciseSortRank(left) - exerciseSortRank(right) || left.name.localeCompare(right.name);
  });

  const tierCounts = promotionTiers.reduce(
    (counts, tier) => {
      counts[tier] = exercises.filter((exercise) => exercise.factory.promotionTier === tier).length;
      return counts;
    },
    {} as Record<MotionPromotionTier, number>,
  );

  return {
    generatedAt: new Date().toISOString(),
    summary: {
      totalExercises: exercises.length,
      guideReady: exercises.filter((exercise) => exercise.factory.guideReady).length,
      validationReady: exercises.filter((exercise) => exercise.factory.validationReady).length,
      referenceCaptureRequired: exercises.filter(
        (exercise) => exercise.gateStatus === "reference_capture_required",
      ).length,
      playableTraces: exercises.filter((exercise) => exercise.trace.length > 0).length,
      detectorReviews: exercises.filter((exercise) => Boolean(exercise.media.detectorVideoUrl)).length,
      contactSheets: exercises.filter((exercise) => Boolean(exercise.media.contactSheetUrl)).length,
      blockedFromGuideReady: exercises.filter(
        (exercise) => exercise.factory.guideReadyBlockers.length > 0,
      ).length,
      tierCounts,
    },
    exercises,
  };
}

export function getMotionReviewData(): MotionReviewData {
  const data = getFileSystemMotionReviewData();
  return data.exercises.length ? data : snapshotMotionReviewData() ?? data;
}
