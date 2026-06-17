import { Suspense } from "react";
import OmrIdsPage from "./omr-ids-content";

export default function Page() {
  return (
    <Suspense fallback={<p className="p-6 text-sm text-slate-500">Loading…</p>}>
      <OmrIdsPage />
    </Suspense>
  );
}
