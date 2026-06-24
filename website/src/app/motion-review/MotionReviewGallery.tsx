"use client";

import {
  Activity,
  AlertTriangle,
  CheckCircle2,
  ChevronLeft,
  Circle,
  Film,
  Gauge,
  ImageIcon,
  Pause,
  Play,
  RotateCcw,
  Search,
  ShieldCheck,
  SlidersHorizontal,
  Video,
} from "lucide-react";
import Image from "next/image";
import Link from "next/link";
import { type ReactNode, useEffect, useMemo, useRef, useState } from "react";

import type {
  Landmark,
  MotionFrame,
  MotionReviewData,
  MotionReviewExercise,
} from "@/lib/motionReview";

type GalleryFilter = "all" | "guide_ready" | "validation_ready" | "detector" | "missing";

type ProjectedPoint = {
  x: number;
  y: number;
  depth: number;
};

const filters: Array<{ id: GalleryFilter; label: string }> = [
  { id: "all", label: "All" },
  { id: "guide_ready", label: "Guide-ready" },
  { id: "validation_ready", label: "Validation-ready" },
  { id: "detector", label: "Review media" },
  { id: "missing", label: "Needs work" },
];

const skeletonSegments: Array<{
  from: string[];
  to: string[];
  tone: "left" | "right" | "core" | "primary" | "secondary";
}> = [
  { from: ["left.shoulder", "secondary.shoulder"], to: ["right.shoulder", "primary.shoulder"], tone: "core" },
  { from: ["left.hip", "secondary.hip"], to: ["right.hip", "primary.hip"], tone: "core" },
  { from: ["left.shoulder", "secondary.shoulder"], to: ["left.hip", "secondary.hip"], tone: "left" },
  { from: ["right.shoulder", "primary.shoulder"], to: ["right.hip", "primary.hip"], tone: "right" },
  { from: ["left.shoulder", "secondary.shoulder"], to: ["left.elbow", "secondary.elbow"], tone: "left" },
  { from: ["left.elbow", "secondary.elbow"], to: ["left.wrist", "secondary.wrist"], tone: "left" },
  { from: ["right.shoulder", "primary.shoulder"], to: ["right.elbow", "primary.elbow"], tone: "right" },
  { from: ["right.elbow", "primary.elbow"], to: ["right.wrist", "primary.wrist"], tone: "right" },
  { from: ["left.hip", "secondary.hip"], to: ["left.knee", "secondary.knee"], tone: "left" },
  { from: ["left.knee", "secondary.knee"], to: ["left.ankle", "secondary.ankle"], tone: "left" },
  { from: ["left.ankle", "secondary.ankle"], to: ["left.heel", "secondary.heel"], tone: "left" },
  { from: ["left.ankle", "secondary.ankle"], to: ["left.foot.index", "secondary.foot.index"], tone: "left" },
  { from: ["right.hip", "primary.hip"], to: ["right.knee", "primary.knee"], tone: "right" },
  { from: ["right.knee", "primary.knee"], to: ["right.ankle", "primary.ankle"], tone: "right" },
  { from: ["right.ankle", "primary.ankle"], to: ["right.heel", "primary.heel"], tone: "right" },
  { from: ["right.ankle", "primary.ankle"], to: ["right.foot.index", "primary.foot.index"], tone: "right" },
  { from: ["primary.shoulder"], to: ["primary.hip"], tone: "primary" },
  { from: ["primary.hip"], to: ["primary.knee"], tone: "primary" },
  { from: ["primary.knee"], to: ["primary.ankle"], tone: "primary" },
  { from: ["secondary.shoulder"], to: ["secondary.hip"], tone: "secondary" },
  { from: ["secondary.hip"], to: ["secondary.knee"], tone: "secondary" },
  { from: ["secondary.knee"], to: ["secondary.ankle"], tone: "secondary" },
  { from: ["nose", "primary.nose"], to: ["primary.shoulder", "right.shoulder"], tone: "core" },
  { from: ["nose", "primary.nose"], to: ["secondary.shoulder", "left.shoulder"], tone: "core" },
];

const pointCandidates = [
  "nose",
  "primary.nose",
  "left.shoulder",
  "right.shoulder",
  "left.elbow",
  "right.elbow",
  "left.wrist",
  "right.wrist",
  "left.hip",
  "right.hip",
  "left.knee",
  "right.knee",
  "left.ankle",
  "right.ankle",
  "left.heel",
  "right.heel",
  "left.foot.index",
  "right.foot.index",
  "primary.shoulder",
  "primary.elbow",
  "primary.wrist",
  "primary.hip",
  "primary.knee",
  "primary.ankle",
  "primary.heel",
  "primary.foot.index",
  "secondary.shoulder",
  "secondary.elbow",
  "secondary.wrist",
  "secondary.hip",
  "secondary.knee",
  "secondary.ankle",
  "secondary.heel",
  "secondary.foot.index",
];

function cx(...classes: Array<string | false | null | undefined>) {
  return classes.filter(Boolean).join(" ");
}

function formatBytes(bytes: number | null) {
  if (bytes === null) {
    return "missing";
  }
  if (bytes < 1024 * 1024) {
    return `${Math.round(bytes / 1024)} KB`;
  }
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

function gateLabel(status: MotionReviewExercise["gateStatus"]) {
  if (status === "guide_ready") {
    return "Guide-ready";
  }
  if (status === "reference_capture_required") {
    return "Reference needed";
  }
  return "Unclassified";
}

function gateClasses(status: MotionReviewExercise["gateStatus"]) {
  if (status === "guide_ready") {
    return "border-[#d7ff5f]/35 bg-[#d7ff5f]/14 text-[#d7ff5f]";
  }
  if (status === "reference_capture_required") {
    return "border-[#ffb15f]/35 bg-[#ffb15f]/12 text-[#ffd3a1]";
  }
  return "border-white/14 bg-white/8 text-white/66";
}

function validationClasses(status: MotionReviewExercise["validation"][number]["status"]) {
  if (status === "pass") {
    return "text-[#d7ff5f]";
  }
  if (status === "warn") {
    return "text-[#ffd3a1]";
  }
  if (status === "missing") {
    return "text-white/42";
  }
  return "text-[#65ffd2]";
}

function tierLabel(tier: MotionReviewExercise["factory"]["promotionTier"]) {
  return tier.replaceAll("-", " ");
}

function tierClasses(tier: MotionReviewExercise["factory"]["promotionTier"]) {
  if (tier === "validation-ready") {
    return "border-[#65ffd2]/45 bg-[#65ffd2]/14 text-[#baffed]";
  }
  if (tier === "guide-ready") {
    return "border-[#d7ff5f]/35 bg-[#d7ff5f]/14 text-[#d7ff5f]";
  }
  if (tier === "avatar-demo-candidate") {
    return "border-[#ffb15f]/35 bg-[#ffb15f]/12 text-[#ffd3a1]";
  }
  if (tier === "detector-reviewable") {
    return "border-[#8ad8ff]/35 bg-[#8ad8ff]/12 text-[#bfeaff]";
  }
  return "border-white/14 bg-white/8 text-white/66";
}

function conceptClasses(status: MotionReviewExercise["factory"]["concepts"][number]["status"]) {
  if (status === "passed" || status === "present") {
    return "text-[#d7ff5f]";
  }
  if (status === "failed" || status === "invalid") {
    return "text-[#ffd3a1]";
  }
  return "text-white/42";
}

function formatReason(reason: string) {
  return reason.replaceAll("_", " ").replaceAll(":", ": ");
}

function matchesFilter(exercise: MotionReviewExercise, filter: GalleryFilter) {
  if (filter === "guide_ready") {
    return exercise.factory.guideReady;
  }
  if (filter === "validation_ready") {
    return exercise.factory.validationReady;
  }
  if (filter === "detector") {
    return Boolean(exercise.media.detectorVideoUrl || exercise.media.contactSheetUrl);
  }
  if (filter === "missing") {
    return exercise.factory.guideReadyBlockers.length > 0 || exercise.factory.validationReadyBlockers.length > 0;
  }
  return true;
}

export function MotionReviewGallery({ data }: { data: MotionReviewData }) {
  const [selectedId, setSelectedId] = useState(data.exercises[0]?.id ?? "");
  const [query, setQuery] = useState("");
  const [filter, setFilter] = useState<GalleryFilter>("all");

  const filteredExercises = useMemo(() => {
    const normalizedQuery = query.trim().toLowerCase();
    return data.exercises.filter((exercise) => {
      const matchesQuery =
        !normalizedQuery ||
        exercise.name.toLowerCase().includes(normalizedQuery) ||
        exercise.id.toLowerCase().includes(normalizedQuery);
      return matchesQuery && matchesFilter(exercise, filter);
    });
  }, [data.exercises, filter, query]);

  const selectedExercise = useMemo(() => {
    return (
      filteredExercises.find((exercise) => exercise.id === selectedId) ??
      filteredExercises[0] ??
      data.exercises[0]
    );
  }, [data.exercises, filteredExercises, selectedId]);

  if (!selectedExercise) {
    return (
      <main className="grid min-h-screen place-items-center bg-[#0b100d] px-6 text-white">
        <p>No motion review data found.</p>
      </main>
    );
  }

  return (
    <main className="min-h-screen bg-[#0b100d] text-white">
      <header className="sticky top-0 z-20 border-b border-white/10 bg-[#0b100d]/92 px-4 py-3 backdrop-blur md:px-6">
        <div className="mx-auto flex max-w-[96rem] items-center justify-between gap-4">
          <div className="flex items-center gap-3">
            <Link
              href="/"
              className="grid size-10 place-items-center rounded-md border border-white/12 bg-white/7 text-white/82"
              aria-label="Back to Momentum"
            >
              <ChevronLeft className="size-5" />
            </Link>
            <div>
              <h1 className="text-xl font-semibold tracking-[-0.01em]">Motion Review</h1>
              <p className="text-sm text-white/54">Local app traces, review media, validation state</p>
            </div>
          </div>
          <div className="hidden items-center gap-2 md:flex">
            <SummaryPill label="Exercises" value={data.summary.totalExercises} />
            <SummaryPill label="Guide" value={data.summary.guideReady} />
            <SummaryPill label="Validation" value={data.summary.validationReady} />
            <SummaryPill label="Blocked" value={data.summary.blockedFromGuideReady} />
          </div>
        </div>
      </header>

      <section className="mx-auto grid max-w-[96rem] gap-4 px-4 py-4 md:px-6 lg:grid-cols-[20rem_minmax(0,1fr)]">
        <aside className="space-y-3 lg:sticky lg:top-[5rem] lg:h-[calc(100svh-6rem)]">
          <div className="grid grid-cols-3 gap-2 md:hidden">
            <SummaryPill label="All" value={data.summary.totalExercises} />
            <SummaryPill label="Guide" value={data.summary.guideReady} />
            <SummaryPill label="Valid" value={data.summary.validationReady} />
          </div>

          <label className="relative block">
            <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-white/42" />
            <input
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              placeholder="Search exercises"
              className="h-11 w-full rounded-md border border-white/10 bg-white/7 pl-10 pr-3 text-sm text-white outline-none placeholder:text-white/38 focus:border-[#65ffd2]/50"
            />
          </label>

          <div className="grid grid-cols-2 gap-2">
            {filters.map((item) => (
              <button
                key={item.id}
                type="button"
                onClick={() => setFilter(item.id)}
                className={cx(
                  "h-10 rounded-md border px-3 text-sm font-semibold",
                  filter === item.id
                    ? "border-[#65ffd2]/48 bg-[#65ffd2]/12 text-[#baffed]"
                    : "border-white/10 bg-white/6 text-white/62",
                )}
              >
                {item.label}
              </button>
            ))}
          </div>

          <label className="block lg:hidden">
            <span className="sr-only">Selected exercise</span>
            <select
              value={selectedExercise.id}
              onChange={(event) => setSelectedId(event.target.value)}
              className="h-12 w-full rounded-md border border-white/10 bg-[#151a15] px-3 text-sm font-semibold text-white outline-none"
            >
              {filteredExercises.map((exercise) => (
                <option key={exercise.id} value={exercise.id}>
                  {exercise.name}
                </option>
              ))}
            </select>
          </label>

          <div className="hidden space-y-2 overflow-y-auto pr-1 lg:block lg:max-h-[calc(100svh-14rem)]">
            {filteredExercises.map((exercise) => (
              <ExerciseListItem
                key={exercise.id}
                exercise={exercise}
                selected={exercise.id === selectedExercise.id}
                onSelect={() => setSelectedId(exercise.id)}
              />
            ))}
          </div>
        </aside>

        <section className="space-y-4">
          <ExerciseHeader exercise={selectedExercise} />

          <div className="grid gap-4 xl:grid-cols-[minmax(0,1.04fr)_minmax(27rem,0.96fr)]">
            <MotionPanel exercise={selectedExercise} />
            <DetectionPanel exercise={selectedExercise} />
          </div>

          <EvidencePanel exercise={selectedExercise} />
          <FactoryPanel exercise={selectedExercise} />

          <div className="grid gap-4 xl:grid-cols-[minmax(0,0.95fr)_minmax(0,1.05fr)]">
            <ValidationPanel exercise={selectedExercise} />
            <ReviewPanel exercise={selectedExercise} />
          </div>
        </section>
      </section>
    </main>
  );
}

function SummaryPill({ label, value }: { label: string; value: number }) {
  return (
    <div className="rounded-md border border-white/10 bg-white/7 px-3 py-2 text-center">
      <div className="text-lg font-semibold leading-none">{value}</div>
      <div className="mt-1 text-[0.68rem] font-semibold uppercase tracking-[0.12em] text-white/42">
        {label}
      </div>
    </div>
  );
}

function ExerciseListItem({
  exercise,
  selected,
  onSelect,
}: {
  exercise: MotionReviewExercise;
  selected: boolean;
  onSelect: () => void;
}) {
  const Icon = exercise.factory.guideReady ? CheckCircle2 : AlertTriangle;

  return (
    <button
      type="button"
      onClick={onSelect}
      className={cx(
        "w-full rounded-md border p-3 text-left transition",
        selected
          ? "border-[#65ffd2]/42 bg-[#65ffd2]/10"
          : "border-white/8 bg-white/5 hover:border-white/18 hover:bg-white/8",
      )}
    >
      <div className="flex items-start gap-3">
        <Icon
          className={cx(
            "mt-0.5 size-4 shrink-0",
            exercise.factory.guideReady ? "text-[#d7ff5f]" : "text-[#ffd3a1]",
          )}
        />
        <div className="min-w-0 flex-1">
          <div className="truncate text-sm font-semibold text-white">{exercise.name}</div>
          <div className="mt-1 truncate text-xs text-white/42">{exercise.id}</div>
          <div className="mt-2">
            <span className={cx("rounded-full border px-2 py-0.5 text-[0.68rem] font-semibold", tierClasses(exercise.factory.promotionTier))}>
              {tierLabel(exercise.factory.promotionTier)}
            </span>
          </div>
          <div className="mt-2 flex items-center gap-2 text-xs text-white/52">
            <span>{exercise.frameCount || "No"} frames</span>
            {exercise.media.detectorVideoUrl ? <Film className="size-3.5 text-[#65ffd2]" /> : null}
            {exercise.trace.length ? <Activity className="size-3.5 text-[#d7ff5f]" /> : null}
          </div>
        </div>
      </div>
    </button>
  );
}

function ExerciseHeader({ exercise }: { exercise: MotionReviewExercise }) {
  return (
    <section className="rounded-lg border border-white/10 bg-[#121712] p-4 md:p-5">
      <div className="flex flex-col gap-4 md:flex-row md:items-start md:justify-between">
        <div>
          <div className="flex flex-wrap items-center gap-2">
            <span className={cx("rounded-full border px-3 py-1 text-xs font-semibold", gateClasses(exercise.gateStatus))}>
              {gateLabel(exercise.gateStatus)}
            </span>
            <span className={cx("rounded-full border px-3 py-1 text-xs font-semibold", tierClasses(exercise.factory.promotionTier))}>
              {tierLabel(exercise.factory.promotionTier)}
            </span>
            <span
              className={cx(
                "rounded-full border px-3 py-1 text-xs font-semibold",
                exercise.factory.validationReady
                  ? "border-[#65ffd2]/45 bg-[#65ffd2]/14 text-[#baffed]"
                  : "border-white/12 bg-white/7 text-white/58",
              )}
            >
              {exercise.factory.validationReady ? "Validation-ready" : "Not validation-ready"}
            </span>
            <span className="rounded-full border border-white/12 bg-white/7 px-3 py-1 text-xs font-semibold text-white/64">
              {exercise.sourceKind.replaceAll("_", " ")}
            </span>
          </div>
          <h2 className="mt-3 text-3xl font-semibold tracking-[-0.02em] md:text-4xl">
            {exercise.name}
          </h2>
          <p className="mt-2 max-w-3xl text-sm leading-6 text-white/58">{exercise.nextReview}</p>
        </div>
        <div className="grid grid-cols-3 gap-2 md:min-w-[22rem]">
          <Metric icon={Activity} label="Frames" value={String(exercise.frameCount)} />
          <Metric icon={ShieldCheck} label="Guide" value={exercise.factory.guideReady ? "yes" : "no"} />
          <Metric icon={Gauge} label="Valid" value={exercise.factory.validationReady ? "yes" : "no"} />
        </div>
      </div>
    </section>
  );
}

function Metric({
  icon: Icon,
  label,
  value,
}: {
  icon: typeof Activity;
  label: string;
  value: string;
}) {
  return (
    <div className="rounded-md border border-white/10 bg-white/6 p-3">
      <Icon className="size-4 text-[#65ffd2]" />
      <div className="mt-3 truncate text-base font-semibold">{value}</div>
      <div className="mt-1 text-[0.68rem] font-semibold uppercase tracking-[0.12em] text-white/42">
        {label}
      </div>
    </div>
  );
}

function MotionPanel({ exercise }: { exercise: MotionReviewExercise }) {
  return (
    <section className="rounded-lg border border-white/10 bg-[#121712] p-3 md:p-4">
      <div className="mb-3 flex items-center justify-between gap-3 px-1">
        <div>
          <h3 className="text-base font-semibold">3D Motion Demo</h3>
          <p className="text-sm text-white/46">
            {exercise.landmarkCount ? `${exercise.landmarkCount} landmarks` : "No landmarks packaged"}
          </p>
        </div>
        <span className="rounded-full bg-[#d7ff5f]/12 px-3 py-1 text-xs font-semibold text-[#d7ff5f]">
          App JSONL
        </span>
      </div>
      <SkeletonCanvas key={exercise.id} exercise={exercise} />
    </section>
  );
}

function DetectionPanel({ exercise }: { exercise: MotionReviewExercise }) {
  const [tab, setTab] = useState<"video" | "sheet" | "source">("video");
  const hasVideo = Boolean(exercise.media.detectorVideoUrl);
  const hasSheet = Boolean(exercise.media.contactSheetUrl);
  const hasSource = Boolean(exercise.media.sourceVideoUrl);
  const activeTab = tab === "video" && !hasVideo ? (hasSheet ? "sheet" : hasSource ? "source" : "video") : tab;

  return (
    <section className="rounded-lg border border-white/10 bg-[#121712] p-3 md:p-4">
      <div className="mb-3 flex items-center justify-between gap-3 px-1">
        <div>
          <h3 className="text-base font-semibold">Trace Review</h3>
          <p className="text-sm text-white/46">Detector review evidence</p>
        </div>
        <div className="flex rounded-md border border-white/10 bg-white/6 p-1">
          <TabButton
            label="Review video"
            selected={activeTab === "video"}
            disabled={!hasVideo}
            onClick={() => setTab("video")}
          >
            <Video className="size-4" />
          </TabButton>
          <TabButton
            label="Contact sheet"
            selected={activeTab === "sheet"}
            disabled={!hasSheet}
            onClick={() => setTab("sheet")}
          >
            <ImageIcon className="size-4" />
          </TabButton>
          <TabButton
            label="Source video"
            selected={activeTab === "source"}
            disabled={!hasSource}
            onClick={() => setTab("source")}
          >
            <Film className="size-4" />
          </TabButton>
        </div>
      </div>

      <div className="relative min-h-[22rem] overflow-hidden rounded-md border border-white/10 bg-[#080d0a]">
        {activeTab === "video" && hasVideo ? (
          <video
            key={exercise.media.detectorVideoUrl}
            className="block aspect-[16/10] w-full bg-black object-contain"
            controls
            loop
            muted
            playsInline
            preload="metadata"
            poster={exercise.media.contactSheetUrl ?? undefined}
          >
            <source src={exercise.media.detectorVideoUrl ?? undefined} type="video/mp4" />
          </video>
        ) : null}

        {activeTab === "sheet" && hasSheet ? (
          <Image
            src={exercise.media.contactSheetUrl ?? ""}
            alt={`${exercise.name} review contact sheet`}
            width={1200}
            height={800}
            unoptimized
            className="block h-full min-h-[22rem] w-full object-contain"
          />
        ) : null}

        {activeTab === "source" && hasSource ? (
          <video
            key={exercise.media.sourceVideoUrl}
            className="block aspect-[16/10] w-full bg-black object-contain"
            controls
            loop
            muted
            playsInline
            preload="metadata"
          >
            <source src={exercise.media.sourceVideoUrl ?? undefined} />
          </video>
        ) : null}

        {!hasVideo && !hasSheet && !hasSource ? (
          <EmptyMediaState />
        ) : null}
      </div>

      <div className="mt-3 grid grid-cols-3 gap-2 text-xs text-white/52">
        <MediaStat label="Review" value={formatBytes(exercise.media.detectorVideoBytes)} />
        <MediaStat label="Sheet" value={formatBytes(exercise.media.contactSheetBytes)} />
        <MediaStat label="Source" value={formatBytes(exercise.media.sourceVideoBytes)} />
      </div>
    </section>
  );
}

function TabButton({
  label,
  selected,
  disabled,
  onClick,
  children,
}: {
  label: string;
  selected: boolean;
  disabled: boolean;
  onClick: () => void;
  children: React.ReactNode;
}) {
  return (
    <button
      type="button"
      disabled={disabled}
      onClick={onClick}
      title={label}
      aria-label={label}
      className={cx(
        "grid size-9 place-items-center rounded-md",
        selected ? "bg-white text-[#0b100d]" : "text-white/58",
        disabled && "cursor-not-allowed opacity-30",
      )}
    >
      {children}
    </button>
  );
}

function EmptyMediaState() {
  return (
    <div className="grid min-h-[22rem] place-items-center px-6 text-center">
      <div>
        <AlertTriangle className="mx-auto size-8 text-[#ffd3a1]" />
        <p className="mt-3 text-sm font-semibold text-white">No review media found</p>
        <p className="mt-2 max-w-sm text-sm leading-6 text-white/48">
          This exercise needs a generated review clip or contact sheet before visual QA can be trusted.
        </p>
      </div>
    </div>
  );
}

function MediaStat({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-md border border-white/8 bg-white/5 px-3 py-2">
      <div className="font-semibold text-white/78">{value}</div>
      <div className="mt-1 uppercase tracking-[0.12em] text-white/36">{label}</div>
    </div>
  );
}

function EvidencePanel({ exercise }: { exercise: MotionReviewExercise }) {
  const { capturePlan, source, captureSession, visualReview } = exercise.evidence;
  const reviewPassed = visualReview.status === "passed" || visualReview.status === "reviewed";

  return (
    <section className="rounded-lg border border-white/10 bg-[#121712] p-4">
      <div className="flex items-center gap-2">
        <Film className="size-5 text-[#65ffd2]" />
        <h3 className="text-base font-semibold">Source Evidence</h3>
      </div>

      <div className="mt-4 grid gap-3 xl:grid-cols-4">
        <EvidenceCard title="Capture Plan">
          <EvidenceRow
            label="Priority"
            value={capturePlan.priority === null ? "missing" : `#${capturePlan.priority}`}
            tone={capturePlan.priority === null ? "missing" : "ok"}
          />
          <EvidenceRow label="View" value={capturePlan.requiredView} />
          <EvidenceRow label="Reason" value={capturePlan.reason} />
          <EvidenceRow label="Promotion" value={capturePlan.promotionRule} />
        </EvidenceCard>

        <EvidenceCard title="Source">
          <EvidenceRow label="Kind" value={source.kind} />
          <EvidenceRow label="Label" value={source.label} />
          <EvidenceRow label="Video" value={source.videoPath} />
          <EvidenceRow label="License" value={source.license} />
          <EvidenceRow label="Attribution" value={source.attribution} />
        </EvidenceCard>

        <EvidenceCard title="Capture Session">
          <EvidenceRow label="Status" value={captureSession.present ? "present" : "missing"} tone={captureSession.present ? "ok" : "warn"} />
          <EvidenceRow label="Source" value={captureSession.sourceKind} />
          <EvidenceRow label="View" value={captureSession.cameraView} />
          <EvidenceRow label="FPS" value={captureSession.fps} />
          <EvidenceRow label="Resolution" value={captureSession.resolution} />
          <EvidenceRow label="Equipment" value={captureSession.equipment} />
          <EvidenceRow label="Notes" value={captureSession.reviewerNotes} />
        </EvidenceCard>

        <EvidenceCard title="Visual Review">
          <EvidenceRow label="Status" value={visualReview.status} tone={reviewPassed ? "ok" : visualReview.present ? "warn" : "missing"} />
          <EvidenceRow label="Reviewer" value={visualReview.reviewer} />
          <EvidenceRow label="Reviewed" value={visualReview.reviewedAt} />
          <EvidenceRow label="Evidence" value={visualReview.evidence} />
          <EvidenceRow
            label="Failures"
            value={visualReview.failureReasons.length ? visualReview.failureReasons.join(", ") : "none"}
            tone={visualReview.failureReasons.length ? "warn" : "ok"}
          />
        </EvidenceCard>
      </div>
    </section>
  );
}

function EvidenceCard({ title, children }: { title: string; children: ReactNode }) {
  return (
    <div className="rounded-md border border-white/8 bg-white/5 p-3">
      <h4 className="text-xs font-semibold uppercase tracking-[0.12em] text-white/40">{title}</h4>
      <div className="mt-3 space-y-2">{children}</div>
    </div>
  );
}

function EvidenceRow({
  label,
  value,
  tone = "default",
}: {
  label: string;
  value: string;
  tone?: "default" | "ok" | "warn" | "missing";
}) {
  const toneClass =
    tone === "ok"
      ? "text-[#d7ff5f]"
      : tone === "warn"
        ? "text-[#ffd3a1]"
        : tone === "missing"
          ? "text-white/38"
          : "text-white/68";

  return (
    <div className="grid grid-cols-[7rem_minmax(0,1fr)] gap-3 text-xs">
      <div className="text-white/36">{label}</div>
      <div className={cx("min-w-0 break-words font-semibold leading-5", toneClass)}>
        {value || "missing"}
      </div>
    </div>
  );
}

function FactoryPanel({ exercise }: { exercise: MotionReviewExercise }) {
  const signals = exercise.factory.currentSignals;
  const signalItems = [
    ["App gate", signals.appGate],
    ["Reference", signals.referenceStatus],
    ["Capture", signals.captureStatus],
    ["Normalizer", signals.normalizerStatus],
    ["Manifest", signals.manifestStatus],
    ["Playable", signals.playableJsonl ? "yes" : "no"],
  ];

  return (
    <section className="rounded-lg border border-white/10 bg-[#121712] p-4">
      <div className="flex flex-col gap-3 md:flex-row md:items-start md:justify-between">
        <div className="min-w-0">
          <div className="flex items-center gap-2">
            <Gauge className="size-5 text-[#65ffd2]" />
            <h3 className="text-base font-semibold">Factory Readiness</h3>
          </div>
          <p className="mt-2 max-w-4xl text-sm leading-6 text-white/56">
            {exercise.factory.nextAction}
          </p>
        </div>
        <span
          className={cx(
            "w-fit rounded-full border px-3 py-1 text-xs font-semibold",
            tierClasses(exercise.factory.promotionTier),
          )}
        >
          {tierLabel(exercise.factory.promotionTier)}
        </span>
      </div>

      <div className="mt-4 grid gap-2 sm:grid-cols-2 xl:grid-cols-5">
        {exercise.factory.concepts.map((item) => (
          <div key={item.key} className="rounded-md border border-white/8 bg-white/5 p-3">
            <div className="flex items-center justify-between gap-3">
              <div className="text-xs font-semibold uppercase tracking-[0.12em] text-white/40">
                {item.label}
              </div>
              <Circle className={cx("size-2.5 fill-current", conceptClasses(item.status))} />
            </div>
            <div className={cx("mt-2 text-sm font-semibold", conceptClasses(item.status))}>
              {item.decision.replaceAll("_", " ")}
            </div>
            <div className="mt-2 text-xs leading-5 text-white/44">
              {item.reasons.length ? formatReason(item.reasons[0]) : "ready"}
            </div>
          </div>
        ))}
      </div>

      <div className="mt-4 grid gap-3 xl:grid-cols-[minmax(0,1fr)_minmax(0,1fr)_22rem]">
        <BlockerList title="Guide blockers" blockers={exercise.factory.guideReadyBlockers} />
        <BlockerList title="Validation blockers" blockers={exercise.factory.validationReadyBlockers} />
        <div className="rounded-md border border-white/8 bg-white/5 p-3">
          <h4 className="text-xs font-semibold uppercase tracking-[0.12em] text-white/40">
            Current signals
          </h4>
          <div className="mt-3 grid grid-cols-2 gap-x-3 gap-y-2 text-xs">
            {signalItems.map(([label, value]) => (
              <div key={label} className="min-w-0">
                <div className="text-white/36">{label}</div>
                <div className="mt-0.5 truncate font-semibold text-white/68">
                  {formatReason(value)}
                </div>
              </div>
            ))}
          </div>
          {signals.localOnlyArtifacts.length ? (
            <div className="mt-3 border-t border-white/8 pt-3 text-xs leading-5 text-[#ffd3a1]">
              Local-only artifacts: {signals.localOnlyArtifacts.length}
            </div>
          ) : null}
        </div>
      </div>
    </section>
  );
}

function BlockerList({ title, blockers }: { title: string; blockers: string[] }) {
  return (
    <div className="rounded-md border border-white/8 bg-white/5 p-3">
      <div className="flex items-center gap-2 text-sm font-semibold">
        {blockers.length ? (
          <AlertTriangle className="size-4 text-[#ffd3a1]" />
        ) : (
          <CheckCircle2 className="size-4 text-[#d7ff5f]" />
        )}
        {title}
      </div>
      <div className="mt-3 flex flex-wrap gap-2">
        {(blockers.length ? blockers : ["none"]).map((item) => (
          <span
            key={item}
            className="rounded-full border border-white/10 bg-[#0b100d] px-3 py-1 text-xs font-semibold text-white/62"
          >
            {formatReason(item)}
          </span>
        ))}
      </div>
    </div>
  );
}

function ValidationPanel({ exercise }: { exercise: MotionReviewExercise }) {
  return (
    <section className="rounded-lg border border-white/10 bg-[#121712] p-4">
      <div className="flex items-center gap-2">
        <ShieldCheck className="size-5 text-[#65ffd2]" />
        <h3 className="text-base font-semibold">Validation Data</h3>
      </div>
      <div className="mt-4 grid gap-2 sm:grid-cols-2">
        {exercise.validation.map((item) => (
          <div key={item.label} className="rounded-md border border-white/8 bg-white/5 p-3">
            <div className="flex items-center justify-between gap-3">
              <div className="text-xs font-semibold uppercase tracking-[0.12em] text-white/40">
                {item.label}
              </div>
              <Circle className={cx("size-2.5 fill-current", validationClasses(item.status))} />
            </div>
            <div className={cx("mt-2 text-sm font-semibold", validationClasses(item.status))}>
              {item.value.replaceAll("_", " ")}
            </div>
          </div>
        ))}
      </div>
    </section>
  );
}

function ReviewPanel({ exercise }: { exercise: MotionReviewExercise }) {
  const reviewGaps = [
    ...new Set([
      ...exercise.missing,
      ...exercise.factory.guideReadyBlockers,
      ...exercise.factory.validationReadyBlockers,
    ]),
  ];

  return (
    <section className="rounded-lg border border-white/10 bg-[#121712] p-4">
      <div className="flex items-center gap-2">
        <SlidersHorizontal className="size-5 text-[#d7ff5f]" />
        <h3 className="text-base font-semibold">Exercise Contract</h3>
      </div>

      <div className="mt-4 grid gap-3 md:grid-cols-2">
        <Fact label="Required view" value={exercise.requiredView} />
        <Fact label="Capture status" value={exercise.captureStatus.replaceAll("_", " ")} />
        <Fact label="Measurement" value={exercise.measurementStatus.replaceAll("_", " ")} />
        <Fact label="Acceptance" value={exercise.acceptanceStatus.replaceAll("_", " ")} />
      </div>

      <div className="mt-4 grid gap-4 md:grid-cols-2">
        <Checklist
          title="Required landmarks"
          items={exercise.requiredLandmarks.length ? exercise.requiredLandmarks : ["missing"]}
        />
        <Checklist title="Form cues" items={exercise.formCues.length ? exercise.formCues : ["missing"]} />
      </div>

      <div className="mt-4 rounded-md border border-white/8 bg-white/5 p-3">
        <div className="flex items-center gap-2 text-sm font-semibold">
          {reviewGaps.length ? (
            <AlertTriangle className="size-4 text-[#ffd3a1]" />
          ) : (
            <CheckCircle2 className="size-4 text-[#d7ff5f]" />
          )}
          Review gaps
        </div>
        <div className="mt-3 flex flex-wrap gap-2">
          {(reviewGaps.length ? reviewGaps : ["none"]).map((item) => (
            <span
              key={item}
              className="rounded-full border border-white/10 bg-[#0b100d] px-3 py-1 text-xs font-semibold text-white/62"
            >
              {formatReason(item)}
            </span>
          ))}
        </div>
      </div>
    </section>
  );
}

function Fact({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-md border border-white/8 bg-white/5 p-3">
      <div className="text-xs font-semibold uppercase tracking-[0.12em] text-white/40">{label}</div>
      <div className="mt-2 text-sm font-semibold text-white/82">{value}</div>
    </div>
  );
}

function Checklist({ title, items }: { title: string; items: string[] }) {
  return (
    <div>
      <h4 className="text-xs font-semibold uppercase tracking-[0.12em] text-white/40">{title}</h4>
      <div className="mt-2 space-y-2">
        {items.map((item) => (
          <div key={item} className="flex items-center gap-2 text-sm text-white/68">
            <CheckCircle2 className="size-4 text-[#65ffd2]" />
            <span>{item}</span>
          </div>
        ))}
      </div>
    </div>
  );
}

function SkeletonCanvas({ exercise }: { exercise: MotionReviewExercise }) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const frames = exercise.trace;
  const [playing, setPlaying] = useState(frames.length > 1);
  const [autoOrbit, setAutoOrbit] = useState(true);
  const [frameIndex, setFrameIndex] = useState(0);
  const [speed, setSpeed] = useState(1);
  const [yaw, setYaw] = useState(-22);
  const activeFrame = frames[frameIndex] ?? null;

  useEffect(() => {
    if (frames.length <= 1) {
      return;
    }

    let animationFrame = 0;
    let previous = performance.now();
    let frameDebt = 0;
    const baseFrameMs = Math.max(60, exercise.durationMs / Math.max(1, frames.length - 1) || 100);

    const step = (now: number) => {
      const elapsed = now - previous;
      previous = now;

      if (playing) {
        frameDebt += elapsed * speed;
        if (frameDebt >= baseFrameMs) {
          const steps = Math.floor(frameDebt / baseFrameMs);
          setFrameIndex((current) => (current + steps) % frames.length);
          frameDebt %= baseFrameMs;
        }
      }

      if (autoOrbit) {
        setYaw((current) => {
          const next = current + elapsed * 0.008;
          return next > 180 ? next - 360 : next;
        });
      }

      animationFrame = requestAnimationFrame(step);
    };

    animationFrame = requestAnimationFrame(step);
    return () => cancelAnimationFrame(animationFrame);
  }, [autoOrbit, exercise.durationMs, frames.length, playing, speed]);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) {
      return;
    }

    drawCanvas(canvas, activeFrame, yaw);
  }, [activeFrame, yaw]);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) {
      return;
    }

    const observer = new ResizeObserver(() => drawCanvas(canvas, activeFrame, yaw));
    observer.observe(canvas);
    return () => observer.disconnect();
  }, [activeFrame, yaw]);

  return (
    <div>
      <div className="relative overflow-hidden rounded-md border border-white/10 bg-[#07100b]">
        <canvas
          ref={canvasRef}
          className="block aspect-[4/3] w-full touch-none"
          aria-label={`${exercise.name} 3D motion demo`}
        />
        {!activeFrame ? (
          <div className="absolute inset-0 grid place-items-center bg-[#07100b]/92 px-6 text-center">
            <div>
              <AlertTriangle className="mx-auto size-8 text-[#ffd3a1]" />
              <p className="mt-3 text-sm font-semibold">No playable trace packaged</p>
              <p className="mt-2 max-w-sm text-sm leading-6 text-white/48">
                This exercise cannot be visually accepted in the app until a MotionDemos JSONL exists.
              </p>
            </div>
          </div>
        ) : null}
      </div>

      <div className="mt-3 grid gap-3 md:grid-cols-[auto_minmax(0,1fr)_8rem] md:items-center">
        <div className="flex gap-2">
          <button
            type="button"
            onClick={() => setPlaying((current) => !current)}
            disabled={frames.length <= 1}
            className="grid size-10 place-items-center rounded-md bg-[#d7ff5f] text-[#0b100d] disabled:cursor-not-allowed disabled:opacity-40"
            aria-label={playing ? "Pause motion" : "Play motion"}
          >
            {playing ? <Pause className="size-5" /> : <Play className="size-5" />}
          </button>
          <button
            type="button"
            onClick={() => {
              setFrameIndex(0);
              setYaw(-22);
            }}
            className="grid size-10 place-items-center rounded-md border border-white/10 bg-white/7 text-white/72"
            aria-label="Reset motion"
          >
            <RotateCcw className="size-5" />
          </button>
          <button
            type="button"
            onClick={() => setAutoOrbit((current) => !current)}
            className={cx(
              "grid size-10 place-items-center rounded-md border",
              autoOrbit
                ? "border-[#65ffd2]/45 bg-[#65ffd2]/12 text-[#baffed]"
                : "border-white/10 bg-white/7 text-white/72",
            )}
            aria-label="Toggle orbit"
          >
            <SlidersHorizontal className="size-5" />
          </button>
        </div>

        <label className="block">
          <span className="sr-only">Frame</span>
          <input
            type="range"
            min={0}
            max={Math.max(0, frames.length - 1)}
            value={frameIndex}
            onChange={(event) => {
              setPlaying(false);
              setFrameIndex(Number(event.target.value));
            }}
            className="w-full accent-[#d7ff5f]"
          />
        </label>

        <label className="block">
          <span className="sr-only">Playback speed</span>
          <select
            value={speed}
            onChange={(event) => setSpeed(Number(event.target.value))}
            className="h-10 w-full rounded-md border border-white/10 bg-white/7 px-2 text-sm font-semibold text-white"
          >
            <option value={0.5}>0.5x</option>
            <option value={1}>1x</option>
            <option value={1.5}>1.5x</option>
            <option value={2}>2x</option>
          </select>
        </label>
      </div>
    </div>
  );
}

function drawCanvas(canvas: HTMLCanvasElement, frame: MotionFrame | null, yawDegrees: number) {
  const rect = canvas.getBoundingClientRect();
  const width = Math.max(1, rect.width);
  const height = Math.max(1, rect.height);
  const dpr = window.devicePixelRatio || 1;
  const targetWidth = Math.floor(width * dpr);
  const targetHeight = Math.floor(height * dpr);

  if (canvas.width !== targetWidth || canvas.height !== targetHeight) {
    canvas.width = targetWidth;
    canvas.height = targetHeight;
  }

  const context = canvas.getContext("2d");
  if (!context) {
    return;
  }

  context.save();
  context.scale(dpr, dpr);
  drawBackground(context, width, height);

  if (frame) {
    drawSkeleton(context, frame, width, height, yawDegrees);
  }

  context.restore();
}

function drawBackground(context: CanvasRenderingContext2D, width: number, height: number) {
  const gradient = context.createLinearGradient(0, 0, width, height);
  gradient.addColorStop(0, "#07100b");
  gradient.addColorStop(0.55, "#111a13");
  gradient.addColorStop(1, "#0b0d0a");
  context.fillStyle = gradient;
  context.fillRect(0, 0, width, height);

  context.strokeStyle = "rgba(215, 255, 95, 0.12)";
  context.lineWidth = 1;
  for (let index = 0; index < 9; index += 1) {
    const progress = index / 8;
    const y = height * (0.66 + progress * 0.26);
    context.beginPath();
    context.ellipse(width / 2, y, width * (0.16 + progress * 0.36), height * 0.035, 0, 0, Math.PI * 2);
    context.stroke();
  }

  context.strokeStyle = "rgba(101, 255, 210, 0.12)";
  for (let index = -3; index <= 3; index += 1) {
    context.beginPath();
    context.moveTo(width * 0.5 + index * width * 0.08, height * 0.7);
    context.lineTo(width * 0.5 + index * width * 0.19, height * 0.92);
    context.stroke();
  }
}

function drawSkeleton(
  context: CanvasRenderingContext2D,
  frame: MotionFrame,
  width: number,
  height: number,
  yawDegrees: number,
) {
  const projected = new Map<string, ProjectedPoint>();
  pointCandidates.forEach((key) => {
    const landmark = frame.landmarks[key];
    if (!isLandmarkUsable(landmark)) {
      return;
    }

    projected.set(key, projectLandmark(landmark, width, height, yawDegrees));
  });

  const sortedSegments = skeletonSegments
    .map((segment) => {
      const from = firstProjected(projected, segment.from);
      const to = firstProjected(projected, segment.to);
      return from && to ? { ...segment, fromPoint: from, toPoint: to } : null;
    })
    .filter((segment): segment is NonNullable<typeof segment> => Boolean(segment))
    .sort((left, right) => left.fromPoint.depth + left.toPoint.depth - right.fromPoint.depth - right.toPoint.depth);

  sortedSegments.forEach((segment) => {
    const averageDepth = (segment.fromPoint.depth + segment.toPoint.depth) / 2;
    context.strokeStyle = toneColor(segment.tone, averageDepth);
    context.lineWidth = Math.max(3, 7 - averageDepth * 2.2);
    context.lineCap = "round";
    context.beginPath();
    context.moveTo(segment.fromPoint.x, segment.fromPoint.y);
    context.lineTo(segment.toPoint.x, segment.toPoint.y);
    context.stroke();
  });

  const points = [...projected.entries()].sort((left, right) => left[1].depth - right[1].depth);
  points.forEach(([key, point]) => {
    const radius = key.includes("nose") ? 5.8 : 4.4;
    context.fillStyle = key.startsWith("left") || key.startsWith("secondary")
      ? "rgba(101, 255, 210, 0.95)"
      : "rgba(215, 255, 95, 0.95)";
    context.beginPath();
    context.arc(point.x, point.y, Math.max(3, radius - point.depth * 0.75), 0, Math.PI * 2);
    context.fill();
  });
}

function isLandmarkUsable(value: Landmark | undefined): value is Landmark {
  return (
    Boolean(value) &&
    Number.isFinite(value?.x) &&
    Number.isFinite(value?.y) &&
    (value?.visibility ?? 1) >= 0.1
  );
}

function firstProjected(projected: Map<string, ProjectedPoint>, candidates: string[]) {
  for (const candidate of candidates) {
    const point = projected.get(candidate);
    if (point) {
      return point;
    }
  }

  return null;
}

function projectLandmark(
  landmark: Landmark,
  width: number,
  height: number,
  yawDegrees: number,
): ProjectedPoint {
  const yaw = (yawDegrees * Math.PI) / 180;
  const pitch = (-10 * Math.PI) / 180;
  const x = (landmark.x - 0.5) * 2.2;
  const y = (0.54 - landmark.y) * 2.35;
  const z = (landmark.z ?? 0) * 1.9;
  const cosYaw = Math.cos(yaw);
  const sinYaw = Math.sin(yaw);
  const rotatedX = x * cosYaw + z * sinYaw;
  const rotatedZ = -x * sinYaw + z * cosYaw;
  const cosPitch = Math.cos(pitch);
  const sinPitch = Math.sin(pitch);
  const rotatedY = y * cosPitch - rotatedZ * sinPitch;
  const pitchedZ = y * sinPitch + rotatedZ * cosPitch;
  const perspective = 1 / (1 + pitchedZ * 0.18);
  const scale = Math.min(width, height) * 0.42;

  return {
    x: width / 2 + rotatedX * scale * perspective,
    y: height * 0.55 - rotatedY * scale * perspective,
    depth: pitchedZ,
  };
}

function toneColor(
  tone: "left" | "right" | "core" | "primary" | "secondary",
  depth: number,
) {
  const alpha = Math.max(0.46, Math.min(0.98, 0.85 - depth * 0.12));
  if (tone === "left" || tone === "secondary") {
    return `rgba(101, 255, 210, ${alpha})`;
  }
  if (tone === "right" || tone === "primary") {
    return `rgba(215, 255, 95, ${alpha})`;
  }
  return `rgba(255, 255, 255, ${alpha})`;
}
