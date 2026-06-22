import Link from "next/link";

import { notFound } from "next/navigation";

import { formatDistanceToNow } from "date-fns";

import { Card, StatCard } from "@/components/ui/card";

import { fetchTeacherAdminDetail } from "@/lib/api/admin";

import { requireAdminSession } from "@/lib/api/session";



export default async function AdminTeacherDetailPage({

  params,

}: {

  params: Promise<{ teacherId: string }>;

}) {

  const { teacherId } = await params;

  const { user, profile, supabase } = await requireAdminSession();

  const schoolName = profile.school_name?.trim() ?? null;



  const detail = await fetchTeacherAdminDetail(supabase, teacherId, schoolName);

  if (!detail) notFound();



  const { teacher, sections } = detail;

  const isYou = teacher.id === user.id;

  const lastUpdatedLabel = detail.lastCloudUpdate

    ? formatDistanceToNow(new Date(detail.lastCloudUpdate), { addSuffix: true })

    : "No activity yet";



  return (

    <>

      <div className="mb-4">

        <Link href="/dashboard/admin" className="text-sm font-bold text-emerald-700 hover:underline">

          ← School overview

        </Link>

        <h1 className="mt-2 text-2xl font-extrabold text-slate-800">{teacher.full_name}</h1>

        <p className="mt-1 text-sm text-slate-500">

          {isYou ? "Your account · " : ""}

          {teacher.school_name ?? "School not set"}

          {lastUpdatedLabel !== "No activity yet" ? ` · Updated ${lastUpdatedLabel}` : ""}

        </p>

      </div>



      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">

        <StatCard label="Classes" value={detail.sectionCount} />

        <StatCard label="Students" value={detail.studentCount} />

        <StatCard label="Answer keys" value={detail.subjectCount} />

        <StatCard label="Graded sheets" value={detail.scanCount} />

      </div>



      <Card title="Classes" className="mt-6" subtitle="View rosters — read only">

        {sections.length === 0 ? (

          <p className="text-sm text-slate-500">This teacher has not set up any classes yet.</p>

        ) : (

          <div className="overflow-x-auto">

            <table className="min-w-full text-sm">

              <thead>

                <tr className="border-b text-xs font-bold uppercase text-slate-500">

                  <th className="px-2 py-2 text-left">Section</th>

                  <th className="px-2 py-2 text-left">Students</th>

                  <th className="px-2 py-2 text-left" />

                </tr>

              </thead>

              <tbody>

                {sections.map((section) => (

                  <tr key={section.name} className="border-b border-slate-100">

                    <td className="px-2 py-2 font-semibold text-slate-800">{section.name}</td>

                    <td className="px-2 py-2">{section.studentCount}</td>

                    <td className="px-2 py-2">

                      <Link

                        href={`/dashboard/admin/teachers/${teacherId}/sections/${encodeURIComponent(section.name)}`}

                        className="text-sm font-bold text-emerald-700 hover:underline"

                      >

                        View roster

                      </Link>

                    </td>

                  </tr>

                ))}

              </tbody>

            </table>

          </div>

        )}

      </Card>



      {detail.pendingReviewCount > 0 ? (

        <p className="mt-4 text-sm text-amber-800">

          <strong>{detail.pendingReviewCount}</strong> sheet

          {detail.pendingReviewCount === 1 ? "" : "s"} waiting for review on this teacher&apos;s phone.

        </p>

      ) : null}

    </>

  );

}

