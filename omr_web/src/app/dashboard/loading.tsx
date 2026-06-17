export default function DashboardLoading() {
  return (
    <div className="min-h-screen bg-slate-50 p-4 md:p-6">
      <div className="mx-auto max-w-7xl animate-pulse space-y-6">
        <div className="h-8 w-48 rounded-lg bg-slate-200" />
        <div className="h-4 w-72 rounded bg-slate-200" />
        <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
          {Array.from({ length: 4 }).map((_, i) => (
            <div key={i} className="h-24 rounded-2xl bg-white shadow-sm ring-1 ring-slate-200" />
          ))}
        </div>
        <div className="grid gap-4 lg:grid-cols-2">
          <div className="h-48 rounded-2xl bg-white shadow-sm ring-1 ring-slate-200" />
          <div className="h-48 rounded-2xl bg-white shadow-sm ring-1 ring-slate-200" />
        </div>
      </div>
    </div>
  );
}
