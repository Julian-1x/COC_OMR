import Image from "next/image";
import { workspaceName } from "@/lib/theme";

export function CocLogo({ size = 48 }: { size?: number }) {
  return (
    <div
      className="relative shrink-0 overflow-hidden rounded-full bg-white shadow-md ring-2 ring-emerald-100"
      style={{ width: size, height: size }}
    >
      <Image
        src="/coc_seal.png"
        alt={`${workspaceName} seal`}
        fill
        className="object-cover"
        sizes={`${size}px`}
        priority
      />
    </div>
  );
}

export function BrandHeader({ subtitle }: { subtitle?: string }) {
  return (
    <div className="flex items-center gap-3">
      <CocLogo size={44} />
      <div>
        <p className="text-sm font-extrabold tracking-tight text-slate-800">COC OMR</p>
        <p className="text-xs font-semibold text-emerald-700">{workspaceName}</p>
        {subtitle ? <p className="text-xs text-slate-500">{subtitle}</p> : null}
      </div>
    </div>
  );
}
