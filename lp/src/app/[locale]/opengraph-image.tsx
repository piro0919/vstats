import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { ImageResponse } from "next/og";
import { routing } from "@/i18n/routing";

export const alt = "VStats";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

/* ビルド時に焼く。動的なままだと public/ が関数側に含まれず、
   本番で icon.png を読めずに 500 になる */
export function generateStaticParams(): { locale: string }[] {
  return routing.locales.map((locale) => ({ locale }));
}

/* 出るのは kk-web の一覧で176px、X のカードで500px 前後。
   その大きさで残るのはアイコンと名前と1行だけ。サイトの暗い表示と同じ黒地に明るい字（白地だとサイトと食い違う、と本人に言われた） */
const BG = "#0a0a0a";
const INK = "#ededed";
const MUTED = "#a1a1a1";

export default async function OgImage({
  params,
}: {
  params: Promise<{ locale: string }>;
}): Promise<ImageResponse> {
  const { locale } = await params;
  const isJa = locale === "ja";
  /* 使う文字だけに絞った書体を同梱している。文言を変えたら assets/README.md の手順で作り直す */
  const [icon, geist, noto] = await Promise.all([
    readFile(join(process.cwd(), "public/icon.png")),
    readFile(join(process.cwd(), "assets/Geist-SemiBold-subset.woff")),
    readFile(join(process.cwd(), "assets/NotoSansJP-SemiBold-subset.woff")),
  ]);
  const iconSrc = `data:image/png;base64,${icon.toString("base64")}`;

  return new ImageResponse(
    <div
      style={{
        alignItems: "center",
        background: BG,
        /* アイコンの後ろに、アイコンの棒と同じ緑の光の輪を置く */
        backgroundImage:
          "radial-gradient(28% 50% at 30% 50%, rgba(61,220,132,0.28) 0%, rgba(10,10,10,0) 100%)",
        display: "flex",
        gap: 56,
        height: "100%",
        justifyContent: "center",
        width: "100%",
      }}
    >
      {/* biome-ignore lint/performance/noImgElement: next/image is not available in ImageResponse */}
      <img alt="" height={240} src={iconSrc} width={240} />
      <div style={{ display: "flex", flexDirection: "column" }}>
        <div style={{ color: INK, fontSize: 120, letterSpacing: -5 }}>VStats</div>
        <div style={{ color: MUTED, display: "flex", fontSize: 36, marginTop: 8 }}>
          {isJa ? "Vercel の全サイトを、ひとつの窓で。" : "Every Vercel site, in one window."}
        </div>
      </div>
    </div>,
    {
      ...size,
      fonts: [
        { data: geist, name: "Geist", style: "normal", weight: 600 },
        { data: noto, name: "Noto Sans JP", style: "normal", weight: 600 },
      ],
    },
  );
}
