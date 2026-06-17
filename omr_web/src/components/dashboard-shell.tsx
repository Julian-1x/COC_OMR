"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import {
  BookOpen,
  ClipboardList,
  GraduationCap,
  Home,
  LogOut,
  RefreshCw,
  Settings,
  BarChart3,
  Shield,
} from "lucide-react";
import { BrandHeader } from "@/components/brand";
import {
  parsePortalMode,
  portalModeCookieValue,
  PORTAL_MODE_COOKIE,
  type PortalMode,
} from "@/lib/portal-mode";
import { cn } from "@/lib/utils";

const teacherNav = [
  { href: "/dashboard", label: "Home", icon: Home },
  { href: "/dashboard/classes", label: "Classes", icon: GraduationCap },
  { href: "/dashboard/prepare", label: "Prepare", icon: BookOpen },
  { href: "/dashboard/results", label: "Results", icon: BarChart3 },
  { href: "/dashboard/settings", label: "Settings", icon: Settings },
];

const adminNav = [
  { href: "/dashboard/admin", label: "Admin", icon: Shield },
  { href: "/dashboard/sync-check", label: "Sync check", icon: RefreshCw },
  { href: "/dashboard/settings", label: "Settings", icon: Settings },
];

function readPortalModeCookie(): PortalMode {
  if (typeof document === "undefined") return "teacher";
  const match = document.cookie
    .split("; ")
    .find((row) => row.startsWith(`${PORTAL_MODE_COOKIE}=`));
  return parsePortalMode(match?.split("=")[1]);
}

function PortalModeSwitch({
  mode,
  onChange,
}: {
  mode: PortalMode;
  onChange: (mode: PortalMode) => void;
}) {
  return (
    <div className="mt-4 rounded-xl bg-slate-100 p-1">
      <div className="grid grid-cols-2 gap-1">
        <button
          type="button"
          onClick={() => onChange("teacher")}
          className={cn(
            "rounded-lg px-2 py-2 text-xs font-bold transition",
            mode === "teacher"
              ? "bg-white text-emerald-800 shadow-sm"
              : "text-slate-600 hover:text-slate-900",
          )}
        >
          Teacher desk
        </button>
        <button
          type="button"
          onClick={() => onChange("admin")}
          className={cn(
            "rounded-lg px-2 py-2 text-xs font-bold transition",
            mode === "admin"
              ? "bg-white text-emerald-800 shadow-sm"
              : "text-slate-600 hover:text-slate-900",
          )}
        >
          School admin
        </button>
      </div>
    </div>
  );
}

export function DashboardShell({
  children,
  teacherName,
  schoolName,
  isAdmin = false,
  initialMode = "teacher",
}: {
  children: React.ReactNode;
  teacherName?: string;
  schoolName?: string;
  isAdmin?: boolean;
  initialMode?: PortalMode;
}) {
  const pathname = usePathname();
  const router = useRouter();
  const [mode, setMode] = useState<PortalMode>(initialMode);

  useEffect(() => {
    setMode(readPortalModeCookie());
  }, []);

  const subtitle = isAdmin && mode === "admin" ? "School admin" : "Teacher portal";
  const nav = isAdmin && mode === "admin" ? adminNav : teacherNav;

  function switchMode(next: PortalMode) {
    document.cookie = portalModeCookieValue(next);
    setMode(next);
    router.push(next === "admin" ? "/dashboard/admin" : "/dashboard");
    router.refresh();
  }

  async function signOut() {
    await fetch("/auth/signout", { method: "POST" });
    router.push("/login");
    router.refresh();
  }

  return (
    <div className="min-h-screen bg-slate-50">
      <div className="mx-auto flex min-h-screen max-w-7xl">
        <aside className="hidden w-64 shrink-0 flex-col border-r border-slate-200 bg-white p-5 lg:flex">
          <BrandHeader subtitle={subtitle} />
          <p className="mt-4 text-xs font-semibold text-slate-500">
            {teacherName}
            {schoolName ? ` · ${schoolName}` : ""}
          </p>
          {isAdmin ? <PortalModeSwitch mode={mode} onChange={switchMode} /> : null}
          <nav className="mt-6 flex flex-1 flex-col gap-1">
            {nav.map((item) => {
              const active = pathname === item.href || pathname.startsWith(`${item.href}/`);
              const Icon = item.icon;
              return (
                <Link
                  key={item.href}
                  href={item.href}
                  className={cn(
                    "flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-bold transition",
                    active
                      ? "bg-emerald-50 text-emerald-800"
                      : "text-slate-600 hover:bg-slate-50 hover:text-slate-900",
                  )}
                >
                  <Icon className="h-4 w-4" />
                  {item.label}
                </Link>
              );
            })}
          </nav>
          <button
            type="button"
            onClick={signOut}
            className="mt-4 flex items-center gap-2 rounded-xl px-3 py-2.5 text-sm font-bold text-slate-500 hover:bg-red-50 hover:text-red-700"
          >
            <LogOut className="h-4 w-4" />
            Sign out
          </button>
        </aside>

        <div className="flex min-w-0 flex-1 flex-col">
          <header className="border-b border-slate-200 bg-white px-4 py-3 lg:hidden">
            <BrandHeader subtitle={subtitle} />
            {isAdmin ? (
              <div className="mt-3">
                <PortalModeSwitch mode={mode} onChange={switchMode} />
              </div>
            ) : null}
            <div className="mt-3 flex gap-2 overflow-x-auto pb-1">
              {nav.map((item) => {
                const active = pathname === item.href || pathname.startsWith(`${item.href}/`);
                return (
                  <Link
                    key={item.href}
                    href={item.href}
                    className={cn(
                      "shrink-0 rounded-full px-3 py-1.5 text-xs font-bold",
                      active ? "bg-emerald-500 text-white" : "bg-slate-100 text-slate-600",
                    )}
                  >
                    {item.label}
                  </Link>
                );
              })}
            </div>
          </header>
          <main className="flex-1 p-4 md:p-6">{children}</main>
        </div>
      </div>
    </div>
  );
}

export function EmptyState({
  title,
  body,
  icon: Icon = ClipboardList,
}: {
  title: string;
  body: string;
  icon?: React.ComponentType<{ className?: string }>;
}) {
  return (
    <div className="rounded-2xl border border-dashed border-slate-300 bg-white p-8 text-center">
      <Icon className="mx-auto h-10 w-10 text-emerald-500" />
      <h3 className="mt-3 text-base font-extrabold text-slate-800">{title}</h3>
      <p className="mt-2 text-sm text-slate-500">{body}</p>
    </div>
  );
}
