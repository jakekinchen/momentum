import Link from "next/link";

export default function MacDownloadPage() {
  const downloadUrl =
    process.env.MOMENTUM_DOWNLOAD_URL?.trim() ??
    process.env.NEXT_PUBLIC_MOMENTUM_DOWNLOAD_URL?.trim();

  return (
    <main className="min-h-svh bg-[#efede5] px-5 py-8 text-[#171713] md:px-8">
      <div className="mx-auto flex min-h-[calc(100svh-4rem)] max-w-5xl flex-col">
        <nav className="flex items-center justify-between text-sm">
          <Link href="/" className="font-semibold">
            Momentum
          </Link>
          <Link
            href="/"
            className="rounded-full border border-[#171713]/15 px-5 py-2 font-medium"
          >
            Home
          </Link>
        </nav>

        <section className="flex flex-1 flex-col justify-center py-20">
          <p className="text-sm font-semibold uppercase tracking-[0.18em] text-[#777267]">
            Mac app
          </p>
          <h1 className="mt-5 max-w-4xl font-serif text-[clamp(3.4rem,12vw,7.4rem)] font-normal leading-[0.92] tracking-[-0.035em]">
            Download Momentum for Mac
          </h1>
          <p className="mt-7 max-w-xl text-lg leading-8 text-[#5d594f]">
            Momentum ships as a signed, notarized DMG. Open the installer on a
            Mac and drag Momentum into Applications.
          </p>
          <div className="mt-10 flex flex-col gap-3 sm:flex-row">
            {downloadUrl ? (
              <a
                href={downloadUrl}
                className="inline-flex rounded-full bg-[#171713] px-8 py-4 text-base font-medium text-white shadow-[0_18px_42px_rgba(23,23,19,0.18)]"
              >
                Download DMG
              </a>
            ) : (
              <span className="inline-flex rounded-full bg-[#171713] px-8 py-4 text-base font-medium text-white shadow-[0_18px_42px_rgba(23,23,19,0.18)]">
                Coming Soon
              </span>
            )}
            <Link
              href="/"
              className="inline-flex rounded-full border border-[#171713]/15 px-8 py-4 text-base font-medium text-[#171713]"
            >
              Back to Site
            </Link>
          </div>
        </section>
      </div>
    </main>
  );
}
