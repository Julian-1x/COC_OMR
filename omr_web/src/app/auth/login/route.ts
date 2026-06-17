import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import { NextResponse } from "next/server";
import { getSupabaseServerEnv } from "@/lib/supabase/env";

async function makeClient() {
  const cookieStore = await cookies();
  const { url, key } = getSupabaseServerEnv();

  return createServerClient(url, key, {
    cookies: {
      getAll() {
        return cookieStore.getAll();
      },
      setAll(cookiesToSet) {
        cookiesToSet.forEach(({ name, value, options }) =>
          cookieStore.set(name, value, options),
        );
      },
    },
  });
}

export async function POST(request: Request) {
  try {
    const body = (await request.json()) as {
      mode?: "login" | "register";
      email?: string;
      password?: string;
      name?: string;
      school?: string;
    };

    const mode = body.mode ?? "login";
    const email = body.email?.trim().toLowerCase() ?? "";
    const password = body.password ?? "";

    if (!email || !password) {
      return NextResponse.json({ error: "Email and password are required." }, { status: 400 });
    }

    const supabase = await makeClient();

    if (mode === "register") {
      const name = body.name?.trim() ?? "";
      const school = body.school?.trim() ?? "";
      if (!name || !school) {
        return NextResponse.json(
          { error: "Name and school are required for registration." },
          { status: 400 },
        );
      }

      const { error } = await supabase.auth.signUp({
        email,
        password,
        options: {
          data: {
            full_name: name,
            school,
            role: "teacher",
          },
        },
      });

      if (error) {
        return NextResponse.json({ error: error.message }, { status: 400 });
      }

      return NextResponse.json({ ok: true });
    }

    const { error } = await supabase.auth.signInWithPassword({ email, password });
    if (error) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }

    return NextResponse.json({ ok: true });
  } catch (error) {
    const message =
      error instanceof Error ? error.message : "Could not reach Supabase. Check your internet.";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
