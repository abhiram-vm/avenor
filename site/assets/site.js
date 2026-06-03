// Avenor marketing site — site.js
// Tiny, no framework. Wired up on DOMContentLoaded.

(function () {
  'use strict';

  // ── Nav backdrop on scroll ─────────────────────────────────────────
  const nav = document.querySelector('.nav');
  if (nav) {
    const onScroll = () => nav.classList.toggle('scrolled', window.scrollY > 16);
    window.addEventListener('scroll', onScroll, { passive: true });
    onScroll();
  }

  // ── Mobile nav drawer ──────────────────────────────────────────────
  const navToggle = document.querySelector('.nav-toggle');
  const navDrawer = document.querySelector('.nav-drawer');
  if (navToggle && navDrawer) {
    const setOpen = (open) => {
      navToggle.setAttribute('aria-expanded', String(open));
      navDrawer.classList.toggle('open', open);
      document.body.classList.toggle('drawer-open', open);
    };
    navToggle.addEventListener('click', () => {
      const open = navToggle.getAttribute('aria-expanded') !== 'true';
      setOpen(open);
    });
    // Close when a link inside the drawer is tapped
    navDrawer.querySelectorAll('a').forEach(a => {
      a.addEventListener('click', () => setOpen(false));
    });
    // Close on Escape
    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') setOpen(false);
    });
    // Close if the viewport grows past the mobile breakpoint
    const mq = window.matchMedia('(min-width: 921px)');
    mq.addEventListener('change', (e) => { if (e.matches) setOpen(false); });
  }

  // ── Scroll reveal (IntersectionObserver) ───────────────────────────
  const reveals = document.querySelectorAll('.reveal');
  if (reveals.length) {
    const io = new IntersectionObserver((entries) => {
      entries.forEach(e => {
        if (e.isIntersecting) {
          e.target.classList.add('in');
          io.unobserve(e.target);
        }
      });
    }, { threshold: 0.12, rootMargin: '0px 0px -10% 0px' });
    reveals.forEach(el => io.observe(el));
  }

  // ── Email forms ────────────────────────────────────────────────────
  // Forms POST to the URL in `data-endpoint`. Set it to your Formspree
  // (or Web3Forms / your own) endpoint. If left blank or unchanged, the
  // form falls back to optimistic UI only (good for local previews).
  document.querySelectorAll('form.email-card').forEach(form => {
    form.addEventListener('submit', async (e) => {
      e.preventDefault();
      const input = form.querySelector('input[type=email]');
      const btn   = form.querySelector('button');
      const note  = form.parentElement.querySelector('.email-note');
      if (!input.value || !/^\S+@\S+\.\S+$/.test(input.value)) { input.focus(); return; }

      const endpoint = form.dataset.endpoint;
      const originalText = btn.textContent;
      btn.disabled = true;
      btn.textContent = 'Sending…';

      try {
        if (endpoint && !/YOUR_FORM_ID/i.test(endpoint)) {
          const res = await fetch(endpoint, {
            method: 'POST',
            headers: { 'Accept': 'application/json', 'Content-Type': 'application/json' },
            body: JSON.stringify({
              email: input.value,
              source: location.pathname,
              referrer: document.referrer || '(direct)',
            }),
          });
          if (!res.ok) throw new Error('http ' + res.status);
        }
        // Success state
        btn.textContent = "You're on the list";
        btn.classList.add('sent');
        input.value = '';
        input.disabled = true;
        if (note) { note.textContent = "Thanks. One email when invites open."; note.style.color = 'var(--fg-2)'; }
      } catch (err) {
        btn.textContent = originalText;
        btn.disabled = false;
        if (note) {
          note.textContent = "Couldn't send. Try again in a moment.";
          note.style.color = 'var(--c-reminder)';
        }
      }
    });
  });

  // ── Capture demo (typewriter + parse reveal) ───────────────────────
  // Multiple demo instances per page supported via data-demo attribute.
  const PARSE_PRESETS = {
    'gym tomorrow @7am !!': {
      type: 'REMINDER', railColor: 'var(--c-reminder)',
      meta: ['REMINDER', 'DUE TOMORROW · 7:00 AM', 'P2'],
      title: 'Gym',
    },
    '#UI new onboarding flow': {
      type: 'IDEA', railColor: 'var(--c-idea)',
      meta: ['IDEA', 'TAG · #UI'],
      title: 'New onboarding flow',
    },
    'finish pitch deck in 3 days': {
      type: 'TODO', railColor: 'var(--c-todo)',
      meta: ['TODO', 'DUE IN 3 DAYS · 9:00 AM'],
      title: 'Finish pitch deck',
    },
  };

  // ── INJECTED: token analyzer for the interactive simulator ─────────
  // Walks the raw text and wraps recognized keywords in inline token pills,
  // while collecting which status facets resolved (drives the status icons).
  const TOKEN_RX = new RegExp(
    [
      '(#[\\w-]+)',                                                   // 1 tag
      '(@\\d{1,2}(?::\\d{2})?\\s*(?:am|pm)?)',                        // 2 time
      '\\b(in\\s+\\d+\\s+days?)\\b',                                  // 3 relative date
      '\\b(today|tomorrow|tonight|next\\s+\\w+|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\\b', // 4 day
      '(!{1,3})',                                                    // 5 priority
    ].join('|'),
    'gi'
  );

  function escapeHtml(s) {
    return s.replace(/[&<>]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]));
  }

  // Returns { html, status:Set } for a given input string.
  function analyze(text) {
    const status = new Set(['type']);   // a type is always inferred
    const out = [];
    let last = 0, m;
    TOKEN_RX.lastIndex = 0;
    while ((m = TOKEN_RX.exec(text))) {
      out.push(escapeHtml(text.slice(last, m.index)));
      let kind;
      if (m[1])               { kind = 'tag';  status.add('tag'); }
      else if (m[2])          { kind = 'time'; status.add('time'); }
      else if (m[3] || m[4])  { kind = 'date'; status.add('date'); }
      else if (m[5])          { kind = 'prio'; status.add('priority'); }
      out.push(`<span class="tok tok-${kind}">${escapeHtml(m[0])}</span>`);
      last = m.index + m[0].length;
    }
    out.push(escapeHtml(text.slice(last)));
    return { html: out.join(''), status };
  }

  // Light the status icons for the resolved facets, staggered for a
  // "system thinking" feel. No-op on hosts that don't render the row.
  function lightStatus(host, status) {
    const icons = host.querySelectorAll('.capture-status .status-icon');
    if (!icons.length) return;
    const order = ['type', 'date', 'time', 'priority', 'tag'];
    let step = 0;
    order.forEach(key => {
      const icon = host.querySelector(`.capture-status .status-icon[data-status="${key}"]`);
      if (!icon) return;
      if (status.has(key)) {
        setTimeout(() => icon.classList.add('lit'), step * 90);
        step++;
      }
    });
  }

  function clearStatus(host) {
    host.querySelectorAll('.capture-status .status-icon.lit')
        .forEach(i => i.classList.remove('lit'));
  }

  // Heuristic parse for free-form input on capture.html
  function parseFreeForm(raw) {
    const text = raw.trim();
    if (!text) return null;
    const meta = []; let type, rail, title = text;

    if (/^#\w+/.test(text)) {
      type = 'IDEA'; rail = 'var(--c-idea)';
      const tag = text.match(/^#(\w+)/)[1];
      title = text.replace(/^#\w+\s*/, '') || '(untitled)';
      meta.push('IDEA', `TAG · #${tag}`);
    } else {
      const hasTime  = /@\d{1,2}(am|pm|:\d{2})?/i.test(text);
      const hasDay   = /\b(today|tomorrow|tonight|next\s+\w+|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b/i.test(text);
      const inN      = text.match(/\bin\s+(\d+)\s+days?\b/i);
      const bangs    = (text.match(/!+/) || [''])[0];
      const wordCnt  = text.split(/\s+/).length;
      if (hasTime || hasDay || inN) {
        // Reminder if time-bound and short, todo otherwise
        const due =
          inN ? `DUE IN ${inN[1]} DAYS` :
          /tomorrow/i.test(text) ? 'DUE TOMORROW' :
          /tonight/i.test(text)  ? 'DUE TONIGHT'  :
          /today/i.test(text)    ? 'DUE TODAY'    : 'DUE SCHEDULED';
        const tm = text.match(/@(\d{1,2})(am|pm)?/i);
        const timeStr = tm ? `${tm[1]}:00 ${tm[2] ? tm[2].toUpperCase() : ''}`.trim() : '';
        type = hasTime ? 'REMINDER' : 'TODO';
        rail = hasTime ? 'var(--c-reminder)' : 'var(--c-todo)';
        meta.push(type, timeStr ? `${due} · ${timeStr}` : due);
        if (bangs) meta.push(`P${4 - Math.min(bangs.length,3)}`);
        title = text
          .replace(/@\d{1,2}(am|pm|:\d{2})?/ig, '')
          .replace(/\b(today|tomorrow|tonight|next\s+\w+|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b/ig, '')
          .replace(/\bin\s+\d+\s+days?\b/ig, '')
          .replace(/!+/g, '')
          .replace(/\s+/g, ' ')
          .trim();
        title = title.charAt(0).toUpperCase() + title.slice(1);
      } else if (wordCnt > 4) {
        type = 'NOTE'; rail = 'var(--c-note)';
        meta.push('NOTE', `${wordCnt} WORDS`);
        title = text;
      } else {
        type = 'TODO'; rail = 'var(--c-todo)';
        meta.push('TODO', 'NO DATE');
        title = text.charAt(0).toUpperCase() + text.slice(1);
      }
    }
    return { type, railColor: rail, meta, title };
  }

  function renderParse(host, parsed) {
    const card  = host.querySelector('.parse-card');
    const rail  = host.querySelector('.parse-rail');
    const metaC = host.querySelector('.parse-meta');
    const titleEl = host.querySelector('.parse-title');
    if (!card || !parsed) return;

    rail.style.background = parsed.railColor;
    metaC.innerHTML = parsed.meta.map((m, i) => {
      const sep = i ? '<span class="dot">·</span>' : '';
      return sep + `<span>${m}</span>`;
    }).join('');
    titleEl.textContent = parsed.title;
    // Card sits in DOM with opacity:0 by default; just flip .show.
    // double rAF so the transition fires from a stable prior frame.
    requestAnimationFrame(() => requestAnimationFrame(() => card.classList.add('show')));
  }

  function clearParse(host) {
    const card = host.querySelector('.parse-card');
    if (card) card.classList.remove('show');
    clearStatus(host);                          // INJECTED — reset status icons too
  }

  // Types plain text char-by-char (caret reads cleanly during typing).
  function typewriteInto(typedEl, text, perChar = 70) {
    return new Promise(resolve => {
      typedEl.textContent = '';
      let i = 0;
      const step = () => {
        if (i > text.length) return resolve();
        typedEl.textContent = text.slice(0, i);
        i++;
        setTimeout(step, perChar);
      };
      step();
    });
  }

  function bindDemo(host) {
    const typedEl  = host.querySelector('.capture-bar .typed');
    const phEl     = host.querySelector('.capture-bar .placeholder');
    const buttons  = [...host.querySelectorAll('.demo-buttons .btn-pill[data-text]')];
    const inputEl  = host.querySelector('input.free');
    const presets  = buttons.map(b => b.getAttribute('data-text'));
    const autoplay = host.hasAttribute('data-autoplay') && !inputEl && presets.length > 0;

    let busy = false, token = 0;
    let autoIdx = 0, autoTimer = null, visible = false, paused = false;

    function setActiveBtn(text) {
      buttons.forEach(b => b.classList.toggle('active', b.getAttribute('data-text') === text));
    }

    // Full sequence: type → highlight tokens inline → light icons → reveal card.
    async function run(text, freeform = false) {
      token++;
      const myToken = token;
      busy = true;
      clearParse(host);
      setActiveBtn(text);
      host.setAttribute('data-active', '');
      if (phEl) phEl.style.display = 'none';

      await typewriteInto(typedEl, text, 70);
      if (myToken !== token) { busy = false; return; }

      // Swap the plain text for highlighted inline token pills.
      const { html, status } = analyze(text);
      typedEl.innerHTML = html;

      await new Promise(r => setTimeout(r, 280));
      if (myToken !== token) { busy = false; return; }

      const parsed = freeform ? parseFreeForm(text) : (PARSE_PRESETS[text] || parseFreeForm(text));
      renderParse(host, parsed);
      lightStatus(host, status);
      busy = false;
    }

    // Manual toggle via preset pills — also reseats the autoplay cursor.
    buttons.forEach(btn => {
      btn.addEventListener('click', () => {
        const text = btn.getAttribute('data-text');
        paused = false;
        autoIdx = Math.max(0, presets.indexOf(text));
        clearTimeout(autoTimer);
        run(text, false).then(() => { if (autoplay) scheduleNext(); });
      });
    });

    // ── Autoplay loop (index.html) ──────────────────────────────────
    function scheduleNext() {
      clearTimeout(autoTimer);
      autoTimer = setTimeout(async () => {
        if (!visible || paused || document.hidden || busy) { scheduleNext(); return; }
        autoIdx = (autoIdx + 1) % presets.length;
        await run(presets[autoIdx], false);
        scheduleNext();
      }, 3400);
    }

    if (autoplay) {
      // Pause while the user is reading / hovering the box.
      host.addEventListener('mouseenter', () => { paused = true; });
      host.addEventListener('mouseleave', () => { paused = false; });

      const io = new IntersectionObserver(entries => {
        entries.forEach(e => {
          visible = e.isIntersecting;
          if (visible && !busy && !typedEl.textContent) {
            run(presets[autoIdx], false).then(scheduleNext);
          }
        });
      }, { threshold: 0.4 });
      io.observe(host);
    }

    // ── Free-form input (capture.html) ──────────────────────────────
    if (inputEl) {
      let t;
      inputEl.addEventListener('input', () => {
        clearTimeout(t);
        const v = inputEl.value;
        if (phEl) phEl.style.display = v ? 'none' : '';
        const { html, status } = analyze(v);   // INJECTED — live token pills + icons
        typedEl.innerHTML = html;
        clearParse(host);
        t = setTimeout(() => {
          const parsed = parseFreeForm(v);
          if (parsed) { renderParse(host, parsed); lightStatus(host, status); }
        }, 380);
      });
    }
  }

  document.querySelectorAll('[data-demo]').forEach(bindDemo);

  // ── Theme switcher (themes.html) ───────────────────────────────────
  const sw = document.querySelector('[data-theme-switcher]');
  if (sw) {
    const screen = sw.querySelector('.phone-screen');
    const pills  = sw.querySelectorAll('[data-theme]');
    const sec    = sw.closest('section') || document.body;
    const bgMap = {
      dark:  '#0A0A0C',
      light: '#F9F9F9',
      earth: '#F4EDDE',
      glass: 'linear-gradient(135deg,#9480DC 0%,#738CCC 50%,#4D94BD 100%)',
    };
    function switchTo(name) {
      screen.classList.add('fading');
      setTimeout(() => {
        screen.classList.remove('t-dark','t-light','t-earth','t-glass');
        screen.classList.add('t-' + name);
        screen.classList.remove('fading');
      }, 300);
      pills.forEach(p => p.classList.toggle('active', p.dataset.theme === name));
      // Subtle section bg shift
      sec.style.transition = 'background 600ms ease';
      if (name === 'light') sec.style.background = 'rgba(249,249,249,0.04)';
      else if (name === 'earth') sec.style.background = 'rgba(244,237,222,0.04)';
      else if (name === 'glass') sec.style.background = 'rgba(148,128,220,0.06)';
      else sec.style.background = '';
    }
    pills.forEach(p => p.addEventListener('click', () => switchTo(p.dataset.theme)));
  }

})();
