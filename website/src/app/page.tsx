import Image from "next/image";

import { HeroWorkoutVideo } from "./HeroWorkoutVideo";

const coachingPillars = [
  {
    title: "Made for the Mac",
    text: "A focused desktop coaching surface built around your camera, your session, and your privacy.",
  },
  {
    title: "Move with feedback",
    text: "The movement loop turns form into reps, holds, tempo, and simple cues while you train.",
  },
  {
    title: "Plans that adapt",
    text: "Workout plans stay tied to your goals, schedule, equipment, and training history.",
  },
  {
    title: "Coach context",
    text: "Every recommendation can point back to the reason it belongs in the session.",
  },
];

const profileDetails = ["Schedule", "Equipment", "Experience", "Injury history", "Goals"];

const proofPoints = [
  "The movement preview is rendered from the macOS app source.",
  "The coach plan is grounded in goals, constraints, and local training context.",
  "The release candidate includes runnable movement demos for form review.",
];

export default function Home() {
  const hasDownload = Boolean(
    process.env.MOMENTUM_DOWNLOAD_URL?.trim() ??
      process.env.NEXT_PUBLIC_MOMENTUM_DOWNLOAD_URL?.trim(),
  );
  const demoHref = "/demo";
  const downloadHref = "/download";
  const downloadLabel = "Download for Mac";
  const heroCtaLabel = "Try Browser Demo";
  const heroCtaHref = demoHref;
  const finalCtaLabel = "Try Browser Demo";
  const finalCtaHref = demoHref;

  return (
    <main className="bg-[#efede5] text-[#171713]">
      <section className="relative isolate min-h-[96svh] overflow-hidden bg-[#85837f] px-5 text-white md:px-8">
        <Image
          src="/app-assets/motion/bodyweight-lunge-hero.jpg"
          alt=""
          fill
          priority
          sizes="100vw"
          className="absolute inset-0 -z-20 object-cover object-[57%_42%] opacity-70 saturate-[0.55] contrast-[0.92] md:object-[56%_43%]"
        />
        <div className="absolute inset-0 -z-10 bg-[#5f5e59]/76" />
        <div className="absolute inset-0 -z-10 bg-[linear-gradient(180deg,rgba(31,30,28,0.26),rgba(31,30,28,0.04)_34%,rgba(31,30,28,0.5)_100%)]" />
        <div className="absolute inset-x-0 bottom-0 -z-10 h-56 bg-[linear-gradient(180deg,rgba(133,131,127,0),rgba(74,70,66,0.58))]" />

        <div className="relative mx-auto flex min-h-[96svh] max-w-[94rem] flex-col">
          <nav className="grid grid-cols-3 items-center py-8 text-sm">
            <a href="#top" className="justify-self-start text-white" aria-label="Momentum home">
              <span className="grid size-9 place-items-center rounded-md border border-white/18 bg-white/8 backdrop-blur">
                <Image
                  src="/app-assets/brand/future.svg"
                  alt=""
                  width={18}
                  height={24}
                  priority
                  className="h-6 w-auto"
                />
              </span>
            </a>
            <a href="#top" className="justify-self-center text-2xl font-semibold text-white">
              Momentum
            </a>
            <div className="hidden justify-self-end items-center gap-8 md:flex">
              <a href="#coach" className="text-white/88">
                Coach
              </a>
              <a href="#proof" className="text-white/88">
                Proof
              </a>
              <a href={demoHref} className="text-white/88">
                Demo
              </a>
              {hasDownload ? (
                <a
                  href={downloadHref}
                  className="rounded-full bg-white px-6 py-3 font-medium text-[#1e1e1a] shadow-[0_10px_34px_rgba(0,0,0,0.18)]"
                >
                  {downloadLabel}
                </a>
              ) : null}
            </div>
            <a
              href={demoHref}
              className="justify-self-end rounded-full bg-white px-4 py-2 text-sm font-medium text-[#1e1e1a] shadow-[0_10px_34px_rgba(0,0,0,0.18)] md:hidden"
            >
              Demo
            </a>
          </nav>

          <div id="top" className="flex flex-1 flex-col items-center pt-6 text-center md:pt-10">
            <h1 className="max-w-6xl font-serif text-[clamp(3.25rem,9vw,7.8rem)] font-normal leading-[0.92] tracking-[-0.035em]">
              Personal coaching, reimagined
            </h1>
            <p className="mt-7 max-w-xl text-base leading-7 text-white/88 md:text-lg">
              Dedicated movement feedback and coach context for training on
              your Mac.
            </p>
            <div className="mt-9 flex flex-col items-center gap-4">
              <a
                href={heroCtaHref}
                className="rounded-full bg-white px-10 py-4 text-base font-medium text-[#191916] shadow-[0_18px_42px_rgba(0,0,0,0.22)]"
              >
                {heroCtaLabel}
              </a>
              {hasDownload ? (
                <a href={downloadHref} className="text-sm font-medium text-white/84">
                  {downloadLabel}
                </a>
              ) : null}
              <p className="max-w-[18rem] text-sm font-medium leading-5 text-white">
                Form feedback, workouts, and coach context.
                <br />
                Built for the Mac.
              </p>
            </div>

            <div className="mt-8 w-full max-w-[64rem] md:mt-10">
              <div className="mx-auto overflow-hidden rounded-[1.25rem] border border-white/28 bg-[#101311] shadow-[0_26px_90px_rgba(0,0,0,0.42)] ring-1 ring-black/20">
                <HeroWorkoutVideo />
              </div>
            </div>
          </div>
        </div>
      </section>

      <section id="coach" className="bg-[#aaa8a0] px-5 py-20 md:px-8 md:py-28">
        <div className="mx-auto max-w-7xl">
          <div className="text-center text-white">
            <h2 className="font-serif text-[clamp(3rem,7vw,6.2rem)] font-normal leading-[0.95] tracking-[-0.035em]">
              Together, your training has context
            </h2>
            <a
              href={hasDownload ? downloadHref : demoHref}
              className="mt-10 inline-flex rounded-full bg-white px-9 py-4 text-base font-medium text-[#171713] shadow-[0_16px_34px_rgba(0,0,0,0.12)]"
            >
              {hasDownload ? downloadLabel : "Browser Demo"}
            </a>
          </div>

          <div className="mt-14 grid gap-4 md:grid-cols-2 lg:grid-cols-4">
            {coachingPillars.map((pillar) => (
              <article key={pillar.title} className="rounded-lg bg-[#f3f0e8] p-6 shadow-sm">
                <h3 className="font-serif text-3xl leading-none tracking-[-0.025em]">
                  {pillar.title}
                </h3>
                <p className="mt-5 text-base leading-7 text-[#5b574f]">{pillar.text}</p>
              </article>
            ))}
          </div>
        </div>
      </section>

      <section className="bg-[#efede5] px-5 py-20 md:px-8 md:py-28">
        <div className="mx-auto grid max-w-7xl gap-12 lg:grid-cols-[0.85fr_1.15fr] lg:items-center">
          <div>
            <p className="text-sm font-semibold uppercase tracking-[0.18em] text-[#777267]">
              Personalized plan
            </p>
            <h2 className="mt-5 max-w-3xl font-serif text-[clamp(3rem,6vw,5.8rem)] font-normal leading-[0.96] tracking-[-0.035em]">
              A roadmap that is uniquely yours
            </h2>
            <p className="mt-7 max-w-xl text-lg leading-8 text-[#5d594f]">
              The coach surface stays simple. Underneath, Momentum ties movement
              choices to schedule, equipment, goals, safety, and local
              observations.
            </p>
          </div>

          <div className="rounded-lg bg-[#171713] p-4 text-white shadow-[0_22px_70px_rgba(45,41,34,0.18)]">
            <div className="rounded-md border border-white/10 bg-[#0d100e] p-4">
              <video
                className="block aspect-[640/272] w-full rounded-md object-cover"
                autoPlay
                loop
                muted
                playsInline
                preload="metadata"
                poster="/app-assets/onboarding/movement-tracking-swiftui-poster.jpg"
                aria-label="Momentum movement tracking preview"
              >
                <source
                  src="/app-assets/onboarding/movement-tracking-swiftui.webm"
                  type="video/webm"
                />
                <source
                  src="/app-assets/onboarding/movement-tracking-swiftui.mp4"
                  type="video/mp4"
                />
              </video>
            </div>
            <div className="mt-4 grid gap-3 sm:grid-cols-5">
              {profileDetails.map((item) => (
                <div key={item} className="rounded-md bg-white/9 px-4 py-4">
                  <div className="text-sm font-semibold">{item}</div>
                </div>
              ))}
            </div>
          </div>
        </div>
      </section>

      <section id="proof" className="bg-[#171713] px-5 py-20 text-white md:px-8 md:py-28">
        <div className="mx-auto grid max-w-7xl gap-12 lg:grid-cols-[0.95fr_1.05fr]">
          <div>
            <p className="text-sm font-semibold uppercase tracking-[0.18em] text-white/48">
              Proof before polish
            </p>
            <h2 className="mt-5 font-serif text-[clamp(3rem,6vw,5.8rem)] font-normal leading-[0.96] tracking-[-0.035em]">
              Built for a release candidate, not a mockup
            </h2>
          </div>
          <div className="space-y-4">
            {proofPoints.map((point) => (
              <div key={point} className="rounded-lg border border-white/12 bg-white/7 p-5">
                <p className="text-lg leading-7 text-white/82">{point}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      <section id="start" className="bg-[#efede5] px-5 py-20 text-center md:px-8 md:py-28">
        <div className="mx-auto max-w-4xl">
          <h2 className="font-serif text-[clamp(3rem,7vw,6rem)] font-normal leading-none tracking-[-0.035em]">
            Momentum for local training
          </h2>
          <p className="mx-auto mt-7 max-w-xl text-lg leading-8 text-[#5d594f]">
            Your future coach for movement feedback, workouts, and training
            context on your Mac.
          </p>
          <a
            href={finalCtaHref}
            className="mt-10 inline-flex rounded-full bg-[#171713] px-10 py-4 text-base font-medium text-white shadow-[0_18px_42px_rgba(23,23,19,0.18)]"
          >
            {finalCtaLabel}
          </a>
          {hasDownload ? (
            <a href={downloadHref} className="ml-0 mt-4 inline-flex px-5 py-3 text-base font-medium text-[#5d594f] md:ml-3">
              {downloadLabel}
            </a>
          ) : null}
        </div>
      </section>
    </main>
  );
}
