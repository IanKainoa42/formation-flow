// FormationFlow — onboarding intro screens (dark "courtside" surface)
//
// Structure borrowed from the CoachFilm intro: a floating marketing card layered
// over a live app surface. Here the surface is FormationFlow's dark floor grid —
// athletes as role-coloured dots, transition paths with waypoints, a formation
// thumbnail strip, and a count-based transport. Copy is deadpan cheer-coach voice,
// switchable between two writers via the FFCopyCtx.

// ────────────────────────────────────────────────────────────────
// Theme tokens
// ────────────────────────────────────────────────────────────────

const FF_DEFAULTS = { accent: '#0A84FF' };

const FFThemeCtx = React.createContext(null);
function useFF() {
  const t = React.useContext(FFThemeCtx) || FF_DEFAULTS;
  return {
    bg:        '#0A0C0F',
    floor:     '#0E1217',
    floorEdge: 'rgba(255,255,255,0.08)',
    gridMinor: 'rgba(255,255,255,0.040)',
    gridMajor: 'rgba(255,255,255,0.105)',
    bar:       'rgba(14,17,22,0.72)',
    barBd:     'rgba(255,255,255,0.09)',
    tile:      'rgba(255,255,255,0.05)',
    accent:    t.accent,
    txt:       '#F5F5F7',
    txtDim:    'rgba(235,235,245,0.60)',
    txtFaint:  'rgba(235,235,245,0.30)',
    // SwiftUI system role colors (dark/vivid)
    role: {
      base:    '#0A84FF',
      flyer:   '#FFD60A',
      spotter: '#30D158',
      backspot:'#BF5AF2',
      tumbler: '#FF9F0A',
      stunt:   '#FF375F',
    },
    mono: 'ui-monospace, "SF Mono", "JetBrains Mono", Menlo, monospace',
    sans: '-apple-system, "SF Pro Display", BlinkMacSystemFont, system-ui, sans-serif',
  };
}

// Court is 72ft × 56ft (9 × 7 panels of 8ft) — CourtConstants.swift
const COURT_W = 72, COURT_H = 56, PANEL = 8;

// ────────────────────────────────────────────────────────────────
// Copy — two deadpan voices
// ────────────────────────────────────────────────────────────────

const FFCopyCtx = React.createContext('A');

const COPY = {
  A: {
    s1: { eyebrow: 'Welcome · 01 / 06',
          title: 'Your full team shows up *the day before* competition.',
          body: 'Cool. Plan the entire routine here instead — place every athlete, map every transition, press play. The mat is for cleaning it up, not figuring it out.',
          cta: 'Get started' },
    s2: { eyebrow: 'Roster · 02 / 06',
          title: 'Move athletes around without anyone *bumping into each other.*',
          body: 'Drop your roster onto a true-to-scale floor and drag them where they go. Color-coded by role so you can read the formation at a glance. This generation collides enough in real life.' },
    s3: { eyebrow: 'Transitions · 03 / 06',
          title: 'Press play. Watch the chaos *resolve itself.*',
          body: 'Animate the move between any two formations in real time. Flow mode pulses the paths; Steps mode counts out the footwork. Either way you see it before they walk it.' },
    s4: { eyebrow: 'Paths · 04 / 06',
          title: 'Two athletes, one spot, *zero collisions.*',
          body: 'Bend any path with waypoints — smooth or sharp — and stagger entrances with a move delay measured in 8-counts. The app flags crossings before they become a pile-up.' },
    s5: { eyebrow: 'Routine · 05 / 06',
          title: 'String it all together. Then move *twelve of them at once.*',
          body: 'Chain formations into a full routine and scrub the whole thing end to end. Multi-select a stunt group to slide everyone together — re-placing sixteen athletes one at a time is a punishment, not a workflow.' },
    s6: { eyebrow: 'Ready · 06 / 06',
          title: 'No team, no signal, *no excuses.*',
          body: 'Everything lives on your device — works on the mat with zero bars, stays private, no account. Go Pro for unlimited formations, every role, and full-routine playback. Four hours a week. Don\u2019t spend them on a transition you could\u2019ve solved at home.',
          cta: 'now let your imagination be.' },
  },
  B: {
    s1: { eyebrow: 'Welcome · 01 / 06',
          title: 'Practice is Thursday. *Half the team* will be there.',
          body: 'Plan the routine now, while it\u2019s quiet. Place every athlete, map every transition, and walk into practice already knowing the answer.',
          cta: 'Get started' },
    s2: { eyebrow: 'Roster · 02 / 06',
          title: 'Assign roles. Avoid *reunions mid-mat.*',
          body: 'Build your roster once and drop athletes onto a scaled floor. Each role gets its own color, so you\u2019re never squinting at sixteen identical dots wondering which one is the flyer.' },
    s3: { eyebrow: 'Transitions · 03 / 06',
          title: 'See the transition *before they trip through it.*',
          body: 'Hit play and the whole move animates in real time. Flow mode for the paths, Steps mode for the counts — pick whichever way you actually coach it.' },
    s4: { eyebrow: 'Paths · 04 / 06',
          title: 'Curved paths for athletes who *can\u2019t walk straight.*',
          body: 'Add waypoints to route around traffic — smooth or sharp — and offset each entrance by a few counts. Crossings get flagged before someone\u2019s eating floor.' },
    s5: { eyebrow: 'Routine · 05 / 06',
          title: 'One routine. Every formation. *Scrubbable.*',
          body: 'Link formations into a sequence and preview the whole thing front to back. Grab a stunt group and move all four at once — your thumbs will thank you.' },
    s6: { eyebrow: 'Ready · 06 / 06',
          title: 'Courtside-proof. *Wi-Fi optional.*',
          body: 'It\u2019s all on-device: no account, no signal, fully private. Pro unlocks unlimited formations, all roles, and full-routine playback. Mat time is precious — stop spending it on math you could do on the couch.',
          cta: 'now let your imagination be.' },
  },
};

// Per-screen voice mix (curated picks). The global FFCopyCtx can force 'A'
// or 'B' wholesale; 'Mix' uses these per-screen assignments.
const SCREEN_VOICE = { s1: 'A', s2: 'B', s3: 'A', s4: 'A', s5: 'B', s6: 'A' };

function useCopy(key) {
  const mode = React.useContext(FFCopyCtx);
  const voice = (mode === 'A' || mode === 'B') ? mode : SCREEN_VOICE[key];
  return COPY[voice][key];
}

// italicise text wrapped in *asterisks*
function renderEm(str, italicColor) {
  const parts = String(str).split(/(\*[^*]+\*)/g);
  return parts.map((p, i) => {
    if (p.startsWith('*') && p.endsWith('*')) {
      return <span key={i} style={{ fontStyle: 'italic', color: italicColor || 'inherit' }}>{p.slice(1, -1)}</span>;
    }
    return <React.Fragment key={i}>{p}</React.Fragment>;
  });
}

// ────────────────────────────────────────────────────────────────
// Formations (athlete positions in floor feet)
// ────────────────────────────────────────────────────────────────

const ROSTER = [
  { id: 'a1',  label: 'A1',  role: 'flyer'    },
  { id: 'a2',  label: 'A2',  role: 'base'     },
  { id: 'a3',  label: 'A3',  role: 'base'     },
  { id: 'a4',  label: 'A4',  role: 'base'     },
  { id: 'a5',  label: 'A5',  role: 'base'     },
  { id: 'a6',  label: 'A6',  role: 'spotter'  },
  { id: 'a7',  label: 'A7',  role: 'spotter'  },
  { id: 'a8',  label: 'A8',  role: 'tumbler'  },
  { id: 'a9',  label: 'A9',  role: 'tumbler'  },
  { id: 'a10', label: 'A10', role: 'backspot' },
];

const FORM_V = {
  a1: [36, 11], a2: [28, 20], a3: [44, 20], a4: [21, 27], a5: [51, 27],
  a6: [15, 33], a7: [57, 33], a8: [11, 40], a9: [61, 40], a10: [36, 39],
};
const FORM_LINES = {
  a1: [36, 16], a2: [16, 24], a3: [28, 24], a4: [44, 24], a5: [56, 24],
  a6: [12, 38], a7: [24, 38], a8: [36, 38], a9: [48, 38], a10: [60, 38],
};

function athletesAt(form) {
  return ROSTER.map(r => ({ ...r, x: form[r.id][0], y: form[r.id][1] }));
}

// ────────────────────────────────────────────────────────────────
// iPad-landscape bezel
// ────────────────────────────────────────────────────────────────

function IPadFrame({ children }) {
  return (
    <div style={{
      width: 1066, height: 800, borderRadius: 44, background: '#050608',
      boxShadow: '0 30px 80px rgba(0,0,0,0.45), 0 0 0 1px rgba(0,0,0,0.7)',
      padding: 15, position: 'relative', WebkitFontSmoothing: 'antialiased',
    }}>
      <div style={{
        position: 'absolute', top: 7, left: '50%', transform: 'translateX(-50%)',
        width: 6, height: 6, borderRadius: 3, background: '#1c1c20',
      }}/>
      <div style={{
        width: '100%', height: '100%', background: '#0A0C0F',
        borderRadius: 30, overflow: 'hidden', position: 'relative',
      }}>{children}</div>
    </div>
  );
}

// ────────────────────────────────────────────────────────────────
// Floor grid + athletes + paths  (one SVG, court-feet coordinate space)
// ────────────────────────────────────────────────────────────────

function FloorSurface({ inset = { t: 60, b: 104, x: 132 }, children }) {
  // children render inside the court <svg> coordinate space (feet → px handled here)
  return (
    <FloorSurfaceInner inset={inset}>{children}</FloorSurfaceInner>
  );
}

function FloorSurfaceInner({ inset, children }) {
  const FF = useFF();
  // available pixel rect inside the 1066×800 surface
  const availW = 1066 - inset.x * 2;
  const availH = 800 - inset.t - inset.b;
  // fit 72:56 by height, centre horizontally
  let courtH = availH, courtW = courtH * (COURT_W / COURT_H);
  if (courtW > availW) { courtW = availW; courtH = courtW * (COURT_H / COURT_W); }
  const left = (1066 - courtW) / 2;
  const top = inset.t + (availH - courtH) / 2;
  const cell = courtW / COURT_W;       // px per foot
  const ctx = { cell, courtW, courtH };

  // grid lines
  const minor = [];
  for (let c = 0; c <= COURT_W; c++) minor.push(<line key={'v'+c} x1={c*cell} y1={0} x2={c*cell} y2={courtH} stroke={c % PANEL === 0 ? FF.gridMajor : FF.gridMinor} strokeWidth={c % PANEL === 0 ? 1 : 0.5}/>);
  for (let r = 0; r <= COURT_H; r++) minor.push(<line key={'h'+r} x1={0} y1={r*cell} x2={courtW} y2={r*cell} stroke={r % PANEL === 0 ? FF.gridMajor : FF.gridMinor} strokeWidth={r % PANEL === 0 ? 1 : 0.5}/>);

  return (
    <div style={{ position: 'absolute', inset: 0, background: FF.bg }}>
      {/* subtle radial lift behind the floor */}
      <div style={{ position: 'absolute', inset: 0, background: 'radial-gradient(120% 90% at 50% 38%, rgba(10,132,255,0.06), transparent 60%)' }}/>
      <div style={{
        position: 'absolute', left, top, width: courtW, height: courtH,
        background: FF.floor, borderRadius: 10,
        boxShadow: '0 1px 0 rgba(255,255,255,0.04) inset, 0 24px 60px rgba(0,0,0,0.5)',
        border: '1px solid ' + FF.floorEdge,
      }}>
        <svg width={courtW} height={courtH} style={{ display: 'block', borderRadius: 10, overflow: 'hidden' }}>
          {minor}
          <FloorCtx.Provider value={ctx}>{children}</FloorCtx.Provider>
        </svg>
      </div>
    </div>
  );
}

const FloorCtx = React.createContext({ cell: 11 });

function Athlete({ x, y, role, label, dim, ring, selected }) {
  const FF = useFF();
  const { cell } = React.useContext(FloorCtx);
  const r = 2.0 * cell;
  const color = FF.role[role];
  const rr = Math.max(r, 11);
  return (
    <g opacity={dim ? 0.32 : 1}>
      {selected && <circle cx={x*cell} cy={y*cell} r={rr + 5} fill="none" stroke={FF.accent} strokeWidth={2} strokeDasharray="3 3"/>}
      {ring && <circle cx={x*cell} cy={y*cell} r={rr + 4} fill="none" stroke={color} strokeWidth={1.5} opacity={0.5}/>}
      <circle cx={x*cell} cy={y*cell} r={rr} fill={color} stroke="rgba(0,0,0,0.25)" strokeWidth={1}/>
      <text x={x*cell} y={y*cell} textAnchor="middle" dominantBaseline="central"
            fontFamily={FF.mono} fontSize={Math.max(cell * 1.15, 8.5)} fontWeight="700"
            fill={role === 'flyer' ? '#1c1500' : '#fff'}>{label}</text>
    </g>
  );
}

function Formation({ form, dim, selectedIds = [] }) {
  return <g>{athletesAt(form).map(a => <Athlete key={a.id} {...a} dim={dim} selected={selectedIds.includes(a.id)}/>)}</g>;
}

// curved transition path between two feet-points, optional waypoint
function Path({ from, to, color, waypoint, dashFlow, label }) {
  const FF = useFF();
  const { cell } = React.useContext(FloorCtx);
  const c = color || FF.accent;
  const ax = from[0]*cell, ay = from[1]*cell, bx = to[0]*cell, by = to[1]*cell;
  let d;
  if (waypoint) {
    const wx = waypoint[0]*cell, wy = waypoint[1]*cell;
    d = `M${ax} ${ay} Q ${wx} ${wy} ${bx} ${by}`;
  } else {
    const mx = (ax+bx)/2, my = (ay+by)/2 - 14;
    d = `M${ax} ${ay} Q ${mx} ${my} ${bx} ${by}`;
  }
  return (
    <g>
      <path d={d} stroke={c} strokeWidth={2.5} fill="none" strokeLinecap="round"
            strokeDasharray={dashFlow ? '2 7' : 'none'} opacity={0.9}/>
      <circle cx={ax} cy={ay} r={3} fill={c}/>
      {/* arrowhead */}
      <ArrowHead x={bx} y={by} fromX={waypoint ? waypoint[0]*cell : ax} fromY={waypoint ? waypoint[1]*cell : ay} color={c}/>
      {waypoint && <WaypointHandle x={waypoint[0]*cell} y={waypoint[1]*cell} color={c} label={label}/>}
    </g>
  );
}

function ArrowHead({ x, y, fromX, fromY, color }) {
  const ang = Math.atan2(y - fromY, x - fromX);
  const s = 7;
  const p1 = [x - s*Math.cos(ang - 0.5), y - s*Math.sin(ang - 0.5)];
  const p2 = [x - s*Math.cos(ang + 0.5), y - s*Math.sin(ang + 0.5)];
  return <path d={`M${x} ${y} L${p1[0]} ${p1[1]} L${p2[0]} ${p2[1]} Z`} fill={color}/>;
}

function WaypointHandle({ x, y, color, label }) {
  const FF = useFF();
  return (
    <g>
      <circle cx={x} cy={y} r={6} fill={FF.floor} stroke={color} strokeWidth={2}/>
      <circle cx={x} cy={y} r={2} fill={color}/>
      {label && (
        <g>
          <rect x={x + 9} y={y - 9} width={label.length * 6.2 + 10} height={16} rx={4} fill="rgba(0,0,0,0.6)" stroke={color} strokeWidth={0.75}/>
          <text x={x + 14} y={y + 2} fontFamily={FF.mono} fontSize={9.5} fontWeight="600" fill={color}>{label}</text>
        </g>
      )}
    </g>
  );
}

// ────────────────────────────────────────────────────────────────
// Chrome — top bar
// ────────────────────────────────────────────────────────────────

function TopBar({ title = 'Opening V', step }) {
  const FF = useFF();
  return (
    <div style={{
      position: 'absolute', top: 0, left: 0, right: 0, height: 52,
      display: 'flex', alignItems: 'center', gap: 14, padding: '0 18px',
      background: FF.bar, borderBottom: '1px solid ' + FF.barBd,
      backdropFilter: 'blur(12px)', zIndex: 4,
    }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 5, color: FF.accent, fontFamily: FF.sans, fontSize: 14, fontWeight: 500 }}>
        <svg width="9" height="15" viewBox="0 0 9 15" fill="none"><path d="M7.5 1.5L1.5 7.5l6 6" stroke={FF.accent} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/></svg>
        Saved Formations
      </div>
      <IconBtn glyph={G.undo} dim/>
      <div style={{ fontFamily: FF.sans, fontSize: 16, fontWeight: 700, color: FF.txt, letterSpacing: -0.2 }}>{title}</div>
      <div style={{ flex: 1 }}/>
      <FFWordmark/>
      <div style={{ flex: 1 }}/>
      <div style={{
        width: 30, height: 30, borderRadius: 15, border: '1.5px solid ' + FF.accent,
        display: 'flex', alignItems: 'center', justifyContent: 'center', color: FF.accent,
      }}>
        <svg width="15" height="15" viewBox="0 0 16 16" fill="none"><path d="M3 8h9m0 0L8.5 4.5M12 8l-3.5 3.5" stroke={FF.accent} strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round"/></svg>
      </div>
      <div style={{
        width: 30, height: 30, borderRadius: 15, border: '1.5px solid ' + FF.accent,
        display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 2.5,
      }}>
        {[0,1,2].map(i => <div key={i} style={{ width: 3, height: 3, borderRadius: 2, background: FF.accent }}/>)}
      </div>
    </div>
  );
}

function FFWordmark() {
  const FF = useFF();
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
      <div style={{ width: 18, height: 18, borderRadius: 5, background: FF.accent, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
        <svg width="11" height="11" viewBox="0 0 12 12"><path d="M2.5 9.5 L5 3 L6 6 L7.2 4.5 L9.5 9.5" stroke="#fff" strokeWidth="1.5" fill="none" strokeLinecap="round" strokeLinejoin="round"/></svg>
      </div>
      <span style={{ fontFamily: FF.mono, fontSize: 11.5, fontWeight: 600, letterSpacing: 1.4, color: FF.txt }}>FORMATIONFLOW</span>
    </div>
  );
}

const G = {
  undo: <svg width="17" height="17" viewBox="0 0 22 22" fill="none"><path d="M6 9h7a4.5 4.5 0 110 9h-2" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"/><path d="M6 9l3-3M6 9l3 3" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"/></svg>,
  plus: <svg width="16" height="16" viewBox="0 0 20 20" fill="none"><path d="M10 4v12M4 10h12" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round"/></svg>,
  list: <svg width="16" height="16" viewBox="0 0 20 20" fill="none"><path d="M7 5h9M7 10h9M7 15h9M3.5 5h.01M3.5 10h.01M3.5 15h.01" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round"/></svg>,
  note: <svg width="16" height="16" viewBox="0 0 20 20" fill="none"><rect x="4" y="3" width="12" height="14" rx="2" stroke="currentColor" strokeWidth="1.5"/><path d="M7 7h6M7 10h6M7 13h3" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round"/></svg>,
  eye: <svg width="16" height="16" viewBox="0 0 20 20" fill="none"><path d="M2 10s3-5 8-5 8 5 8 5-3 5-8 5-8-5-8-5z" stroke="currentColor" strokeWidth="1.5"/><circle cx="10" cy="10" r="2.2" stroke="currentColor" strokeWidth="1.5"/></svg>,
  play: <svg width="15" height="15" viewBox="0 0 22 22" fill="currentColor"><path d="M5 3l14 8L5 19V3z"/></svg>,
  pause: <svg width="14" height="14" viewBox="0 0 22 22" fill="currentColor"><rect x="5" y="4" width="4" height="14" rx="1"/><rect x="13" y="4" width="4" height="14" rx="1"/></svg>,
  back: <svg width="13" height="13" viewBox="0 0 22 22" fill="currentColor"><rect x="3" y="6" width="2" height="10"/><path d="M18 5L7 11l11 6V5z"/></svg>,
  fwd: <svg width="13" height="13" viewBox="0 0 22 22" fill="currentColor"><rect x="17" y="6" width="2" height="10"/><path d="M4 5l11 6L4 17V5z"/></svg>,
  loop: <svg width="15" height="15" viewBox="0 0 22 22" fill="none"><path d="M5 11a6 6 0 016-6h4m0 0l-2.5-2.5M15 5l-2.5 2.5" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"/><path d="M17 11a6 6 0 01-6 6H7m0 0l2.5 2.5M7 17l2.5-2.5" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"/></svg>,
};

function IconBtn({ glyph, active, dim, danger }) {
  const FF = useFF();
  const col = danger ? FF.role.stunt : active ? FF.accent : dim ? FF.txtFaint : FF.txtDim;
  return (
    <div style={{
      width: 34, height: 34, borderRadius: 9,
      background: active ? FF.accent + '22' : FF.tile, border: '1px solid ' + (active ? FF.accent + '88' : FF.barBd),
      display: 'flex', alignItems: 'center', justifyContent: 'center', color: col,
    }}>{glyph}</div>
  );
}

// ────────────────────────────────────────────────────────────────
// Chrome — thumbnail strip (bottom)
// ────────────────────────────────────────────────────────────────

const RAINBOW = ['#FF375F', '#FF9F0A', '#FFD60A', '#30D158', '#0A84FF', '#BF5AF2'];

function MiniThumb({ form, name, selected, index }) {
  const FF = useFF();
  const accent = RAINBOW[index % RAINBOW.length];
  const w = 56, h = 42, pad = 4;
  const sx = (w - pad*2) / COURT_W, sy = (h - pad*2) / COURT_H;
  return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 3 }}>
      <div style={{
        width: w, height: h, borderRadius: 6, background: '#0B0E12',
        border: '1.5px solid ' + (selected ? accent : FF.barBd),
        boxShadow: selected ? '0 0 0 2px ' + accent + '40' : 'none', position: 'relative',
      }}>
        <svg width={w} height={h}>
          {athletesAt(form).map(a => (
            <circle key={a.id} cx={pad + a.x*sx} cy={pad + a.y*sy} r={2.4} fill={FF.role[a.role]}/>
          ))}
        </svg>
      </div>
      <span style={{ fontFamily: FF.sans, fontSize: 9, fontWeight: selected ? 600 : 400, color: selected ? FF.txt : FF.txtDim, maxWidth: 56, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{name}</span>
    </div>
  );
}

function ThumbnailStrip({ items, selectedIndex = 0 }) {
  const FF = useFF();
  return (
    <div style={{
      position: 'absolute', left: 0, right: 0, bottom: 0, height: 84,
      display: 'flex', alignItems: 'center', gap: 6, padding: '0 16px',
      background: FF.bar, borderTop: '1px solid ' + FF.barBd, backdropFilter: 'blur(12px)', zIndex: 4,
    }}>
      {items.map((it, i) => (
        <React.Fragment key={i}>
          {i > 0 && <svg width="10" height="10" viewBox="0 0 10 10" style={{ opacity: 0.4, flexShrink: 0 }}><path d="M3 2l4 3-4 3" stroke={FF.txtDim} strokeWidth="1.3" fill="none" strokeLinecap="round" strokeLinejoin="round"/></svg>}
          <MiniThumb {...it} index={i} selected={i === selectedIndex}/>
        </React.Fragment>
      ))}
      <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 3, marginLeft: 4 }}>
        <div style={{ width: 52, height: 42, borderRadius: 6, border: '1.5px dashed ' + FF.barBd, display: 'flex', alignItems: 'center', justifyContent: 'center', color: FF.txtDim }}>{G.plus}</div>
        <span style={{ fontFamily: FF.sans, fontSize: 9, color: FF.txtDim }}>Add</span>
      </div>
      <div style={{ flex: 1 }}/>
    </div>
  );
}

// ────────────────────────────────────────────────────────────────
// Chrome — transport bar (count-based) + mode toggle
// ────────────────────────────────────────────────────────────────

function TransportBar({ playing, counts = 8, pos = 0.42, speed = '1.0×', mode }) {
  const FF = useFF();
  return (
    <div style={{
      position: 'absolute', left: 20, right: 20, bottom: 18,
      padding: '12px 16px', borderRadius: 16, background: FF.bar,
      border: '1px solid ' + FF.barBd, backdropFilter: 'blur(14px)',
      display: 'flex', flexDirection: 'column', gap: 10, zIndex: 4,
    }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
        {mode && <ModeToggle mode={mode}/>}
        <div style={{ flex: 1 }}/>
        <span style={{ fontFamily: FF.mono, fontSize: 11, color: FF.txtDim, letterSpacing: 1 }}>8-COUNT</span>
      </div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
        <Chip glyph={G.back}/>
        <div style={{ width: 40, height: 40, borderRadius: 12, background: FF.accent, color: '#fff', display: 'flex', alignItems: 'center', justifyContent: 'center', boxShadow: '0 6px 18px ' + FF.accent + '55' }}>{playing ? G.pause : G.play}</div>
        <Chip glyph={G.fwd}/>
        <span style={{ fontFamily: FF.mono, fontSize: 12, color: FF.txtDim, width: 38 }}>{(pos*counts).toFixed(1)}</span>
        <div style={{ flex: 1, height: 5, borderRadius: 3, background: 'rgba(255,255,255,0.16)', position: 'relative' }}>
          <div style={{ position: 'absolute', left: 0, top: 0, height: 5, borderRadius: 3, width: (pos*100)+'%', background: FF.accent }}/>
          <div style={{ position: 'absolute', top: '50%', left: (pos*100)+'%', width: 16, height: 16, borderRadius: 8, background: '#fff', transform: 'translate(-50%,-50%)', boxShadow: '0 2px 4px rgba(0,0,0,0.4)' }}/>
        </div>
        <span style={{ fontFamily: FF.mono, fontSize: 12, color: FF.txtDim, width: 30, textAlign: 'right' }}>{counts} ct</span>
        <Chip custom={<span style={{ fontFamily: FF.mono, fontSize: 11, fontWeight: 600 }}>{speed}</span>} wide/>
        <Chip glyph={G.loop} active/>
      </div>
    </div>
  );
}

function ModeToggle({ mode }) {
  const FF = useFF();
  const opts = ['Flow', 'Steps'];
  return (
    <div style={{ display: 'inline-flex', padding: 3, borderRadius: 10, background: 'rgba(255,255,255,0.06)', border: '1px solid ' + FF.barBd }}>
      {opts.map(o => {
        const on = o === mode;
        return (
          <div key={o} style={{
            padding: '5px 14px', borderRadius: 7, fontFamily: FF.mono, fontSize: 11, fontWeight: 600, letterSpacing: 0.5,
            background: on ? FF.accent : 'transparent', color: on ? '#fff' : FF.txtDim,
          }}>{o.toUpperCase()}</div>
        );
      })}
    </div>
  );
}

function Chip({ glyph, custom, active, danger, wide }) {
  const FF = useFF();
  return (
    <div style={{
      height: 34, minWidth: wide ? 46 : 34, padding: wide ? '0 8px' : 0, borderRadius: 9,
      background: active ? FF.accent + '22' : 'rgba(255,255,255,0.05)', border: '1px solid ' + (active ? FF.accent + '88' : FF.barBd),
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      color: active ? FF.accent : danger ? FF.role.stunt : FF.txtDim,
    }}>{custom || glyph}</div>
  );
}

// floating action chips (left, for editor screens)
function ActionRow({ children }) {
  const FF = useFF();
  return (
    <div style={{
      position: 'absolute', left: 20, top: 66, display: 'flex', alignItems: 'center', gap: 8, zIndex: 4,
    }}>{children}</div>
  );
}

function CollisionBadge({ count, label = 'spacing' }) {
  const FF = useFF();
  return (
    <div style={{
      display: 'inline-flex', alignItems: 'center', gap: 6, padding: '7px 11px', borderRadius: 20,
      background: 'rgba(255,55,95,0.16)', border: '1px solid rgba(255,55,95,0.5)', color: FF.role.stunt,
      fontFamily: FF.mono, fontSize: 11.5, fontWeight: 700,
    }}>
      <svg width="13" height="13" viewBox="0 0 16 16" fill="none"><path d="M8 2l6.5 11.5h-13L8 2z" stroke="currentColor" strokeWidth="1.4" strokeLinejoin="round"/><path d="M8 6.5v3.2M8 11.6v.01" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round"/></svg>
      {count} · {label}
    </div>
  );
}

// ────────────────────────────────────────────────────────────────
// Role legend (for roster screen, inside intro card)
// ────────────────────────────────────────────────────────────────

function RoleLegend({ proTag }) {
  const FF = useFF();
  const roles = [
    ['base','Base'], ['flyer','Flyer'], ['spotter','Spotter'],
    ['backspot','Backspot'], ['tumbler','Tumbler'], ['stunt','Stunt Grp'],
  ];
  return (
    <div>
      <div style={{ fontFamily: FF.mono, fontSize: 9.5, fontWeight: 600, color: FF.txtDim, letterSpacing: 1.5, marginBottom: 11, textTransform: 'uppercase', display: 'flex', justifyContent: 'space-between' }}>
        <span>Six roles</span>
        {proTag && <span style={{ color: FF.accent }}>PRO unlocks all</span>}
      </div>
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: '10px 8px' }}>
        {roles.map(([k, name]) => (
          <div key={k} style={{ display: 'flex', alignItems: 'center', gap: 7 }}>
            <div style={{ width: 14, height: 14, borderRadius: 7, background: FF.role[k], flexShrink: 0 }}/>
            <span style={{ fontFamily: FF.sans, fontSize: 12, color: FF.txtDim }}>{name}</span>
          </div>
        ))}
      </div>
    </div>
  );
}

// delay slider mock (for paths screen)
function DelayControl({ value = '·2 ct' }) {
  const FF = useFF();
  return (
    <div style={{ padding: 14, borderRadius: 12, background: 'rgba(0,0,0,0.28)', border: '1px solid ' + FF.barBd }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 9 }}>
        <span style={{ fontFamily: FF.mono, fontSize: 10, fontWeight: 600, color: FF.txtDim, letterSpacing: 1.3 }}>MOVE DELAY</span>
        <span style={{ fontFamily: FF.mono, fontSize: 11, fontWeight: 700, color: FF.accent }}>{value}</span>
      </div>
      <div style={{ height: 5, borderRadius: 3, background: 'rgba(255,255,255,0.14)', position: 'relative' }}>
        <div style={{ position: 'absolute', left: 0, top: 0, height: 5, borderRadius: 3, width: '28%', background: FF.accent }}/>
        <div style={{ position: 'absolute', top: '50%', left: '28%', width: 16, height: 16, borderRadius: 8, background: '#fff', transform: 'translate(-50%,-50%)', boxShadow: '0 2px 4px rgba(0,0,0,0.4)' }}/>
      </div>
      <div style={{ display: 'flex', gap: 8, marginTop: 11 }}>
        <PathPill label="Smooth" on/>
        <PathPill label="Sharp"/>
        <PathPill label="+ Waypoint" accentBtn/>
      </div>
    </div>
  );
}

function PathPill({ label, on, accentBtn }) {
  const FF = useFF();
  return (
    <div style={{
      padding: '6px 11px', borderRadius: 8, fontFamily: FF.mono, fontSize: 10.5, fontWeight: 600,
      background: accentBtn ? FF.accent : on ? 'rgba(255,255,255,0.1)' : 'transparent',
      border: '1px solid ' + (accentBtn ? FF.accent : FF.barBd),
      color: accentBtn ? '#fff' : on ? FF.txt : FF.txtDim,
    }}>{label}</div>
  );
}

// pro feature rows (outro)
function ProList() {
  const FF = useFF();
  const rows = [
    ['Unlimited formations', 'Free caps at 2'],
    ['Every athlete role', 'Free is base only'],
    ['Full-routine playback', 'Scrub end to end'],
    ['Waypoints & timing', 'Bend + stagger paths'],
  ];
  return (
    <div style={{ padding: 15, borderRadius: 12, background: 'rgba(10,132,255,0.08)', border: '1px solid ' + FF.accent + '40' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 11 }}>
        <span style={{ fontFamily: FF.mono, fontSize: 10, fontWeight: 700, color: FF.accent, letterSpacing: 1.5 }}>FORMATIONFLOW PRO</span>
        <span style={{ fontFamily: FF.sans, fontSize: 14, fontWeight: 700, color: FF.txt }}>$4.99 <span style={{ fontSize: 10, fontWeight: 500, color: FF.txtDim }}>once</span></span>
      </div>
      {rows.map((r, i) => (
        <div key={i} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '7px 0', borderBottom: i === rows.length-1 ? 'none' : '1px solid rgba(255,255,255,0.06)' }}>
          <span style={{ display: 'flex', alignItems: 'center', gap: 8, fontFamily: FF.sans, fontSize: 12.5, color: FF.txt, fontWeight: 500 }}>
            <svg width="13" height="13" viewBox="0 0 14 14" fill="none"><path d="M2.5 7.5l3 3 6-7" stroke={FF.accent} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"/></svg>
            {r[0]}
          </span>
          <span style={{ fontFamily: FF.sans, fontSize: 11, color: FF.txtFaint }}>{r[1]}</span>
        </div>
      ))}
    </div>
  );
}

// ────────────────────────────────────────────────────────────────
// Intro card + CTA + callout (shared with CoachFilm pattern)
// ────────────────────────────────────────────────────────────────

function IntroCard({ copy, align = 'center', accentItalic, primary, children }) {
  const FF = useFF();
  return (
    <div style={{
      position: 'absolute',
      ...(align === 'center' ? { top: '50%', left: '50%', transform: 'translate(-50%,-50%)' }
        : align === 'left' ? { top: '50%', left: 92, transform: 'translateY(-50%)' }
        : { top: '50%', right: 92, transform: 'translateY(-50%)' }),
      width: 432, borderRadius: 26, background: 'rgba(16,19,24,0.82)',
      backdropFilter: 'blur(30px)', border: '1px solid rgba(255,255,255,0.09)',
      boxShadow: '0 30px 80px rgba(0,0,0,0.6)', padding: 32, color: FF.txt,
      fontFamily: FF.sans, zIndex: 6,
    }}>
      <div style={{ display: 'inline-flex', alignItems: 'center', gap: 8, fontFamily: FF.mono, fontSize: 10, fontWeight: 600, color: FF.accent, letterSpacing: 1.8, textTransform: 'uppercase', marginBottom: 18 }}>
        <div style={{ width: 6, height: 6, borderRadius: 3, background: FF.accent }}/>
        {copy.eyebrow}
      </div>
      <div style={{ fontSize: 35, fontWeight: 800, lineHeight: 1.04, letterSpacing: -1, marginBottom: 14, textWrap: 'pretty' }}>
        {renderEm(copy.title, accentItalic)}
      </div>
      <div style={{ fontSize: 15, lineHeight: '23px', color: FF.txtDim, marginBottom: children ? 22 : 26 }}>{copy.body}</div>
      {children && <div style={{ marginBottom: 24 }}>{children}</div>}
      <Footer step={copy.eyebrowStep} primary={primary || copy.cta}/>
    </div>
  );
}

function Footer({ primary }) {
  return null; // replaced by FooterRow below (kept name-free to avoid step coupling)
}

function CardFooter({ step, total = 6, primary }) {
  const FF = useFF();
  return (
    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginTop: 4 }}>
      <div style={{ display: 'flex', gap: 7 }}>
        {Array.from({ length: total }).map((_, i) => (
          <div key={i} style={{ width: i === step ? 22 : 6, height: 6, borderRadius: 3, background: i === step ? FF.accent : 'rgba(255,255,255,0.18)', transition: 'width .2s' }}/>
        ))}
      </div>
      {primary && <CTAButton>{primary}</CTAButton>}
    </div>
  );
}

function CTAButton({ children }) {
  const FF = useFF();
  return (
    <button style={{
      height: 42, padding: '0 18px', borderRadius: 12, border: 'none', background: FF.accent, color: '#fff',
      fontFamily: FF.mono, fontSize: 12, fontWeight: 600, letterSpacing: 1, cursor: 'pointer',
      display: 'inline-flex', alignItems: 'center', gap: 8, textTransform: 'none',
      boxShadow: '0 8px 22px ' + FF.accent + '55', whiteSpace: 'nowrap',
    }}>
      {children}
      <svg width="12" height="9" viewBox="0 0 14 10" fill="none"><path d="M1 5h12m0 0L9 1m4 4L9 9" stroke="#fff" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/></svg>
    </button>
  );
}

function Callout({ from, to, label, color }) {
  const FF = useFF();
  const c = color || FF.accent;
  const midX = (from.x + to.x) / 2;
  return (
    <svg style={{ position: 'absolute', inset: 0, pointerEvents: 'none', zIndex: 5 }} width="1066" height="800" viewBox="0 0 1066 800">
      <path d={`M${from.x} ${from.y} Q ${midX} ${from.y}, ${midX} ${(from.y+to.y)/2} T ${to.x} ${to.y}`} stroke={c} strokeWidth="1.5" fill="none" strokeDasharray="5 4" opacity="0.85"/>
      <circle cx={to.x} cy={to.y} r="6" fill="none" stroke={c} strokeWidth="1.5"/>
      <circle cx={to.x} cy={to.y} r="2.5" fill={c}/>
      {label && <>
        <rect x={from.x - 4} y={from.y - 17} width={label.length * 6.6 + 12} height="17" rx="4" fill="rgba(12,14,18,0.9)" stroke={c} strokeWidth="0.75"/>
        <text x={from.x + 2} y={from.y - 5} fontFamily={FF.mono} fontSize="10" fontWeight="600" fill={c} letterSpacing="1">{label}</text>
      </>}
    </svg>
  );
}

// ────────────────────────────────────────────────────────────────
// Screens
// ────────────────────────────────────────────────────────────────

const THUMBS = [
  { form: FORM_V, name: 'Opening V' },
  { form: FORM_LINES, name: 'Lines' },
  { form: FORM_V, name: 'Pyramid' },
];

function Screen01() {
  const copy = useCopy('s1');
  return (
    <IPadFrame>
      <FloorSurface><Formation form={FORM_V}/></FloorSurface>
      <Scrim/>
      <TopBar title="Opening V"/>
      <ThumbnailStrip items={THUMBS} selectedIndex={0}/>
      <CardWrap copy={copy} align="right" step={0} primary={copy.cta}/>
    </IPadFrame>
  );
}

function Screen02() {
  const copy = useCopy('s2');
  return (
    <IPadFrame>
      <FloorSurface><Formation form={FORM_V} selectedIds={['a1']}/></FloorSurface>
      <Scrim/>
      <TopBar title="Opening V"/>
      <ActionRow>
        <IconBtn glyph={G.plus} active/>
        <IconBtn glyph={G.list}/>
        <IconBtn glyph={G.note}/>
      </ActionRow>
      <ThumbnailStrip items={THUMBS} selectedIndex={0}/>
      <Callout from={{ x: 318, y: 250 }} to={{ x: 533, y: 188 }} label="FLYER · A1"/>
      <CardWrap copy={copy} align="left" step={1}/>
    </IPadFrame>
  );
}

function Screen03() {
  const copy = useCopy('s3');
  return (
    <IPadFrame>
      <FloorSurface inset={{ t: 60, b: 150, x: 132 }}>
        <Formation form={FORM_V} dim/>
        <Formation form={FORM_LINES}/>
        {ROSTER.map(r => <Path key={r.id} from={FORM_V[r.id]} to={FORM_LINES[r.id]} color={useFFRole(r.role)} dashFlow/>)}
      </FloorSurface>
      <Scrim/>
      <TopBar title="V → Lines"/>
      <TransportBar playing counts={8} pos={0.42} mode="Flow"/>
      <CardWrap copy={copy} align="left" step={2}/>
    </IPadFrame>
  );
}

function Screen04() {
  const copy = useCopy('s4');
  return (
    <IPadFrame>
      <FloorSurface inset={{ t: 60, b: 150, x: 132 }}>
        <Formation form={FORM_V} dim/>
        <Formation form={FORM_LINES}/>
        <Path from={FORM_V.a4} to={FORM_LINES.a4} color="#0A84FF" waypoint={[26, 44]} label="·2 ct"/>
        <Path from={FORM_V.a8} to={FORM_LINES.a8} color="#FF9F0A" waypoint={[20, 32]}/>
      </FloorSurface>
      <Scrim/>
      <TopBar title="V → Lines"/>
      <ActionRow>
        <CollisionBadge count={1} label="path"/>
        <IconBtn glyph={G.eye} active/>
      </ActionRow>
      <TransportBar playing={false} counts={8} pos={0.3} mode="Steps"/>
      <CardWrap copy={copy} align="right" step={3}><DelayControl value="·2 ct"/></CardWrap>
    </IPadFrame>
  );
}

function Screen05() {
  const copy = useCopy('s5');
  const stunt = ['a4', 'a5', 'a6', 'a7'];
  return (
    <IPadFrame>
      <FloorSurface><Formation form={FORM_LINES} selectedIds={stunt}/></FloorSurface>
      <Scrim/>
      <TopBar title="Lines"/>
      <ActionRow>
        <div style={{
          display: 'inline-flex', alignItems: 'center', gap: 6, padding: '7px 11px', borderRadius: 20,
          background: 'rgba(10,132,255,0.16)', border: '1px solid rgba(10,132,255,0.5)',
        }}>
          <span style={{ fontFamily: 'ui-monospace, monospace', fontSize: 11.5, fontWeight: 700, color: '#0A84FF' }}>4 selected · stunt group</span>
        </div>
      </ActionRow>
      <ThumbnailStrip items={[...THUMBS, { form: FORM_LINES, name: 'Closer' }]} selectedIndex={1}/>
      <CardWrap copy={copy} align="right" step={4}/>
    </IPadFrame>
  );
}

function Screen06() {
  const copy = useCopy('s6');
  return (
    <IPadFrame>
      <FloorSurface><Formation form={FORM_V}/></FloorSurface>
      <Scrim strong/>
      <TopBar title="Opening V"/>
      <ThumbnailStrip items={THUMBS} selectedIndex={0}/>
      <CardWrap copy={copy} align="center" step={5} primary={copy.cta} wide><ProList/></CardWrap>
    </IPadFrame>
  );
}

function useFFRole(role) {
  const FF = useFF();
  return FF.role[role];
}

// Scrim so the floating card stays readable over the floor
function Scrim({ strong }) {
  return <div style={{ position: 'absolute', inset: 0, zIndex: 3, pointerEvents: 'none', background: strong
    ? 'radial-gradient(90% 80% at 50% 50%, rgba(10,12,15,0.78), rgba(10,12,15,0.5))'
    : 'linear-gradient(180deg, rgba(10,12,15,0.30) 0%, rgba(10,12,15,0.42) 55%, rgba(10,12,15,0.58) 100%)' }}/>;
}

// Intro card wrapper that also draws the page-dot footer with the right step
function CardWrap({ copy, align, step, primary, children, wide }) {
  const FF = useFF();
  const accentItalic = FF.accent;
  return (
    <div style={{
      position: 'absolute', zIndex: 6,
      ...(align === 'center' ? { top: '50%', left: '50%', transform: 'translate(-50%,-50%)' }
        : align === 'left' ? { top: '50%', left: 92, transform: 'translateY(-50%)' }
        : { top: '50%', right: 92, transform: 'translateY(-50%)' }),
      width: wide ? 470 : 432, borderRadius: 26, background: 'rgba(16,19,24,0.82)',
      backdropFilter: 'blur(30px)', border: '1px solid rgba(255,255,255,0.09)',
      boxShadow: '0 30px 80px rgba(0,0,0,0.6)', padding: 32, color: FF.txt, fontFamily: FF.sans,
    }}>
      <div style={{ display: 'inline-flex', alignItems: 'center', gap: 8, fontFamily: FF.mono, fontSize: 10, fontWeight: 600, color: FF.accent, letterSpacing: 1.8, textTransform: 'uppercase', marginBottom: 18 }}>
        <div style={{ width: 6, height: 6, borderRadius: 3, background: FF.accent }}/>
        {copy.eyebrow}
      </div>
      <div style={{ fontSize: 34, fontWeight: 800, lineHeight: 1.05, letterSpacing: -0.9, marginBottom: 14, textWrap: 'pretty' }}>
        {renderEm(copy.title, accentItalic)}
      </div>
      <div style={{ fontSize: 14.5, lineHeight: '22px', color: FF.txtDim, marginBottom: children ? 20 : 26 }}>{copy.body}</div>
      {children && <div style={{ marginBottom: 22 }}>{children}</div>}
      <CardFooter step={step} primary={primary}/>
    </div>
  );
}

// ────────────────────────────────────────────────────────────────
// iPhone-portrait device exploration
// ────────────────────────────────────────────────────────────────

function PhoneFrame({ children }) {
  return (
    <div style={{
      width: 393, height: 852, borderRadius: 54, background: '#050608',
      boxShadow: '0 30px 80px rgba(0,0,0,0.45), 0 0 0 1px rgba(0,0,0,0.7)',
      padding: 13, position: 'relative', WebkitFontSmoothing: 'antialiased',
    }}>
      <div style={{ width: '100%', height: '100%', background: '#0A0C0F', borderRadius: 42, overflow: 'hidden', position: 'relative' }}>
        {children}
        {/* dynamic island */}
        <div style={{ position: 'absolute', top: 11, left: '50%', transform: 'translateX(-50%)', width: 116, height: 33, borderRadius: 17, background: '#000', zIndex: 20 }}/>
      </div>
    </div>
  );
}

function PhoneStatusBar() {
  const FF = useFF();
  return (
    <div style={{ position: 'absolute', top: 0, left: 0, right: 0, height: 50, display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '0 26px', zIndex: 6, color: FF.txt, fontFamily: FF.sans, fontSize: 14, fontWeight: 600 }}>
      <span style={{ marginTop: 4 }}>9:41</span>
      <span style={{ marginTop: 4, display: 'flex', gap: 6, alignItems: 'center', fontSize: 12, opacity: 0.9 }}>
        <svg width="17" height="11" viewBox="0 0 17 11" fill="currentColor"><rect x="0" y="7" width="3" height="4" rx="1"/><rect x="4.5" y="5" width="3" height="6" rx="1"/><rect x="9" y="3" width="3" height="8" rx="1"/><rect x="13.5" y="0" width="3" height="11" rx="1"/></svg>
        <svg width="24" height="12" viewBox="0 0 24 12" fill="none"><rect x="1" y="1" width="20" height="10" rx="3" stroke="currentColor" strokeWidth="1" opacity="0.5"/><rect x="2.5" y="2.5" width="15" height="7" rx="1.5" fill="currentColor"/><rect x="22" y="4" width="1.5" height="4" rx="0.75" fill="currentColor" opacity="0.5"/></svg>
      </span>
    </div>
  );
}

function PhoneTopBar({ title }) {
  const FF = useFF();
  return (
    <div style={{ position: 'absolute', top: 50, left: 0, right: 0, height: 46, display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '0 16px', zIndex: 6, background: FF.bar, borderBottom: '1px solid ' + FF.barBd, backdropFilter: 'blur(12px)' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 3, color: FF.accent, fontFamily: FF.sans, fontSize: 14, fontWeight: 500 }}>
        <svg width="8" height="14" viewBox="0 0 9 15" fill="none"><path d="M7.5 1.5L1.5 7.5l6 6" stroke={FF.accent} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/></svg>
        Saved
      </div>
      <div style={{ fontFamily: FF.sans, fontSize: 15, fontWeight: 700, color: FF.txt }}>{title}</div>
      <div style={{ width: 26, height: 26, borderRadius: 13, border: '1.5px solid ' + FF.accent, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 2 }}>
        {[0,1,2].map(i => <div key={i} style={{ width: 2.5, height: 2.5, borderRadius: 2, background: FF.accent }}/>)}
      </div>
    </div>
  );
}

function PhoneCourt({ form, dim, selectedIds = [], paths, secondForm }) {
  const FF = useFF();
  const top = 108;
  const padX = 14;
  const courtW = 393 - padX * 2;
  const courtH = courtW * (COURT_H / COURT_W);
  const cell = courtW / COURT_W;
  const minor = [];
  for (let c = 0; c <= COURT_W; c++) minor.push(<line key={'v'+c} x1={c*cell} y1={0} x2={c*cell} y2={courtH} stroke={c % PANEL === 0 ? FF.gridMajor : FF.gridMinor} strokeWidth={c % PANEL === 0 ? 1 : 0.5}/>);
  for (let r = 0; r <= COURT_H; r++) minor.push(<line key={'h'+r} x1={0} y1={r*cell} x2={courtW} y2={r*cell} stroke={r % PANEL === 0 ? FF.gridMajor : FF.gridMinor} strokeWidth={r % PANEL === 0 ? 1 : 0.5}/>);
  return (
    <div style={{ position: 'absolute', left: padX, top, width: courtW, height: courtH, background: FF.floor, borderRadius: 10, border: '1px solid ' + FF.floorEdge, boxShadow: '0 12px 36px rgba(0,0,0,0.5)' }}>
      <svg width={courtW} height={courtH} style={{ display: 'block', borderRadius: 10 }}>
        {minor}
        <FloorCtx.Provider value={{ cell, courtW, courtH }}>
          {secondForm && <Formation form={secondForm} dim/>}
          {paths}
          <Formation form={form} dim={dim} selectedIds={selectedIds}/>
        </FloorCtx.Provider>
      </svg>
    </div>
  );
}

function PhoneStrip({ items, selectedIndex = 0, y = 396 }) {
  const FF = useFF();
  return (
    <div style={{ position: 'absolute', left: 0, right: 0, top: y, height: 70, display: 'flex', alignItems: 'center', gap: 5, padding: '0 14px', overflow: 'hidden', zIndex: 5 }}>
      {items.map((it, i) => (
        <React.Fragment key={i}>
          {i > 0 && <svg width="9" height="9" viewBox="0 0 10 10" style={{ opacity: 0.4, flexShrink: 0 }}><path d="M3 2l4 3-4 3" stroke={FF.txtDim} strokeWidth="1.3" fill="none" strokeLinecap="round" strokeLinejoin="round"/></svg>}
          <MiniThumb {...it} index={i} selected={i === selectedIndex}/>
        </React.Fragment>
      ))}
      <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 3, marginLeft: 2, flexShrink: 0 }}>
        <div style={{ width: 48, height: 38, borderRadius: 6, border: '1.5px dashed ' + FF.barBd, display: 'flex', alignItems: 'center', justifyContent: 'center', color: FF.txtDim }}>{G.plus}</div>
        <span style={{ fontFamily: FF.sans, fontSize: 9, color: FF.txtDim }}>Add</span>
      </div>
    </div>
  );
}

function PhoneSheet({ copy, step, primary, children }) {
  const FF = useFF();
  return (
    <div style={{
      position: 'absolute', left: 0, right: 0, bottom: 0, zIndex: 8,
      borderTopLeftRadius: 28, borderTopRightRadius: 28,
      background: 'rgba(16,19,24,0.92)', backdropFilter: 'blur(30px)',
      borderTop: '1px solid rgba(255,255,255,0.10)', boxShadow: '0 -20px 60px rgba(0,0,0,0.5)',
      padding: '14px 24px 34px', color: FF.txt, fontFamily: FF.sans,
    }}>
      <div style={{ width: 38, height: 5, borderRadius: 3, background: 'rgba(255,255,255,0.22)', margin: '0 auto 18px' }}/>
      <div style={{ display: 'inline-flex', alignItems: 'center', gap: 7, fontFamily: FF.mono, fontSize: 9.5, fontWeight: 600, color: FF.accent, letterSpacing: 1.6, textTransform: 'uppercase', marginBottom: 12 }}>
        <div style={{ width: 5, height: 5, borderRadius: 3, background: FF.accent }}/>
        {copy.eyebrow}
      </div>
      <div style={{ fontSize: 25, fontWeight: 800, lineHeight: 1.08, letterSpacing: -0.6, marginBottom: 11, textWrap: 'pretty' }}>{renderEm(copy.title, FF.accent)}</div>
      <div style={{ fontSize: 13.5, lineHeight: '20px', color: FF.txtDim, marginBottom: children ? 16 : 22 }}>{copy.body}</div>
      {children && <div style={{ marginBottom: 18 }}>{children}</div>}
      <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: primary ? 16 : 0 }}>
        {Array.from({ length: 6 }).map((_, i) => (
          <div key={i} style={{ width: i === step ? 20 : 6, height: 6, borderRadius: 3, background: i === step ? FF.accent : 'rgba(255,255,255,0.18)', transition: 'width .2s' }}/>
        ))}
      </div>
      {primary && (
        <button style={{ width: '100%', height: 46, borderRadius: 13, border: 'none', background: FF.accent, color: '#fff', fontFamily: FF.mono, fontSize: 12.5, fontWeight: 600, cursor: 'pointer', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 8, boxShadow: '0 8px 22px ' + FF.accent + '55', whiteSpace: 'nowrap' }}>
          {primary}
          <svg width="12" height="9" viewBox="0 0 14 10" fill="none"><path d="M1 5h12m0 0L9 1m4 4L9 9" stroke="#fff" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/></svg>
        </button>
      )}
    </div>
  );
}

function PhoneScreen({ children }) {
  return <PhoneFrame>{children}</PhoneFrame>;
}

function PScreen01() {
  const copy = useCopy('s1');
  return (<PhoneScreen><PhoneStatusBar/><PhoneTopBar title="Opening V"/><PhoneCourt form={FORM_V}/><PhoneStrip items={THUMBS} selectedIndex={0}/><PhoneSheet copy={copy} step={0} primary={copy.cta}/></PhoneScreen>);
}
function PScreen02() {
  const copy = useCopy('s2');
  return (<PhoneScreen><PhoneStatusBar/><PhoneTopBar title="Opening V"/><PhoneCourt form={FORM_V} selectedIds={['a1']}/><PhoneStrip items={THUMBS} selectedIndex={0}/><PhoneSheet copy={copy} step={1}/></PhoneScreen>);
}
function PScreen03() {
  const copy = useCopy('s3');
  const paths = ROSTER.map(r => <Path key={r.id} from={FORM_V[r.id]} to={FORM_LINES[r.id]} color={FF_ROLE[r.role]} dashFlow/>);
  return (<PhoneScreen><PhoneStatusBar/><PhoneTopBar title="V → Lines"/><PhoneCourt form={FORM_LINES} secondForm={FORM_V} paths={paths}/><PhoneTransport mode="Flow"/><PhoneSheet copy={copy} step={2}/></PhoneScreen>);
}
function PScreen04() {
  const copy = useCopy('s4');
  const paths = [
    <Path key="4" from={FORM_V.a4} to={FORM_LINES.a4} color="#0A84FF" waypoint={[26, 44]} label="·2 ct"/>,
    <Path key="8" from={FORM_V.a8} to={FORM_LINES.a8} color="#FF9F0A" waypoint={[20, 32]}/>,
  ];
  return (<PhoneScreen><PhoneStatusBar/><PhoneTopBar title="V → Lines"/><PhoneCourt form={FORM_LINES} secondForm={FORM_V} paths={paths}/><PhoneCollision/><PhoneSheet copy={copy} step={3}><DelayControl value="·2 ct"/></PhoneSheet></PhoneScreen>);
}
function PScreen05() {
  const copy = useCopy('s5');
  return (<PhoneScreen><PhoneStatusBar/><PhoneTopBar title="Lines"/><PhoneCourt form={FORM_LINES} selectedIds={['a4','a5','a6','a7']}/><PhoneStrip items={[...THUMBS, { form: FORM_LINES, name: 'Closer' }]} selectedIndex={1}/><PhoneSheet copy={copy} step={4}/></PhoneScreen>);
}
function PScreen06() {
  const copy = useCopy('s6');
  return (<PhoneScreen><PhoneStatusBar/><PhoneTopBar title="Opening V"/><PhoneCourt form={FORM_V}/><PhoneStrip items={THUMBS} selectedIndex={0}/><PhoneSheet copy={copy} step={5} primary={copy.cta}><ProList/></PhoneSheet></PhoneScreen>);
}

function PhoneTransport({ mode }) {
  const FF = useFF();
  return (
    <div style={{ position: 'absolute', left: 14, right: 14, top: 400, zIndex: 5, padding: '9px 11px', borderRadius: 14, background: 'rgba(20,24,30,0.96)', border: '1px solid ' + FF.barBd, boxShadow: '0 10px 30px rgba(0,0,0,0.5)', display: 'flex', alignItems: 'center', gap: 9 }}>
      <ModeToggle mode={mode}/>
      <div style={{ width: 32, height: 32, borderRadius: 9, background: FF.accent, color: '#fff', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>{G.play}</div>
      <div style={{ flex: 1, height: 4, borderRadius: 2, background: 'rgba(255,255,255,0.16)', position: 'relative' }}>
        <div style={{ position: 'absolute', left: 0, top: 0, height: 4, borderRadius: 2, width: '42%', background: FF.accent }}/>
        <div style={{ position: 'absolute', top: '50%', left: '42%', width: 12, height: 12, borderRadius: 6, background: '#fff', transform: 'translate(-50%,-50%)' }}/>
      </div>
      <span style={{ fontFamily: FF.mono, fontSize: 11, color: FF.txtDim, flexShrink: 0 }}>8 ct</span>
    </div>
  );
}

function PhoneCollision() {
  const FF = useFF();
  return (
    <div style={{ position: 'absolute', left: 14, top: 360, zIndex: 5 }}>
      <CollisionBadge count={1} label="path"/>
    </div>
  );
}

const FF_ROLE = { base: '#0A84FF', flyer: '#FFD60A', spotter: '#30D158', backspot: '#BF5AF2', tumbler: '#FF9F0A', stunt: '#FF375F' };

// ────────────────────────────────────────────────────────────────
// Styles + exports
// ────────────────────────────────────────────────────────────────

(function injectStyles() {
  if (document.getElementById('ffIntroStyles')) return;
  const s = document.createElement('style');
  s.id = 'ffIntroStyles';
  s.textContent = `@keyframes ffPulse{0%,100%{opacity:1}50%{opacity:.55}}`;
  document.head.appendChild(s);
})();

window.FFIntro = { Screen01, Screen02, Screen03, Screen04, Screen05, Screen06,
  PScreen01, PScreen02, PScreen03, PScreen04, PScreen05, PScreen06 };
window.FFThemeCtx = FFThemeCtx;
window.FFCopyCtx = FFCopyCtx;
window.FF_DEFAULTS = FF_DEFAULTS;
