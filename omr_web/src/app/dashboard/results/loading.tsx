import { PageSkeleton } from "@/components/page-skeleton";

export default function ResultsLoading() {
  return (
    <div className="p-4 md:p-6">
      <PageSkeleton rows={6} />
    </div>
  );
}
