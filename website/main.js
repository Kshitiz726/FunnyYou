/* Funny You - marketing site behaviour.
   No framework, no build step. Everything degrades to a readable page
   if this file never loads. */

(() => {
  'use strict';

  /* The scenarios, mirroring assets/video_templates/. Kept here rather than
     fetched so the grid works from a file:// preview too. */
  const SCENARIOS = [
    ['gym',     'Gym Legend'],
    ['nurse',   'The Great Escape'],
    ['karaoke', 'Karaoke Night'],
    ['skating', 'Skate Park'],
    ['hello',   'Hello?!'],
  ];

  const VISIBLE = SCENARIOS.length;          // they all fit; nothing to expand
  const img = id => `/img/scenarios/${id}.jpg`;

  /* ── scenario grid ────────────────────────────────────── */

  const grid = document.getElementById('grid');
  if (grid) {
    grid.innerHTML = SCENARIOS.map(([id, name], i) => `
      <figure class="tile${i >= VISIBLE ? ' hidden' : ''}">
        <img src="${img(id)}" alt="${name}" loading="lazy" decoding="async">
        <figcaption>${name}</figcaption>
      </figure>`).join('');

    const button = document.getElementById('showAll');
    let open = false;
    button?.addEventListener('click', () => {
      open = !open;
      grid.querySelectorAll('.tile').forEach((tile, i) => {
        tile.classList.toggle('hidden', !open && i >= VISIBLE);
      });
      button.textContent = open ? 'Show fewer' : 'Show all 40 scenarios';
      if (!open) grid.scrollIntoView({ block: 'start' });
    });
  }

  /* ── marquees ─────────────────────────────────────────── */

  /* Duplicated once so the -50% keyframe lands on a seamless loop. */
  const strip = list => list.concat(list)
    .map(([id, name]) => `<img src="${img(id)}" alt="${name}" loading="lazy" decoding="async">`)
    .join('');

  const a = document.getElementById('track-a');
  const b = document.getElementById('track-b');
  if (a) a.innerHTML = strip(SCENARIOS);
  if (b) b.innerHTML = strip([...SCENARIOS].reverse());

  /* ── sticky nav ───────────────────────────────────────── */

  const nav = document.getElementById('nav');
  const onScroll = () => nav?.classList.toggle('stuck', window.scrollY > 24);
  onScroll();
  addEventListener('scroll', onScroll, { passive: true });

  /* ── mobile menu ──────────────────────────────────────── */

  const burger = document.getElementById('burger');
  const menu = document.getElementById('mobile-menu');
  const setMenu = open => {
    if (!burger || !menu) return;
    burger.setAttribute('aria-expanded', String(open));
    menu.hidden = !open;
  };
  burger?.addEventListener('click', () => {
    setMenu(burger.getAttribute('aria-expanded') !== 'true');
  });
  menu?.addEventListener('click', e => {
    if (e.target.tagName === 'A') setMenu(false);
  });
  addEventListener('keydown', e => { if (e.key === 'Escape') setMenu(false); });

  /* ── reveal on scroll ─────────────────────────────────── */

  const targets = document.querySelectorAll('.reveal');
  if (!('IntersectionObserver' in window)) {
    // No observer means no animation, not an invisible page.
    targets.forEach(el => el.classList.add('in'));
  } else {
    const io = new IntersectionObserver(entries => {
      entries.forEach(entry => {
        if (!entry.isIntersecting) return;
        entry.target.classList.add('in');
        io.unobserve(entry.target);
      });
    }, { threshold: 0.12, rootMargin: '0px 0px -60px' });
    targets.forEach(el => io.observe(el));
  }

  /* ── footer year ──────────────────────────────────────── */

  const yr = document.getElementById('yr');
  if (yr) yr.textContent = String(new Date().getFullYear());
})();
