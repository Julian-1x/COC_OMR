import { NextResponse, type NextRequest } from "next/server";

/** @deprecated Supabase middleware removed — see src/middleware.ts */
export async function updateSession(request: NextRequest) {
  return NextResponse.next({ request });
}
