// Avenor — phones.js
// Renders iPhone mockups from data-* attributes.
// Drop:  <div data-phone="command" data-theme="dark" data-size="lg"></div>
// Available screens: command, command-empty, tasks, notes, goals, calendar, capture
// Themes: dark | light | earth | glass
// Sizes:  sm | md | lg | (omit for default 320×680)

(function () {
  'use strict';

  // ── Reusable markup builders ───────────────────────────────────────
  function statusBar() {
    return `<div class="status">
      <span>9:41</span>
      <span class="status-r">
        <span class="icn-signal"></span>
        <span class="icn-wifi"></span>
        <span class="icn-batt"></span>
      </span>
    </div>`;
  }

  function tabbar(active) {
    const tabs = [
      { id: 'overview', label: 'Overview', svg: '<rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/>' },
      { id: 'tasks',    label: 'Tasks',    svg: '<rect x="3" y="3" width="18" height="18" rx="3"/><polyline points="8 12 11 15 16 9" fill="none" stroke-width="2"/>' },
      { id: 'notes',    label: 'Notes',    svg: '<path d="M6 3h9l5 5v13H6z"/><line x1="9" y1="11" x2="17" y2="11" stroke-width="1.5"/><line x1="9" y1="15" x2="17" y2="15" stroke-width="1.5"/>' },
      { id: 'goals',    label: 'Goals',    svg: '<circle cx="12" cy="12" r="8" fill="none" stroke-width="2"/><circle cx="12" cy="12" r="3"/><line x1="12" y1="2" x2="12" y2="6" stroke-width="2"/><line x1="12" y1="18" x2="12" y2="22" stroke-width="2"/><line x1="2" y1="12" x2="6" y2="12" stroke-width="2"/><line x1="18" y1="12" x2="22" y2="12" stroke-width="2"/>' },
      { id: 'calendar', label: 'Calendar', svg: '<rect x="3" y="5" width="18" height="16" rx="2" fill="none" stroke-width="1.8"/><line x1="3" y1="10" x2="21" y2="10" stroke-width="1.8"/><line x1="8" y1="3" x2="8" y2="7" stroke-width="1.8"/><line x1="16" y1="3" x2="16" y2="7" stroke-width="1.8"/><circle cx="8"  cy="14" r="1"/><circle cx="12" cy="14" r="1"/><circle cx="16" cy="14" r="1"/><circle cx="8"  cy="18" r="1"/><circle cx="12" cy="18" r="1"/>' },
    ];
    return `<div class="tabbar">${tabs.map(t => `
      <div class="tab ${t.id === active ? 'active' : ''}">
        <svg class="ico" viewBox="0 0 24 24" fill="currentColor" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round">${t.svg}</svg>
        <span>${t.label}</span>
      </div>`).join('')}</div>`;
  }

  function captureBar(value, blink = true) {
    if (value) {
      return `<div class="scr-capture">
        <span class="prompt">&gt;</span>
        <span style="flex:1;">${value}</span>
        ${blink ? '<span class="caret"></span>' : ''}
      </div>`;
    }
    return `<div class="scr-capture">
      <span class="prompt">&gt;</span>
      <span class="ph">Capture intent…</span>
    </div>`;
  }

  // ── Individual screens ─────────────────────────────────────────────

  const SCREENS = {

    // 1) Command — populated overview
    'command': () => `
      <div class="scr">
        <div class="scr-cmd-title">
          <span>COMMAND</span>
          <span class="gear">⚙</span>
        </div>
        <div class="scr-meta">May 27, 2026 · Registry Status: Active</div>
        ${captureBar()}

        <div class="scr-section first"><span>Due Today</span><span class="sep">·</span><span class="cnt">1</span></div>
        <div class="scr-item" style="--c: var(--app-todo);">
          <div class="rail"></div>
          <div class="row-meta"><span>TODO</span><span class="sep">·</span><span>Due Today at 7:00 PM</span></div>
          <div class="row-main">
            <div class="check"></div>
            <div class="row-title">Gym</div>
            <div class="chev">⌄</div>
          </div>
        </div>

        <div class="scr-section"><span>Active Metrics</span><span class="sep">·</span><span class="cnt">1</span></div>
        <div class="scr-item" style="--c: var(--app-goal);">
          <div class="rail"></div>
          <div class="row-title">Read 100 books</div>
          <div class="row-meta" style="margin-top:6px;">
            <span>Goal</span><span class="sep">·</span><span>5 / 100 books</span><span class="pct">5%</span>
          </div>
          <div class="progress"><div style="width:5%;"></div></div>
        </div>

        <div class="scr-section"><span>Recent Brain Dumps</span><span class="sep">·</span><span class="cnt">1</span></div>
        <div class="scr-item" style="--c: var(--app-note); border-bottom: none;">
          <div class="rail"></div>
          <div class="row-meta"><span>NOTE</span><span class="sep">·</span><span>0 Words</span><span class="sep">·</span><span>Edited May 27</span></div>
          <div class="row-title">Jygduysha</div>
        </div>

        ${tabbar('overview')}
      </div>
    `,

    // 2) Command empty — onboarding-feel
    'command-empty': () => `
      <div class="scr">
        <div class="scr-cmd-title">
          <span>COMMAND</span>
          <span class="gear">⚙</span>
        </div>
        <div class="scr-meta">May 27, 2026 · Registry Status: Active</div>
        ${captureBar()}

        <div class="scr-section first"><span>Due Today</span><span class="sep">·</span><span class="cnt">0</span></div>
        <div class="scr-empty" style="margin-top:14px;">No action items due today.<span class="l2">Inbox holds the line.</span></div>

        <div class="scr-section" style="margin-top:64px;"><span>Active Metrics</span><span class="sep">·</span><span class="cnt">0</span></div>
        <div class="scr-empty" style="margin-top:14px;">No metrics tracked.<span class="l2">Open goals to define one.</span></div>

        <div class="scr-section" style="margin-top:64px;"><span>Recent Brain Dumps</span><span class="sep">·</span><span class="cnt">0</span></div>
        <div class="scr-empty" style="margin-top:14px;">No notes recorded.<span class="l2">Capture a thought in Notes.</span></div>

        ${tabbar('overview')}
      </div>
    `,

    // 3) Tasks — with mid-swipe row
    'tasks': () => `
      <div class="scr">
        <div class="scr-navtitle">
          <span class="btn-circle">Al</span>
          <span class="ctr">Tasks</span>
          <span class="btn-circle">+</span>
        </div>
        <div class="scr-search">
          <span class="mag"></span>
          <span>Search tasks</span>
        </div>
        <div class="scr-bigtitle">Today</div>
        <div style="height:8px;"></div>
        <div class="scr-stats">
          <div class="stat"><div class="n">3</div><div class="lab">Due Today</div></div>
          <div class="stat"><div class="n">7</div><div class="lab">Upcoming</div></div>
          <div class="stat"><div class="n">2</div><div class="lab">Marinating</div></div>
        </div>
        <div class="scr-rowfilt">
          <div class="ll">Your List<span class="small">3 items</span></div>
          <div class="pill">Filter ≡</div>
        </div>

        <div class="scr-item" style="--c: var(--app-todo);">
          <div class="rail"></div>
          <div class="row-meta"><span>TODO</span><span class="sep">·</span><span>Due Today at 7:00 PM</span></div>
          <div class="row-main">
            <div class="check"></div>
            <div class="row-title">Gym</div>
            <div class="chev">⌄</div>
          </div>
        </div>

        <div class="scr-item" style="--c: var(--app-rem);">
          <div class="rail"></div>
          <div class="row-meta"><span>REMINDER</span><span class="sep">·</span><span>Tomorrow · 9:00 AM</span></div>
          <div class="row-main">
            <div class="check"></div>
            <div class="row-title">Call dad</div>
            <div class="chev">⌄</div>
          </div>
        </div>

        <div class="scr-item" style="--c: var(--app-todo); border-bottom:none; position:relative; overflow:hidden;">
          <div class="rail"></div>
          <div class="row-meta"><span>TODO</span><span class="sep">·</span><span>Friday · 9:00 AM</span><span class="sep">·</span><span>P1</span></div>
          <div class="row-main">
            <div class="check"></div>
            <div class="row-title" style="transform: translateX(-32px);">Ship Avenor beta</div>
            <div class="chev">⌄</div>
          </div>
          <div style="position:absolute; right:0; top:0; bottom:0; width:64px; background: var(--app-todo); display:flex; align-items:center; justify-content:center; color:#0A0A0C; font-size:11px; font-weight:600;">Done</div>
        </div>

        ${tabbar('tasks')}
      </div>
    `,

    // 4) Notes — with editor
    'notes': () => `
      <div class="scr">
        <div class="scr-navtitle">
          <span style="width:32px;"></span>
          <span class="ctr">Notes</span>
          <span class="btn-circle">+</span>
        </div>
        <div class="scr-search">
          <span class="mag"></span>
          <span>Search notes</span>
        </div>
        <div class="scr-bigtitle">Notes</div>
        <div class="scr-meta" style="margin: 4px 0 12px;">1 Note</div>

        <div class="scr-item" style="--c: var(--app-note); border-bottom: none;">
          <div class="rail"></div>
          <div class="row-meta"><span>NOTE</span><span class="sep">·</span><span>32 Words</span><span class="sep">·</span><span>Edited Today</span></div>
          <div class="row-title" style="margin-bottom: 10px;">On editorial typefaces in software</div>
          <div style="font-family: var(--font-text); font-size: 11px; line-height: 1.5; color: var(--p-fg-2, var(--fg-2));">
            <b>Bold</b>, <i>italic</i>, and bulleted lists render inline. The body
            keeps its quiet typographic feeling — no markdown chrome, no menus.
          </div>
        </div>

        ${tabbar('notes')}
      </div>
    `,

    // 5) Goals — with progress
    'goals': () => `
      <div class="scr">
        <div class="scr-navtitle">
          <span class="btn-circle">Al</span>
          <span class="ctr">Goals</span>
          <span class="btn-circle">+</span>
        </div>
        <div class="scr-search">
          <span class="mag"></span>
          <span>Search goals</span>
        </div>
        <div class="scr-bigtitle">Goals</div>
        <div class="scr-meta" style="margin: 4px 0 14px;">3 Items</div>
        <div class="scr-rowfilt">
          <div class="ll">Your List</div>
          <div class="pill">Current ≡</div>
        </div>

        <div class="scr-item" style="--c: var(--app-goal);">
          <div class="rail"></div>
          <div class="row-title">Read 100 books</div>
          <div class="row-meta" style="margin-top:6px;">
            <span>Goal</span><span class="sep">·</span><span>5 / 100 books</span><span class="pct">5%</span>
          </div>
          <div class="progress"><div style="width:5%;"></div></div>
        </div>

        <div class="scr-item" style="--c: var(--app-goal);">
          <div class="rail"></div>
          <div class="row-title">Run 500 km</div>
          <div class="row-meta" style="margin-top:6px;">
            <span>Goal</span><span class="sep">·</span><span>312 / 500 km</span><span class="pct">62%</span>
          </div>
          <div class="progress"><div style="width:62%;"></div></div>
        </div>

        <div class="scr-item" style="--c: var(--app-goal); border-bottom: none;">
          <div class="rail"></div>
          <div class="row-title">Ship Avenor v1.0</div>
          <div class="row-meta" style="margin-top:6px;">
            <span>Goal</span><span class="sep">·</span><span>14 / 23 tasks</span><span class="pct">61%</span>
          </div>
          <div class="progress"><div style="width:61%;"></div></div>
        </div>

        ${tabbar('goals')}
      </div>
    `,

    // 6) Calendar — month grid
    'calendar': () => {
      const dim = [26,27,28,29,30,'·','·']; const _ = '·';
      const days = [];
      // May 2026: 1st is Friday → dim Sun-Thu (26 Apr…30 Apr)
      const cells = [
        ['d',26],['d',27],['d',28],['d',29],['d',30],['',1],['',2],
        ['',3],['',4],['',5],['',6],['',7],['',8],['',9],
        ['',10],['',11],['',12],['',13],['',14],['',15],['',16],
        ['',17],['',18],['',19],['',20],['',21],['',22],['',23],
        ['',24],['',25],['',26],['sel',27],['',28],['',29],['',30],
        ['',31],['d',1],['d',2],['d',3],['d',4],['d',5],['d',6],
      ];
      const dotMap = {
        4:  ['var(--app-todo)'],
        7:  ['var(--app-rem)','var(--app-todo)'],
        13: ['var(--app-note)'],
        15: ['var(--app-todo)','var(--app-goal)','var(--app-rem)'],
        20: ['var(--app-todo)','var(--app-rem)'],
        22: ['var(--app-goal)'],
        27: ['var(--app-todo)','var(--app-rem)'],
        29: ['var(--app-todo)'],
      };
      const cellsHtml = cells.map(([k, n]) => {
        const dots = dotMap[n] ? `<div class="dots">${dotMap[n].map(c => `<span style="background:${c};"></span>`).join('')}</div>` : '';
        const cls  = ['day', k === 'd' ? 'dim' : '', k === 'sel' ? 'sel' : ''].filter(Boolean).join(' ');
        return `<div class="${cls}">${n}${dots}</div>`;
      }).join('');

      return `
      <div class="scr">
        <div class="scr-navtitle"><span style="width:32px;"></span><span class="ctr">Calendar</span><span style="width:32px;"></span></div>

        <div class="scr-cal">
          <div class="cal-head">
            <span class="nav-arrow">‹</span>
            <span class="month">May 2026</span>
            <span class="nav-arrow">›</span>
          </div>
          <div class="dow"><span>SUN</span><span>MON</span><span>TUE</span><span>WED</span><span>THU</span><span>FRI</span><span>SAT</span></div>
          <div class="days">${cellsHtml}</div>
        </div>

        <div class="scr-meta">Wednesday, May 27 · 2 Tasks</div>

        <div class="scr-item" style="--c: var(--app-todo);">
          <div class="rail"></div>
          <div class="row-meta"><span>TODO</span><span class="sep">·</span><span>7:00 PM</span></div>
          <div class="row-main"><div class="check"></div><div class="row-title">Gym</div></div>
        </div>
        <div class="scr-item" style="--c: var(--app-rem); border-bottom: none;">
          <div class="rail"></div>
          <div class="row-meta"><span>REMINDER</span><span class="sep">·</span><span>5:00 PM</span></div>
          <div class="row-main"><div class="check"></div><div class="row-title">Reschedule dentist</div></div>
        </div>

        ${tabbar('calendar')}
      </div>
      `;
    },

    // 7) Capture-focused screen (for capture page mockup variations)
    'capture-typing': () => `
      <div class="scr">
        <div class="scr-cmd-title">
          <span>COMMAND</span>
          <span class="gear">⚙</span>
        </div>
        <div class="scr-meta">May 27, 2026 · Registry Status: Active</div>
        ${captureBar('gym tomorrow @7am !!', true)}

        <div class="scr-section first"><span>Result</span></div>
        <div class="scr-item" style="--c: var(--app-rem); border-bottom: none;">
          <div class="rail"></div>
          <div class="row-meta"><span>REMINDER</span><span class="sep">·</span><span>Tomorrow · 7:00 AM</span><span class="sep">·</span><span>P2</span></div>
          <div class="row-main">
            <div class="check"></div>
            <div class="row-title">Gym</div>
          </div>
        </div>

        ${tabbar('overview')}
      </div>
    `,

    // 8) Widgets — home screen with Avenor widget
    'widgets': () => `
      <div class="scr" style="padding: 54px 18px; background: linear-gradient(180deg, #1a1a1f 0%, #0A0A0C 100%);">
        <div style="font-family: var(--font-display); font-size: 36px; font-weight: 700; color: #fff; text-align: center; margin-bottom: 6px;">9:41</div>
        <div style="font-family: var(--font-text); font-size: 16px; color: rgba(255,255,255,0.85); text-align: center; margin-bottom: 32px;">Wednesday, May 27</div>

        <div style="background: rgba(255,255,255,0.10); backdrop-filter: blur(20px); border: 1px solid rgba(255,255,255,0.20); border-radius: 22px; padding: 20px;">
          <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 16px;">
            <div style="font-family: var(--font-mono); font-size: 9px; letter-spacing: 0.14em; text-transform: uppercase; color: rgba(255,255,255,0.55);">Avenor · Today</div>
            <div style="font-family: var(--font-display); font-size: 12px; color: #fff; font-weight: 600;">3</div>
          </div>
          <div style="font-family: var(--font-text); font-size: 11px; color: #fff; line-height: 1.5; margin-bottom: 4px;">
            <span style="color:var(--app-todo); margin-right:6px;">●</span>Ship Avenor beta · <span style="color:rgba(255,255,255,0.5);">Fri 9:00 AM</span>
          </div>
          <div style="font-family: var(--font-text); font-size: 11px; color: #fff; line-height: 1.5; margin-bottom: 4px;">
            <span style="color:var(--app-rem); margin-right:6px;">●</span>Call dad · <span style="color:rgba(255,255,255,0.5);">Tomorrow 9:00 AM</span>
          </div>
          <div style="font-family: var(--font-text); font-size: 11px; color: #fff; line-height: 1.5;">
            <span style="color:var(--app-todo); margin-right:6px;">●</span>Gym · <span style="color:rgba(255,255,255,0.5);">Today 7:00 PM</span>
          </div>
          <div style="border-top: 1px solid rgba(255,255,255,0.15); margin: 14px 0 12px;"></div>
          <div style="display:flex; gap: 6px; align-items: center; font-family: var(--font-mono); font-size: 9px; color: rgba(255,255,255,0.55); letter-spacing: 0.10em;">
            <span style="font-family: var(--font-mono);">&gt;</span><span>Tap to capture</span>
          </div>
        </div>

        <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 14px; margin-top: 14px;">
          <div style="aspect-ratio: 1; background: rgba(74,158,255,0.20); border-radius: 22px;"></div>
          <div style="aspect-ratio: 1; background: rgba(255,179,71,0.20); border-radius: 22px;"></div>
        </div>
      </div>
    `,
  };

  // ── Hydrate ─────────────────────────────────────────────────────────
  function hydrate(el) {
    const screen = el.dataset.phone;
    const theme  = el.dataset.theme || 'dark';
    const size   = el.dataset.size  || '';
    const fn = SCREENS[screen];
    if (!fn) return;

    el.classList.add('phone');
    if (size) el.classList.add(size);
    el.innerHTML = `
      <div class="phone-screen t-${theme}">
        <div class="island"></div>
        ${statusBar()}
        <div class="home-bar"></div>
        ${fn()}
      </div>
    `;
  }

  document.querySelectorAll('[data-phone]').forEach(hydrate);

})();
