/**
 * The flight-progress strips: one strip per leg in a rack, the way air traffic
 * control tracks flights. The strip being flown sticks out, and a white tick
 * marks where the plan says I should be. Satori lays it out, styled with its
 * built-in Tailwind, and writes an SVG with the text as outlines, so it looks
 * the same in the README, on the docs site and on any device. A <desc> carries
 * the same detail as text.
 */
import { readFile } from "node:fs/promises";
import type { ReactNode } from "react";
import satori from "satori";
import {
  type Flight,
  type Leg,
  type Status,
  STAMPS,
  TAKEOFF,
  activeLeg,
  closedCount,
  legName,
  legNumber,
  planned,
  plural,
  shortDate,
  status,
  totals,
} from "./plan";

declare module "react" {
  interface HTMLAttributes<T> {
    tw?: string; // Satori's Tailwind classes
  }
}

const tailwindConfig = {
  theme: {
    extend: {
      colors: {
        background: "#0d1117",
        strip: "#161b22",
        ink: "#eaecef",
        slate: "#8b97a6",
        dim: "#30363d", // decoration only: the rail and strip edges
        faint: "#7d8896", // 4.8:1 on a strip, so it passes for small text
        orange: "#f2662b",
        red: "#f07167",
        amber: "#ffb547",
      },
    },
  },
};

const TONE: Record<Status, string> = {
  landed: "orange",
  "in flight": "amber",
  late: "red",
  "started early": "slate",
  "not started": "slate",
};

const PIP_GAP = 3;

/**
 * The two cards. The wide one is for a desktop. A phone would shrink it to
 * about 40%, so the narrow one drops the ETAs, puts each strip on two rows and
 * keeps every number at full size.
 */
const CARDS = {
  wide: {
    narrow: false,
    width: 900,
    pad: "px-7",
    rail: "w-2.5 mr-2.5",
    strip: "h-[34px]",
    stickOut: "ml-[22px]", // how far the active strip sticks out of the rack
    tuckIn: "mr-[22px]",
    label: "w-[84px]",
    name: "text-[15px]",
    status: "w-[112px]",
    count: "w-16",
    stamp: "text-[11px]",
    pips: 260, // past 20 issues the pips get narrower instead of the rack wider
  },
  narrow: {
    narrow: true,
    width: 420,
    pad: "px-4",
    rail: "w-1.5 mr-2",
    strip: "h-14",
    stickOut: "ml-3.5",
    tuckIn: "mr-3.5",
    label: "w-[62px]",
    name: "text-sm", // fits the longest leg name today, 25 characters
    status: "w-[104px]",
    count: "w-11",
    stamp: "text-xs",
    pips: 166, // what's left of the second row beside the status
  },
};
type Card = (typeof CARDS)["wide"];

export function Rack({ flight, mark, card = CARDS.wide }: { flight: Flight; mark: string; card?: Card }) {
  const most = Math.max(1, ...flight.legs.map((leg) => leg.issues.length));
  const pitch = Math.min(13, Math.floor(card.pips / most)); // a pip and its gap
  return (
    <div
      tw={`flex flex-col w-full ${card.pad} py-[22px] bg-background border-2 border-dim rounded-[14px] text-ink`}
      style={{ fontFamily: "JetBrains Mono" }}
    >
      <Header flight={flight} mark={mark} card={card} />
      <div tw="flex mt-[18px]">
        <div tw={`${card.rail} shrink-0 bg-dim rounded-sm`} />
        <div tw="flex flex-col flex-grow min-w-0">
          {flight.legs.map((leg, i) => (
            <Strip key={leg.title} {...{ flight, leg, pitch, most, mark, card }} index={i} />
          ))}
          <Standby flight={flight} card={card} />
        </div>
      </div>
      <div tw="flex flex-wrap justify-center mt-3.5">
        {Object.entries(STAMPS).map(([n, name]) => (
          <Stamp key={n} name={name} won={flight.closed.has(Number(n))} card={card} />
        ))}
      </div>
    </div>
  );
}

function Header({ flight, mark, card }: { flight: Flight; mark: string; card: Card }) {
  const { done, total, percent, headwind } = totals(flight);
  const arrival = flight.legs.at(-1)?.dueOn;
  const route = `Takeoff ${shortDate(TAKEOFF)}` + (arrival ? ` · arrival ${shortDate(arrival)}` : "");
  const notes = [headwind ? `+${headwind} since takeoff` : "no headwind yet"];
  if (flight.legs.some((_, i) => planned(flight, i) !== null)) notes.push("white tick = today's plan");
  return (
    <div tw="flex flex-wrap items-center">
      <img src={mark} width={40} height={47} />
      <div tw="flex flex-col flex-grow ml-3.5">
        <div tw="text-[13px] tracking-[1.5px] text-slate">FLIGHT PROGRESS STRIPS</div>
        <div tw="text-[15px] font-bold mt-0.5">{route}</div>
      </div>
      {/* the narrow card has no room beside the route, so the score wraps under it */}
      <div tw={`flex flex-col ${card.narrow ? "w-full mt-3.5" : "items-end"}`}>
        <div tw="text-[17px] font-bold">{`${done} of ${plural(total, "issue")} · ${percent}%`}</div>
        <div tw="text-xs text-slate mt-0.5">{notes.join(" · ")}</div>
      </div>
    </div>
  );
}

interface StripProps {
  flight: Flight;
  leg: Leg;
  index: number;
  pitch: number;
  most: number;
  mark: string;
  card: Card;
}

function Strip({ flight, leg, index, pitch, most, mark, card }: StripProps) {
  const st = status(flight, index);
  const tone = TONE[st];
  const active = index === activeLeg(flight);
  const late = st === "late";
  const closed = closedCount(leg.issues);
  // a late leg's label is outlined, not filled, so it differs from a landed one by more than colour
  const label = late ? `border-2 border-${tone} text-${tone}` : `bg-${tone} text-background`;
  const offset = active ? `${card.stickOut} border-${tone}` : `${card.tuckIn} border-dim`;
  const name = (
    <Name tw={`${card.name} font-bold ${st === "landed" ? "text-slate" : "text-ink"}`}>{legName(leg.title)}</Name>
  );
  const state = <div tw={`flex ${card.status} shrink-0 text-xs font-bold text-${tone}`}>{late ? "LATE" : st}</div>;
  const pips = (
    <Pips closed={closed} total={leg.issues.length} plan={planned(flight, index)} pitch={pitch} most={most} />
  );
  const count = <Count card={card}>{`${closed}/${leg.issues.length}`}</Count>;
  return (
    <div tw={`flex items-center ${card.strip} mb-1.5 bg-strip rounded-sm border-[1.5px] ${offset}`}>
      <div tw={`flex ${card.label} h-full shrink-0 items-center justify-center text-sm font-bold ${label}`}>
        {active && <img src={mark} width={17} height={20} tw="mr-[5px]" />}
        {`TBX${legNumber(leg.title, index)}`}
      </div>
      {card.narrow ? (
        <Rows
          top={
            <>
              {name}
              {count}
            </>
          }
          bottom={
            <>
              {state}
              {pips}
            </>
          }
        />
      ) : (
        <>
          {name}
          <div tw="flex w-[100px] shrink-0 text-xs text-slate">{`ETA ${shortDate(leg.dueOn)}`}</div>
          {state}
          {pips}
          {count}
        </>
      )}
    </div>
  );
}

interface PipsProps {
  closed: number;
  total: number;
  plan: number | null;
  pitch: number;
  most: number;
}

/** One pip per issue, filled once it closes, and the white tick where the plan says I should be. */
function Pips({ closed, total, plan, pitch, most }: PipsProps) {
  return (
    <div tw="flex relative shrink-0" style={{ width: pitch * most }}>
      {Array.from({ length: total }, (_, n) => (
        // open work is an outline, so it passes 3:1 and reads by shape as well as colour
        <div
          key={n}
          tw={`h-3 mr-[${PIP_GAP}px] shrink-0 rounded-sm ${n < closed ? "bg-orange" : "border border-faint"}`}
          style={{ width: pitch - PIP_GAP }}
        />
      ))}
      {plan !== null && (
        // centred in the gap after the last pip the plan expects to be done
        <div tw="absolute -top-1 w-0.5 h-5 bg-ink" style={{ left: plan * total * pitch - (PIP_GAP + 2) / 2 }} />
      )}
    </div>
  );
}

function Standby({ flight, card }: { flight: Flight; card: Card }) {
  const count = <Count card={card}>{`${closedCount(flight.bonus)}/${flight.bonus.length}`}</Count>;
  return (
    <div
      tw={`flex items-center ${card.strip} ${card.tuckIn} rounded-sm border-[1.5px] border-dashed border-faint text-faint`}
    >
      <div tw={`flex ${card.label} shrink-0 justify-center text-sm font-bold`}>TBX-S</div>
      {card.narrow ? (
        <Rows
          top={
            <>
              <Name tw="text-sm">Stretch · on standby</Name>
              {count}
            </>
          }
          bottom={<div tw="text-xs">flown if the legs land early</div>}
        />
      ) : (
        <>
          <Name tw="text-sm">Stretch · on standby, flown if the legs land early</Name>
          {count}
        </>
      )}
    </div>
  );
}

/** A narrow strip's two rows, beside the label: the name and count, then the detail under them. */
function Rows({ top, bottom }: { top: ReactNode; bottom: ReactNode }) {
  return (
    <div tw="flex flex-col flex-grow min-w-0">
      <div tw="flex items-center">{top}</div>
      <div tw="flex items-center mt-2 pl-3">{bottom}</div>
    </div>
  );
}

/** The strip's name column: takes the room that's left and cuts a long name short with an ellipsis. */
function Name({ tw, children }: { tw: string; children: string }) {
  return (
    <div tw={`flex flex-grow min-w-0 px-3 ${tw}`}>
      <span tw="overflow-hidden" style={{ whiteSpace: "nowrap", textOverflow: "ellipsis" }}>
        {children}
      </span>
    </div>
  );
}

function Count({ card, children }: { card: Card; children: string }) {
  return <div tw={`flex ${card.count} shrink-0 justify-end pr-3 text-[13px]`}>{children}</div>;
}

function Stamp({ name, won, card }: { name: string; won: boolean; card: Card }) {
  return (
    <div
      tw={`m-1 px-[9px] py-[3px] rounded-xl border-[1.5px] ${card.stamp} font-bold ${won ? "bg-orange border-orange text-background" : "border-faint text-faint"}`}
    >
      {name}
    </div>
  );
}

/** The rack in words: a title and one sentence per leg, for screen readers and the <desc>. */
export function summary(flight: Flight) {
  const { done, total, percent } = totals(flight);
  const title = `Flight progress: ${done} of ${plural(total, "issue")} closed (${percent}%)`;
  const legs = flight.legs.map((leg, i) => {
    const plan = planned(flight, i);
    return (
      `TBX${legNumber(leg.title, i)} ${legName(leg.title)}: ${status(flight, i)}, ` +
      `${closedCount(leg.issues)} of ${leg.issues.length} closed, due ${shortDate(leg.dueOn)}` +
      (plan === null ? "." : `, the plan says ${Math.round(plan * 100)}% by today.`)
    );
  });
  const stamps = Object.entries(STAMPS)
    .filter(([n]) => flight.closed.has(Number(n)))
    .map(([, name]) => name);
  const desc = [
    ...legs,
    `Stretch: ${closedCount(flight.bonus)} of ${flight.bonus.length} closed.`,
    `Stamps won: ${stamps.length ? stamps.join(", ") : "none yet"}.`,
  ].join(" ");
  return { title, desc };
}

const xml = (text: string) =>
  text.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&apos;" })[c]!);

const asset = (path: string) => readFile(new URL(import.meta.resolve(path)));

/**
 * The rack as SVG, as tall as its content, with a title and description for
 * screen readers. `narrow` draws the 420px card for phones.
 */
export async function render(flight: Flight, { narrow = false } = {}): Promise<string> {
  const card = narrow ? CARDS.narrow : CARDS.wide;
  const [regular, bold, markSvg] = await Promise.all([
    asset("@fontsource/jetbrains-mono/files/jetbrains-mono-latin-500-normal.woff"),
    asset("@fontsource/jetbrains-mono/files/jetbrains-mono-latin-700-normal.woff"),
    readFile(new URL("../../../docs/brand/mark-dark.svg", import.meta.url)),
  ]);
  const mark = `data:image/svg+xml;base64,${markSvg.toString("base64")}`;
  const svg = await satori(<Rack flight={flight} mark={mark} card={card} />, {
    width: card.width,
    tailwindConfig,
    fonts: [
      { name: "JetBrains Mono", data: regular, weight: 500, style: "normal" },
      { name: "JetBrains Mono", data: bold, weight: 700, style: "normal" },
    ],
  });
  const { title, desc } = summary(flight);
  return (
    svg.replace(/<svg\b[^>]*>/, (open) => {
      const withA11y = open.replace("<svg ", `<svg role="img" aria-label="${xml(title)}" `);
      return `${withA11y}<title>${xml(title)}</title><desc>${xml(desc)}</desc>`;
    }) + "\n"
  );
}
