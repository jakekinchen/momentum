import { readFile } from "fs/promises";

import {
  type MotionMediaAsset,
  resolveMotionMediaFile,
  resolveMotionMediaRedirect,
} from "@/lib/motionReview";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

const allowedAssets = new Set<MotionMediaAsset>([
  "contact-sheet",
  "detector-video",
  "source-video",
]);

export async function GET(
  _request: Request,
  context: { params: Promise<{ exerciseId: string; asset: string }> },
) {
  const { exerciseId, asset } = await context.params;

  if (!allowedAssets.has(asset as MotionMediaAsset)) {
    return new Response("Unknown media asset", { status: 404 });
  }

  const media = resolveMotionMediaFile(exerciseId, asset as MotionMediaAsset);
  if (!media) {
    const redirect = resolveMotionMediaRedirect(exerciseId, asset as MotionMediaAsset);
    if (redirect) {
      return Response.redirect(redirect, 302);
    }

    return new Response("Media asset not found", { status: 404 });
  }

  const body = await readFile(media.path);

  return new Response(body, {
    headers: {
      "Cache-Control": "no-store",
      "Content-Type": media.contentType,
      "Content-Length": String(body.byteLength),
    },
  });
}
