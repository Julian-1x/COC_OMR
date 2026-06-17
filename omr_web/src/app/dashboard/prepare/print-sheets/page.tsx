import { Suspense } from "react";
import PrintSheetsPage from "./print-sheets-content";

export default function Page() {
  return (
    <Suspense fallback={<p className="p-6 text-sm text-slate-500">Loading…</p>}>
      <PrintSheetsPage />
    </Suspense>
  );
}
