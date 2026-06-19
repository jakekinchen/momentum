import { NextRequest, NextResponse } from "next/server";

const macInfoPath = "/download/mac";

function isMacDesktop(userAgent: string) {
  const ua = userAgent.toLowerCase();
  const looksLikeMac = ua.includes("macintosh") || ua.includes("mac os x");
  const looksMobile =
    ua.includes("mobile") ||
    ua.includes("iphone") ||
    ua.includes("ipad") ||
    ua.includes("ipod") ||
    ua.includes("android");

  return looksLikeMac && !looksMobile;
}

export function GET(request: NextRequest) {
  const downloadUrl =
    process.env.MOMENTUM_DOWNLOAD_URL?.trim() ??
    process.env.NEXT_PUBLIC_MOMENTUM_DOWNLOAD_URL?.trim();

  if (!downloadUrl) {
    return NextResponse.redirect(new URL(`${macInfoPath}?status=unavailable`, request.url));
  }

  const userAgent = request.headers.get("user-agent") ?? "";
  if (!isMacDesktop(userAgent)) {
    return NextResponse.redirect(new URL(macInfoPath, request.url));
  }

  return NextResponse.redirect(downloadUrl);
}
