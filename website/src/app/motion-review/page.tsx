import type { Metadata } from "next";

import { getMotionReviewData } from "@/lib/motionReview";

import { MotionReviewGallery } from "./MotionReviewGallery";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

export const metadata: Metadata = {
  title: "Momentum Motion Review",
  description:
    "Local review gallery for Momentum motion demos, detector videos, and validation manifests.",
};

export default function MotionReviewPage() {
  const data = getMotionReviewData();

  return <MotionReviewGallery data={data} />;
}
