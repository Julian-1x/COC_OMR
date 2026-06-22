import { redirect } from "next/navigation";

/** Sync help lives on Settings — one place for teachers. */
export default function SyncCheckPage() {
  redirect("/dashboard/settings");
}
