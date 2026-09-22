"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import {
  BookOpen,
  BarChart3,
  ClipboardList,
  GraduationCap,
  Home,
  LogOut,
  Menu,
  Settings,
  Shield,
  ArrowRightLeft,
  Users,
  X,
} from "lucide-react";
import { BrandHeader, CocLogo } from "@/components/brand";
import {
  parsePortalMode,
  portalModeCookieValue,
  PORTAL_MODE_COOKIE,
  type PortalMode,
} from "@/lib/portal-mode";
import { cn } from "@/lib/utils";

type NavItem = {
  href: string;
  label: string;
  icon: React.ComponentType<{ className?: string }>;
  exact?: boolean;
};

const teacherNav: NavItem[] = [
  { href: "/dashboard", label: "Home", icon: Home, exact: true },
  { href: "/dashboard/classes", label: "Classes", icon: GraduationCap },
  { href: "/dashboard/prepare", label: "Prepare", icon: BookOpen },
  { href: "/dashboard/results", label: "Results", icon: BarChart3 },
  { href: "/dashboard/settings", label: "Settings", icon: Settings },
];

const adminNavBase: NavItem[] = [
  { href: "/dashboard/admin", label: "Overview", icon: Shield, exact: true },
  { href: "/dashboard/admin/access", label: "Access", icon: ClipboardList },
];

const adminNavSuper: NavItem[] = [
  { href: "/dashboard/admin/departments", label: "Dept admins", icon: Users },
  { href: "/dashboard/admin/security", label: "Sign-in log", icon: Shield },
  { href: "/dashboard/admin/transfer", label: "Transfer", icon: ArrowRightLeft },
];

const adminNavTail: NavItem[] = [
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
  className = "",
}: {
  mode: PortalMode;
  onChange: (mode: PortalMode) => void;
  className?: string;
}) {
  return (
    <div className={cn("rounded-xl bg-slate-100 p-1", className)}>
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
          Admin desk
        </button>
      </div>
    </div>
  );
}

function navItemActive(pathname: string, href: string, exact?: boolean): boolean {
  if (exact) return pathname === href;
  return pathname === href || pathname.startsWith(`${href}/`);
}

export function DashboardShell({
  children,
  teacherName,
  schoolName,
  isAdmin = false,
  isSuperAdmin = false,
  initialMode = "teacher",
}: {
  children: React.ReactNode;
  teacherName?: string;
  schoolName?: string;
  isAdmin?: boolean;
  isSuperAdmin?: boolean;
  initialMode?: PortalMode;
}) {
  const pathname = usePathname();
  const router = useRouter();
  const [mode, setMode] = useState<PortalMode>(initialMode);
  const [menuOpen, setMenuOpen] = useState(false);

  // Desk chrome must match the URL so Admin nav never wraps Teacher pages.
  useEffect(() => {
    if (!isAdmin) return;
    const onAdminRoute = pathname.startsWith("/dashboard/admin");
    const onSharedSettings =
      pathname === "/dashboard/settings" || pathname.startsWith("/dashboard/settings/");

    if (onAdminRoute) {
      document.cookie = portalModeCookieValue("admin");
      if (mode !== "admin") setMode("admin");
      return;
    }

    if (onSharedSettings) {
      const cookieMode = readPortalModeCookie();
      if (cookieMode !== mode) setMode(cookieMode);
      return;
    }

    // Any other /dashboard* route is Teacher desk content.
    document.cookie = portalModeCookieValue("teacher");
    if (mode !== "teacher") setMode("teacher");
  }, [pathname, isAdmin, mode]);

  useEffect(() => {
    setMenuOpen(false);
  }, [pathname]);

  const subtitle = isAdmin && mode === "admin" ? "Admin monitoring" : "Teacher desk";
  const adminNav = [...adminNavBase, ...(isSuperAdmin ? adminNavSuper : []), ...adminNavTail];
  const nav = isAdmin && mode === "admin" ? adminNav : teacherNav;
  // Bottom bar: keep 4 primary tabs; Settings lives in the menu on phone.
  const bottomNav =
    isAdmin && mode === "admin"
      ? adminNav.filter((item) => item.href !== "/dashboard/settings").slice(0, 4)
      : teacherNav.filter((item) => item.href !== "/dashboard/settings");

  function switchMode(next: PortalMode) {
    setMenuOpen(false);
    if (next === "admin") {
      // Navigate first; cookie is set when /dashboard/admin* actually loads.
      // Avoids Admin chrome stuck on Teacher home if admin route redirects.
      router.push("/dashboard/admin");
      router.refresh();
      return;
    }
    document.cookie = portalModeCookieValue("teacher");
    setMode("teacher");
    router.push("/dashboard");
    router.refresh();
  }

  async function signOut() {
    setMenuOpen(false);
    await fetch("/auth/signout", { method: "POST" });
    router.push("/login");
    router.refresh();
  }

  return (
    <div className="min-h-dvh bg-slate-50">
      <div className="mx-auto flex min-h-dvh max-w-7xl">
        {/* Desktop sidebar */}
        <aside className="hidden w-64 shrink-0 flex-col border-r border-slate-200 bg-white p-5 lg:flex">
          <BrandHeader subtitle={subtitle} />
          <p className="mt-4 text-xs font-semibold text-slate-500">
            {teacherName}
            {schoolName ? ` · ${schoolName}` : ""}
          </p>
          {isAdmin ? <PortalModeSwitch mode={mode} onChange={switchMode} className="mt-4" /> : null}
          <nav className="mt-6 flex flex-1 flex-col gap-1">
            {nav.map((item) => {
              const active = navItemActive(pathname, item.href, item.exact);
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
          {/* Phone / tablet header */}
          <header className="sticky top-0 z-40 border-b border-slate-200 bg-white/95 px-3 py-2 backdrop-blur lg:hidden">
            <div className="flex items-center gap-2">
              <CocLogo size={36} />
              <div className="min-w-0 flex-1">
                <p className="truncate text-sm font-extrabold text-slate-800">COC OMR</p>
                <p className="truncate text-[11px] font-semibold text-slate-500">{subtitle}</p>
              </div>
              <button
                type="button"
                onClick={signOut}
                className="inline-flex items-center gap-1.5 rounded-xl border border-slate-200 bg-white px-2.5 py-2 text-xs font-bold text-slate-700"
                aria-label="Sign out"
              >
                <LogOut className="h-3.5 w-3.5" />
                Sign out
              </button>
              <button
                type="button"
                onClick={() => setMenuOpen((open) => !open)}
                className="inline-flex h-9 w-9 items-center justify-center rounded-xl border border-slate-200 bg-white text-slate-700"
                aria-expanded={menuOpen}
                aria-label={menuOpen ? "Close menu" : "Open menu"}
              >
                {menuOpen ? <X className="h-4 w-4" /> : <Menu className="h-4 w-4" />}
              </button>
            </div>

            {menuOpen ? (
              <div className="mt-3 space-y-3 rounded-2xl border border-slate-200 bg-slate-50 p-3">
                <p className="truncate text-xs font-semibold text-slate-500">
                  {teacherName}
                  {schoolName ? ` · ${schoolName}` : ""}
                </p>
                {isAdmin ? <PortalModeSwitch mode={mode} onChange={switchMode} /> : null}
                <nav className="grid gap-1">
                  {nav.map((item) => {
                    const active = navItemActive(pathname, item.href, item.exact);
                    const Icon = item.icon;
                    return (
                      <Link
                        key={item.href}
                        href={item.href}
                        className={cn(
                          "flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-bold",
                          active
                            ? "bg-emerald-500 text-white"
                            : "bg-white text-slate-700 ring-1 ring-slate-200",
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
                  className="flex w-full items-center justify-center gap-2 rounded-xl bg-red-50 px-3 py-2.5 text-sm font-bold text-red-700 ring-1 ring-red-100"
                >
                  <LogOut className="h-4 w-4" />
                  Sign out
                </button>
              </div>
            ) : null}
          </header>

          <main className="flex-1 p-4 pb-24 md:p-6 lg:pb-6">{children}</main>

          {/* Phone bottom tabs */}
          <nav
            className="fixed inset-x-0 bottom-0 z-40 border-t border-slate-200 bg-white/95 px-2 pb-[max(0.5rem,env(safe-area-inset-bottom))] pt-1.5 backdrop-blur lg:hidden"
            aria-label="Main"
          >
            <div className="mx-auto grid max-w-lg grid-cols-4 gap-1">
              {bottomNav.map((item) => {
                const active = navItemActive(pathname, item.href, item.exact);
                const Icon = item.icon;
                return (
                  <Link
                    key={item.href}
                    href={item.href}
                    className={cn(
                      "flex flex-col items-center gap-0.5 rounded-xl px-1 py-2 text-[10px] font-bold",
                      active ? "bg-emerald-50 text-emerald-800" : "text-slate-500",
                    )}
                  >
                    <Icon className="h-5 w-5" />
                    <span className="truncate">{item.label}</span>
                  </Link>
                );
              })}
            </div>
          </nav>
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
