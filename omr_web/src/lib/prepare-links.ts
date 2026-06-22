export function printSheetsHref(subjectLocalId: string, sectionName: string) {
  const params = new URLSearchParams({
    subject: subjectLocalId,
    section: sectionName,
  });
  return `/dashboard/prepare/print-sheets?${params.toString()}`;
}

export function sectionPrintSheetsHref(sectionName: string) {
  return `/dashboard/prepare/print-sheets?${new URLSearchParams({ section: sectionName }).toString()}`;
}

export function omrIdsHref(sectionName: string) {
  return `/dashboard/prepare/omr-ids?${new URLSearchParams({ section: sectionName }).toString()}`;
}

export function classRosterHref(sectionName: string) {
  return `/dashboard/classes/${encodeURIComponent(sectionName)}`;
}
