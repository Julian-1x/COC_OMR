"use client";

import Link from "next/link";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { createBrowserApiClient } from "@/lib/api/laravel-client";
import {
  fetchAccessRequests,
  fetchSchoolTeacherSummaries,
  isSuperAdmin,
  type AccessRequestTeacher,
  type SchoolTeacherSummary,
} from "@/lib/api/admin";
import { slowApiLoadingMessage, useSlowApiLoad } from "@/lib/api/use-slow-api-load";
import type { ApiUser } from "@/lib/api/laravel-client";
import type { DbTeacherProfile } from "@/lib/types/database";
import { AccessControlPanel } from "./access-control-panel";

type AccessControlContentProps = {
  schoolName: string;
  profile: DbTeacherProfile;
  user: ApiUser;
};

export function AccessControlContent({ schoolName, profile, user }: AccessControlContentProps) {
  const viewerIsSuperAdmin = isSuperAdmin(profile, user);
  const [pending, setPending] = useState<AccessRequestTeacher[]>([]);
  const [teachers, setTeachers] = useState<SchoolTeacherSummary[]>([]);

  const { loading, error, attempt, maxAttempts, reload } = useSlowApiLoad(async () => {
    const api = createBrowserApiClient();
    const [pendingRows, teacherRows] = await Promise.all([
      fetchAccessRequests(api),
      fetchSchoolTeacherSummaries(api, schoolName, user.id),
    ]);
    setPending(pendingRows);
    setTeachers(teacherRows);
  }, [schoolName, user.id]);

  const approved = teachers.filter(
    (teacher) =>
      teacher.accessStatus === "approved" ||
      (!teacher.accessStatus && teacher.status !== "pending" && teacher.status !== "revoked"),
  );
  const revoked = teachers.filter((teacher) => teacher.accessStatus === "revoked");

  return (
    <>
      {loading ? (
        <div className="mb-4 rounded-xl border border-slate-200 bg-slate-50 px-4 py-3 text-sm text-slate-700">
          <p className="font-semibold">Loading access requests…</p>
          <p className="mt-1 text-xs text-slate-500">{slowApiLoadingMessage(attempt, maxAttempts)}</p>
        </div>
      ) : null}

      {error ? (
        <div className="mb-4 rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-800">
          <p className="font-semibold">{error}</p>
          <Button type="button" variant="secondary" className="mt-3" onClick={reload}>
            Try again
          </Button>
        </div>
      ) : null}

      {!loading && !error ? (
        <AccessControlPanel
          pending={pending}
          approved={approved}
          revoked={revoked}
          viewerIsSuperAdmin={viewerIsSuperAdmin}
          viewerDepartment={profile.department}
        />
      ) : null}
    </>
  );
}
