import { PageSkeleton } from "@/components/page-skeleton";

export default function PrepareLoading() {
  return (
    <div className="p-4 md:p-6">
      <PageSkeleton rows={3} />
    </div>
  );
}
