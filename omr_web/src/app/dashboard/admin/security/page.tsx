import Link from "next/link";

import { Card } from "@/components/ui/card";
import { fetchAuthEvents } from "@/lib/api/admin";
import { requireSuperAdminSession } from "@/lib/api/session";

function formatEvent(event: string): string {
  return event.replaceAll("_", " ");
}

function formatWhen(iso: string): string {
  try {
    return new Date(iso).toLocaleString();
  } catch {
    return iso;
  }
}

export default async function AdminSecurityPage({
  searchParams,
}: {
  searchParams: Promise<{ email?: string; event?: string }>;
}) {
  const { api } = await requireSuperAdminSession();
  const params = await searchParams;
  const email = params.email?.trim() ?? "";
  const event = params.event?.trim() ?? "";

  let events: Awaited<ReturnType<typeof fetchAuthEvents>> = [];
  let loadError: string | null = null;

  try {
    events = await fetchAuthEvents(api, { email: email || undefined, event: event || undefined });
  } catch {
    loadError = "Could not load sign-in activity. The school server may be waking up — refresh in a minute.";
  }

  return (
    <>
      <div className="mb-6">
        <h1 className="text-2xl font-extrabold text-slate-800">Sign-in activity</h1>
        <p className="mt-1 text-sm text-slate-500">
          Recent sign-in attempts, lockouts, and two-factor events. Use this to spot unusual activity.
        </p>
        <p className="mt-2 text-sm">
          <Link href="/dashboard/admin" className="font-semibold text-emerald-700 hover:underline">
            ← Back to school overview
          </Link>
        </p>
      </div>

      <Card title="Filter" className="mb-4">
        <form className="flex flex-wrap items-end gap-3" method="get">
          <div>
            <label htmlFor="email" className="mb-1 block text-xs font-bold uppercase text-slate-500">
              Email contains
            </label>
            <input
              id="email"
              name="email"
              defaultValue={email}
              className="rounded-lg border border-slate-200 px-3 py-2 text-sm"
              placeholder="teacher@coc.edu.ph"
            />
          </div>
          <div>
            <label htmlFor="event" className="mb-1 block text-xs font-bold uppercase text-slate-500">
              Event
            </label>
            <select
              id="event"
              name="event"
              defaultValue={event}
              className="rounded-lg border border-slate-200 px-3 py-2 text-sm"
            >
              <option value="">All events</option>
              <option value="login_failed">login failed</option>
              <option value="login_success">login success</option>
              <option value="login_locked">login locked</option>
              <option value="mfa_failed">mfa failed</option>
              <option value="mfa_success">mfa success</option>
              <option value="register">register</option>
              <option value="password_reset_requested">password reset requested</option>
            </select>
          </div>
          <button
            type="submit"
            className="rounded-xl bg-emerald-700 px-4 py-2 text-sm font-bold text-white hover:bg-emerald-800"
          >
            Apply
          </button>
        </form>
      </Card>

      {loadError ? (
        <div className="mb-4 rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900">
          {loadError}
        </div>
      ) : null}

      <Card title="Recent events">
        {events.length === 0 ? (
          <p className="text-sm text-slate-500">No matching events yet.</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="min-w-full text-sm">
              <thead>
                <tr className="border-b text-xs font-bold uppercase text-slate-500">
                  <th className="px-2 py-2 text-left">When</th>
                  <th className="px-2 py-2 text-left">Event</th>
                  <th className="px-2 py-2 text-left">Email</th>
                  <th className="px-2 py-2 text-left">IP</th>
                </tr>
              </thead>
              <tbody>
                {events.map((row) => (
                  <tr key={row.id} className="border-b border-slate-100">
                    <td className="px-2 py-2 whitespace-nowrap text-slate-600">
                      {formatWhen(row.created_at)}
                    </td>
                    <td className="px-2 py-2">
                      <span className="rounded-full bg-slate-100 px-2 py-0.5 text-xs font-bold capitalize text-slate-700">
                        {formatEvent(row.event)}
                      </span>
                    </td>
                    <td className="px-2 py-2 font-medium text-slate-800">{row.email}</td>
                    <td className="px-2 py-2 text-slate-500">{row.ip_address ?? "—"}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>
    </>
  );
}
