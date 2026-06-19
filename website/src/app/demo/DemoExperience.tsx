"use client";

import {
  Activity,
  BrainCircuit,
  CheckCircle2,
  ChevronLeft,
  Clock3,
  FileText,
  HeartPulse,
  MessageSquare,
  Play,
  RotateCcw,
  ShieldCheck,
  Sparkles,
  Target,
  Zap,
} from "lucide-react";
import Link from "next/link";
import { useMemo, useState } from "react";

import { HeroWorkoutVideo } from "../HeroWorkoutVideo";

type DemoTab = "train" | "coach" | "graph" | "history";

const member = {
  name: "Jordan Rivera",
  plan: "Lower-body return to strength",
  goal: "Pain-free squat pattern with dumbbell strength work",
  injury: "Left knee flare-up, resolving",
  equipment: ["Dumbbells", "Loop band", "Bench", "Yoga mat"],
};

const plan = [
  {
    name: "Bodyweight squat",
    sets: "2 x 8",
    status: "live",
    reason: "Form baseline before load",
  },
  {
    name: "Split-stance RDL",
    sets: "3 x 8",
    status: "safe",
    reason: "Hinge stimulus without knee compression",
  },
  {
    name: "Mini-band lateral walk",
    sets: "2 x 12",
    status: "safe",
    reason: "Glute med support for knee tracking",
  },
  {
    name: "Jump squat",
    sets: "blocked",
    status: "blocked",
    reason: "Impact blocked while knee is recovering",
  },
];

const cues = [
  "Stand tall. Camera found hips, knees, and ankles.",
  "Rep 1 counted. Depth cleared, knees stayed stacked.",
  "Rep 2 counted. Tempo slowed at the bottom.",
  "Rep 3 counted. Slight left knee drift corrected.",
  "Rep 4 counted. Keep weight through midfoot.",
  "Rep 5 counted. Range and control look consistent.",
  "Set complete. Coach summary is ready.",
];

const graphEdges = [
  ["left knee", "limits", "deep loaded flexion"],
  ["dumbbell", "enables", "hinge progression"],
  ["sleep dip", "reduces", "session intensity"],
  ["glute med", "supports", "knee tracking"],
];

const history = [
  ["Jun 10", "Squat form review", "5 clean reps, 1 correction"],
  ["Jun 08", "Coach check-in", "Adherence risk resolved"],
  ["Jun 06", "Plan update", "Removed impact work"],
  ["Jun 04", "Movement baseline", "Left knee context captured"],
];

const tabs: Array<{ id: DemoTab; label: string; icon: typeof Activity }> = [
  { id: "train", label: "Train", icon: Activity },
  { id: "coach", label: "Coach", icon: MessageSquare },
  { id: "graph", label: "Graph", icon: BrainCircuit },
  { id: "history", label: "History", icon: Clock3 },
];

function cx(...classes: Array<string | false | null | undefined>) {
  return classes.filter(Boolean).join(" ");
}

export function DemoExperience() {
  const [activeTab, setActiveTab] = useState<DemoTab>("train");
  const [repCount, setRepCount] = useState(2);
  const cue = cues[Math.min(repCount, cues.length - 1)];
  const complete = repCount >= 5;

  const readiness = useMemo(() => {
    if (complete) {
      return "Ready for coach review";
    }
    if (repCount >= 3) {
      return "Tracking stable";
    }
    return "Warm-up set";
  }, [complete, repCount]);

  return (
    <main className="min-h-screen bg-[#f1eee4] text-[#151713]">
      <section className="border-b border-[#d8d2c0] bg-[#10130f] px-4 py-4 text-white md:px-6">
        <div className="mx-auto flex max-w-[92rem] flex-wrap items-center justify-between gap-4">
          <Link
            href="/"
            className="inline-flex items-center gap-2 rounded-full border border-white/12 bg-white/7 px-4 py-2 text-sm font-medium text-white/82"
          >
            <ChevronLeft className="size-4" />
            Momentum
          </Link>
          <div className="flex items-center gap-3">
            <span className="rounded-full border border-[#d7ff5f]/28 bg-[#d7ff5f]/12 px-3 py-1 text-xs font-semibold uppercase tracking-[0.16em] text-[#d7ff5f]">
              Synthetic demo
            </span>
            <span className="hidden text-sm text-white/58 sm:inline">
              No camera, account, or real member data
            </span>
          </div>
        </div>
      </section>

      <section className="mx-auto grid max-w-[92rem] gap-5 px-4 py-5 md:px-6 lg:grid-cols-[18rem_minmax(0,1fr)]">
        <aside className="space-y-5">
          <section className="rounded-lg bg-[#151713] p-5 text-white shadow-[0_18px_50px_rgba(24,22,18,0.13)]">
            <div className="flex items-center gap-3">
              <div className="grid size-12 place-items-center rounded-md bg-[#d7ff5f] text-lg font-black text-[#151713]">
                JR
              </div>
              <div>
                <h1 className="text-xl font-semibold">{member.name}</h1>
                <p className="text-sm text-white/58">Synthetic Future member</p>
              </div>
            </div>
            <div className="mt-5 space-y-3 text-sm">
              <ContextRow label="Goal" value={member.goal} />
              <ContextRow label="Safety" value={member.injury} />
              <ContextRow label="Plan" value={member.plan} />
            </div>
          </section>

          <section className="rounded-lg bg-white p-5 shadow-sm">
            <h2 className="text-sm font-semibold uppercase tracking-[0.16em] text-[#716c5f]">
              Equipment
            </h2>
            <div className="mt-4 flex flex-wrap gap-2">
              {member.equipment.map((item) => (
                <span key={item} className="rounded-full bg-[#eff6df] px-3 py-2 text-sm font-medium">
                  {item}
                </span>
              ))}
            </div>
          </section>
        </aside>

        <div className="space-y-5">
          <section className="overflow-hidden rounded-lg bg-[#151713] text-white shadow-[0_18px_60px_rgba(24,22,18,0.18)]">
            <div className="grid gap-0 lg:grid-cols-[minmax(0,1.35fr)_minmax(22rem,0.65fr)]">
              <div className="relative min-h-[28rem] border-b border-white/10 bg-[#0c100d] lg:border-b-0 lg:border-r">
                <HeroWorkoutVideo />
                <div className="absolute left-4 top-4 rounded-full bg-black/72 px-4 py-2 text-sm font-semibold backdrop-blur">
                  Live mirror · Bodyweight squat
                </div>
                <div className="absolute bottom-4 left-4 right-4 grid gap-3 sm:grid-cols-3">
                  <MetricCard icon={Zap} label="Reps" value={`${repCount}/5`} tone="lime" />
                  <MetricCard icon={Activity} label="Knee drift" value={repCount >= 3 ? "Corrected" : "Clear"} tone="mint" />
                  <MetricCard icon={Clock3} label="Tempo" value="3.1s" tone="amber" />
                </div>
              </div>

              <div className="p-5 md:p-6">
                <div className="flex items-center justify-between gap-3">
                  <div>
                    <p className="text-xs font-semibold uppercase tracking-[0.18em] text-[#d7ff5f]">
                      Movement feedback
                    </p>
                    <h2 className="mt-2 text-3xl font-semibold tracking-[-0.02em]">
                      {readiness}
                    </h2>
                  </div>
                  <div className="grid size-14 place-items-center rounded-full bg-[#d7ff5f] text-xl font-black text-[#151713]">
                    {repCount}
                  </div>
                </div>
                <p className="mt-5 rounded-lg border border-white/12 bg-white/7 p-4 text-base leading-7 text-white/82">
                  {cue}
                </p>
                <div className="mt-5 grid gap-3 sm:grid-cols-2">
                  <button
                    type="button"
                    onClick={() => setRepCount((current) => Math.min(current + 1, 5))}
                    className="inline-flex items-center justify-center gap-2 rounded-md bg-[#d7ff5f] px-4 py-3 font-semibold text-[#151713]"
                  >
                    <Play className="size-4" />
                    Advance rep
                  </button>
                  <button
                    type="button"
                    onClick={() => setRepCount(0)}
                    className="inline-flex items-center justify-center gap-2 rounded-md border border-white/14 bg-white/7 px-4 py-3 font-semibold text-white"
                  >
                    <RotateCcw className="size-4" />
                    Reset set
                  </button>
                </div>
              </div>
            </div>
          </section>

          <section className="rounded-lg bg-white p-2 shadow-sm">
            <div className="grid grid-cols-4 gap-2">
              {tabs.map((tab) => {
                const Icon = tab.icon;
                const selected = activeTab === tab.id;
                return (
                  <button
                    key={tab.id}
                    type="button"
                    onClick={() => setActiveTab(tab.id)}
                    className={cx(
                      "inline-flex items-center justify-center gap-2 rounded-md px-3 py-3 text-sm font-semibold",
                      selected ? "bg-[#151713] text-white" : "text-[#555044] hover:bg-[#f2efe4]",
                    )}
                  >
                    <Icon className="size-4" />
                    <span>{tab.label}</span>
                  </button>
                );
              })}
            </div>
          </section>

          {activeTab === "train" && <TrainPanel />}
          {activeTab === "coach" && <CoachPanel complete={complete} />}
          {activeTab === "graph" && <GraphPanel />}
          {activeTab === "history" && <HistoryPanel />}
        </div>
      </section>
    </main>
  );
}

function ContextRow({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <div className="text-xs font-semibold uppercase tracking-[0.14em] text-white/42">{label}</div>
      <div className="mt-1 leading-6 text-white/86">{value}</div>
    </div>
  );
}

function MetricCard({
  icon: Icon,
  label,
  value,
  tone,
}: {
  icon: typeof Activity;
  label: string;
  value: string;
  tone: "lime" | "mint" | "amber";
}) {
  const toneClass = {
    lime: "text-[#d7ff5f]",
    mint: "text-[#65ffd2]",
    amber: "text-[#ffb25f]",
  }[tone];

  return (
    <div className="rounded-lg border border-white/14 bg-black/62 p-4 backdrop-blur">
      <div className={cx("flex items-center gap-2 text-xs font-semibold uppercase tracking-[0.14em]", toneClass)}>
        <Icon className="size-4" />
        {label}
      </div>
      <div className="mt-2 text-2xl font-semibold">{value}</div>
    </div>
  );
}

function TrainPanel() {
  return (
    <section className="grid gap-5 xl:grid-cols-[minmax(0,1fr)_23rem]">
      <div className="rounded-lg bg-white p-5 shadow-sm">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <p className="text-xs font-semibold uppercase tracking-[0.16em] text-[#716c5f]">
              Workout plan
            </p>
            <h2 className="mt-2 text-3xl font-semibold tracking-[-0.02em]">Today&apos;s safe session</h2>
          </div>
          <span className="rounded-full bg-[#eff6df] px-4 py-2 text-sm font-semibold text-[#263416]">
            42 minutes
          </span>
        </div>
        <div className="mt-5 space-y-3">
          {plan.map((item) => (
            <div key={item.name} className="grid gap-3 rounded-lg border border-[#ddd6c3] p-4 md:grid-cols-[1fr_auto]">
              <div>
                <div className="flex flex-wrap items-center gap-2">
                  <h3 className="text-lg font-semibold">{item.name}</h3>
                  <Status status={item.status} />
                </div>
                <p className="mt-2 text-sm leading-6 text-[#605a4d]">{item.reason}</p>
              </div>
              <div className="self-center rounded-md bg-[#151713] px-4 py-2 text-sm font-semibold text-white">
                {item.sets}
              </div>
            </div>
          ))}
        </div>
      </div>

      <div className="rounded-lg bg-[#151713] p-5 text-white shadow-sm">
        <div className="flex items-center gap-2 text-[#65ffd2]">
          <ShieldCheck className="size-5" />
          <h2 className="text-lg font-semibold">Safety gate</h2>
        </div>
        <p className="mt-4 leading-7 text-white/76">
          Impact and deep loaded knee flexion are blocked before the workout plan is assembled.
        </p>
        <div className="mt-5 space-y-3">
          <Evidence label="Allowed" value="hinge, banded glute work, slow squats" />
          <Evidence label="Blocked" value="jump squats, deep loaded flexion" />
          <Evidence label="Reason" value="left knee recovery context" />
        </div>
      </div>
    </section>
  );
}

function CoachPanel({ complete }: { complete: boolean }) {
  return (
    <section className="grid gap-5 xl:grid-cols-[minmax(0,1fr)_23rem]">
      <div className="rounded-lg bg-white p-5 shadow-sm">
        <div className="flex items-center gap-2 text-[#2d3a18]">
          <MessageSquare className="size-5" />
          <h2 className="text-2xl font-semibold tracking-[-0.02em]">Coach console</h2>
        </div>
        <div className="mt-5 rounded-lg border border-[#ddd6c3] bg-[#f8f6ef] p-5">
          <p className="text-sm font-semibold uppercase tracking-[0.16em] text-[#716c5f]">
            Draft check-in
          </p>
          <p className="mt-3 text-lg leading-8">
            Jordan completed a controlled squat set with one corrected knee-tracking cue. Keep the next
            session hinge-dominant and avoid impact work.
          </p>
        </div>
        <div className="mt-4 grid gap-3 md:grid-cols-3">
          <CoachAction icon={CheckCircle2} label={complete ? "Approve summary" : "Wait for set"} />
          <CoachAction icon={FileText} label="Open rationale" />
          <CoachAction icon={Sparkles} label="Draft next plan" />
        </div>
      </div>

      <div className="rounded-lg bg-[#fffbef] p-5 shadow-sm">
        <h3 className="text-lg font-semibold">Coach context</h3>
        <div className="mt-4 space-y-3">
          <Evidence label="Adherence" value="3 of 4 sessions this week" />
          <Evidence label="Sleep" value="6.7h average, trending up" />
          <Evidence label="Form" value="knee drift corrected in-session" />
          <Evidence label="Next step" value="progress to loaded hinge" />
        </div>
      </div>
    </section>
  );
}

function GraphPanel() {
  return (
    <section className="grid gap-5 xl:grid-cols-[minmax(0,1fr)_23rem]">
      <div className="rounded-lg bg-[#151713] p-5 text-white shadow-sm">
        <div className="flex items-center gap-2 text-[#d7ff5f]">
          <BrainCircuit className="size-5" />
          <h2 className="text-2xl font-semibold tracking-[-0.02em]">Reasoning graph</h2>
        </div>
        <div className="mt-5 grid gap-3 md:grid-cols-2">
          {graphEdges.map(([from, relation, to]) => (
            <div key={`${from}-${to}`} className="rounded-lg border border-white/12 bg-white/7 p-4">
              <div className="text-sm font-semibold text-[#65ffd2]">{from}</div>
              <div className="my-2 text-xs uppercase tracking-[0.16em] text-white/42">{relation}</div>
              <div className="text-lg font-semibold">{to}</div>
            </div>
          ))}
        </div>
      </div>

      <div className="rounded-lg bg-white p-5 shadow-sm">
        <h3 className="text-lg font-semibold">Audit trail</h3>
        <div className="mt-4 space-y-3">
          <Evidence label="Facts" value="18 member facts loaded" />
          <Evidence label="Rules" value="6 safety rules checked" />
          <Evidence label="Blocks" value="2 movements filtered" />
          <Evidence label="Output" value="coach-readable rationale" />
        </div>
      </div>
    </section>
  );
}

function HistoryPanel() {
  return (
    <section className="rounded-lg bg-white p-5 shadow-sm">
      <div className="flex items-center gap-2 text-[#2d3a18]">
        <HeartPulse className="size-5" />
        <h2 className="text-2xl font-semibold tracking-[-0.02em]">Training history</h2>
      </div>
      <div className="mt-5 divide-y divide-[#ddd6c3]">
        {history.map(([date, title, detail]) => (
          <div key={`${date}-${title}`} className="grid gap-3 py-4 md:grid-cols-[8rem_1fr]">
            <div className="font-mono text-sm text-[#716c5f]">{date}</div>
            <div>
              <h3 className="font-semibold">{title}</h3>
              <p className="mt-1 text-sm leading-6 text-[#605a4d]">{detail}</p>
            </div>
          </div>
        ))}
      </div>
    </section>
  );
}

function Status({ status }: { status: string }) {
  const styles =
    status === "blocked"
      ? "bg-[#ffe8d6] text-[#8b3614]"
      : status === "live"
        ? "bg-[#d7ff5f] text-[#151713]"
        : "bg-[#e4f9f0] text-[#17573f]";

  return <span className={cx("rounded-full px-3 py-1 text-xs font-semibold uppercase tracking-[0.12em]", styles)}>{status}</span>;
}

function Evidence({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-md border border-current/10 bg-current/[0.035] p-3">
      <div className="text-xs font-semibold uppercase tracking-[0.16em] opacity-50">{label}</div>
      <div className="mt-1 text-sm font-medium leading-6">{value}</div>
    </div>
  );
}

function CoachAction({ icon: Icon, label }: { icon: typeof Target; label: string }) {
  return (
    <button
      type="button"
      className="inline-flex min-h-12 items-center justify-center gap-2 rounded-md bg-[#151713] px-4 py-3 text-sm font-semibold text-white"
    >
      <Icon className="size-4 text-[#d7ff5f]" />
      {label}
    </button>
  );
}
