/* Tokyo Rice Prices dashboard. Reads data.json (written by R/30_export_dashboard.R). */
(() => {
  "use strict";
  const $ = (s) => document.querySelector(s);
  const parseYM = (s) => new Date(Date.UTC(+s.slice(0, 4), +s.slice(5, 7) - 1, 1));
  const fmtYM = d3.utcFormat("%b %Y");
  const yen = (v) => "¥" + d3.format(",")(Math.round(v));
  const pct = (v, d = 1) => (v > 0 ? "+" : v < 0 ? "−" : "") + Math.abs(v).toFixed(d) + "%";
  const tok = (name) => getComputedStyle(document.documentElement).getPropertyValue(name).trim();
  const state = { range: "all", tax: "incl", ccf: "pre" };
  let D = null;

  // ---------- theme ----------
  const themeBtn = $("#theme");
  try { const t = localStorage.getItem("rice-theme"); if (t) document.documentElement.dataset.theme = t; } catch (e) { /* storage blocked */ }
  themeBtn.addEventListener("click", () => {
    const dark = document.documentElement.dataset.theme
      ? document.documentElement.dataset.theme === "dark"
      : matchMedia("(prefers-color-scheme: dark)").matches;
    const next = dark ? "light" : "dark";
    document.documentElement.dataset.theme = next;
    try { localStorage.setItem("rice-theme", next); } catch (e) { /* ignore */ }
    renderAll();
  });
  matchMedia("(prefers-color-scheme: dark)").addEventListener("change", () => renderAll());

  // ---------- tooltip ----------
  const tip = $("#tip");
  function showTip(evt, html) {
    tip.innerHTML = html; tip.hidden = false;
    const pad = 14, w = tip.offsetWidth, h = tip.offsetHeight;
    let x = evt.clientX + pad, y = evt.clientY + pad;
    if (x + w > innerWidth - 8) x = evt.clientX - w - pad;
    if (y + h > innerHeight - 8) y = evt.clientY - h - pad;
    tip.style.left = Math.max(8, x) + "px"; tip.style.top = Math.max(8, y) + "px";
  }
  const hideTip = () => { tip.hidden = true; };

  // ---------- shared plot options ----------
  function base(el, height) {
    const w = el.clientWidth || 600;
    return {
      width: w, height: height ?? Math.max(220, Math.min(340, w * 0.45)),
      marginLeft: 52, marginRight: 16, marginTop: 20, marginBottom: 30,
      style: { background: "transparent", color: tok("--muted"), fontSize: "11px", overflow: "visible" },
    };
  }
  const gridY = () => Plot.gridY({ stroke: tok("--grid"), strokeOpacity: 1 });

  /* Time-series chart with crosshair + multi-row tooltip.
     series: [{key, label, color, fmt}]; rows: data with .d (Date) */
  function timeChart(el, { rows, series, y = {}, marks = [], height, tipExtra }) {
    const opts = base(el, height);
    const plot = Plot.plot({
      ...opts,
      x: { type: "utc", label: null,
           ticks: (rows[rows.length - 1].d - rows[0].d) < 5 * 365.25 * 864e5 ? d3.utcMonth.every(6) : Math.max(3, Math.floor(opts.width / 110)) },
      y: { label: null, grid: false, ticks: 5, ...y },
      marks: [
        gridY(),
        ...marks,
        ...series.map((s) => Plot.lineY(rows, { x: "d", y: s.key, stroke: s.color, strokeWidth: 2, curve: "linear" })),
      ],
    });
    el.replaceChildren(plot);
    attachHover(el, plot, rows, series, tipExtra);
    return plot;
  }

  function attachHover(el, plot, rows, series, tipExtra) {
    const svg = plot.tagName === "svg" ? plot : plot.querySelector("svg");
    const xs = plot.scale("x"), ys = plot.scale("y");
    const ns = "http://www.w3.org/2000/svg";
    const g = document.createElementNS(ns, "g"); g.style.display = "none"; g.style.pointerEvents = "none";
    const rule = document.createElementNS(ns, "line");
    rule.setAttribute("stroke", tok("--muted")); rule.setAttribute("stroke-width", "1"); rule.setAttribute("stroke-dasharray", "3,3");
    g.appendChild(rule);
    const dots = series.map((s) => {
      const c = document.createElementNS(ns, "circle");
      c.setAttribute("r", "4.5"); c.setAttribute("fill", s.color); c.setAttribute("stroke", tok("--surface")); c.setAttribute("stroke-width", "2");
      g.appendChild(c); return c;
    });
    svg.appendChild(g);
    const [y0, y1] = ys.range;
    const dates = rows.map((r) => +r.d);
    const move = (evt) => {
      const box = svg.getBoundingClientRect();
      const px = (evt.clientX - box.left) * (svg.viewBox.baseVal?.width ? svg.viewBox.baseVal.width / box.width : 1);
      const t = +xs.invert(px);
      let i = d3.bisectCenter(dates, t); i = Math.max(0, Math.min(rows.length - 1, i));
      const r = rows[i], x = xs.apply(r.d);
      if (x < xs.range[0] - 2 || x > xs.range[1] + 2) return leave();
      rule.setAttribute("x1", x); rule.setAttribute("x2", x); rule.setAttribute("y1", Math.min(y0, y1)); rule.setAttribute("y2", Math.max(y0, y1));
      series.forEach((s, k) => {
        const v = r[s.key];
        if (v == null || isNaN(v)) { dots[k].style.display = "none"; return; }
        dots[k].style.display = ""; dots[k].setAttribute("cx", x); dots[k].setAttribute("cy", ys.apply(v));
      });
      g.style.display = "";
      const lines = series.filter((s) => r[s.key] != null)
        .map((s) => `<div><i style="background:${s.color}"></i>${s.label}: <b>${s.fmt(r[s.key])}</b></div>`).join("");
      showTip(evt, `<div class="t">${fmtYM(r.d)}</div>${lines}${tipExtra ? tipExtra(r) : ""}`);
    };
    const leave = () => { g.style.display = "none"; hideTip(); };
    svg.addEventListener("pointermove", move);
    svg.addEventListener("pointerleave", leave);
    svg.style.touchAction = "pan-y";
  }

  // Plot's built-in pointer tip, themed
  const tipMark = (data, opts) => Plot.tip(data, Plot.pointerX({ ...opts, fill: tok("--surface"), stroke: tok("--border"), textPadding: 8 }));

  // ---------- table view ----------
  const tables = {};
  function tableHTML(cols, rows) {
    return `<table><thead><tr>${cols.map((c) => `<th scope="col">${c.label}</th>`).join("")}</tr></thead><tbody>${
      rows.map((r) => `<tr>${cols.map((c) => `<td>${c.fmt ? c.fmt(r[c.key], r) : r[c.key] ?? "–"}</td>`).join("")}</tr>`).join("")}</tbody></table>`;
  }
  document.addEventListener("click", (e) => {
    const b = e.target.closest(".tbl-toggle"); if (!b) return;
    const box = document.getElementById("t-" + b.dataset.for);
    const open = box.hidden;
    if (open) box.innerHTML = tables[b.dataset.for] ? tables[b.dataset.for]() : "";
    box.hidden = !open; b.textContent = open ? "Hide table" : "View as table";
  });

  // ---------- controls ----------
  function wireSeg(attr, key) {
    document.querySelectorAll(`[data-${attr}]`).forEach((btn) => btn.addEventListener("click", () => {
      state[key] = btn.dataset[attr];
      document.querySelectorAll(`[data-${attr}]`).forEach((b) => b.setAttribute("aria-pressed", String(b === btn)));
      renderAll();
    }));
  }
  wireSeg("range", "range"); wireSeg("tax", "tax"); wireSeg("ccf", "ccf");

  // ---------- static content ----------
  function renderStatic() {
    const m = D.meta, t = D.tiles;
    $("#meta").textContent = `Data through ${fmtYM(parseYM(m.as_of))} · built ${m.built}`;
    const w = t.wholesale, warn = (w.prelim || w.thin)
      ? `<br><span style="color:var(--warning-ink)"><span aria-hidden="true">⚠</span> <b style="color:var(--warning-ink)">Caution:</b> preliminary, thin volume (${d3.format(",")(w.volume_t)} t)</span>` : "";
    $("#tiles").innerHTML = `
      <div class="tile"><div class="k">Retail, 5 kg Koshihikari (Tokyo)</div>
        <div class="v">${yen(t.retail.value)}</div>
        <div class="n"><b>${pct(t.retail.yoy_pct)}</b> year on year · <b>${pct(t.retail.from_peak_pct)}</b> from the ${fmtYM(parseYM(t.retail.peak_date))} peak (${yen(t.retail.peak)})</div></div>
      <div class="tile"><div class="k">Wholesale, new ${t.weather.crop_year} crop</div>
        <div class="v">${yen(w.value)} <small>/ 60 kg</small></div>
        <div class="n"><b>${pct(w.mom_pct)}</b> vs previous month${warn}</div></div>
      <div class="tile"><div class="k">Retail mark-up over wholesale</div>
        <div class="v">${t.markup.value.toFixed(2)}×</div>
        <div class="n">Pre-2024 average <b>${t.markup.pre_mean.toFixed(2)}×</b> (range ${t.markup.pre_min.toFixed(2)}–${t.markup.pre_max.toFixed(2)}). Above average → room for retail to fall</div></div>
      <div class="tile"><div class="k">Summer ${t.weather.crop_year}, Niigata</div>
        <div class="v">${t.weather.aug_anom > 0 ? "+" : ""}${t.weather.aug_anom.toFixed(1)} °C <small>· ${t.weather.jja_pct}% rain</small></div>
        <div class="n">August temperature vs normal · June–August rain vs normal</div></div>`;

    $("#events").innerHTML = D.events.map((e, i) =>
      `<li><span class="dot">${i + 1}</span><span><b>${fmtYM(parseYM(e.date))} · ${e.label}.</b> ${e.detail}${
        e.source.startsWith("http") ? ` <a href="${e.source}" target="_blank" rel="noopener">Source</a>` : ` (${e.source})`}</span></li>`).join("");

    $("#markup-sub").textContent = `Retail ¥/kg ÷ wholesale ¥/kg milled. Dotted: pre-2024 average (${t.markup.pre_mean.toFixed(2)}×).`;

    const icons = { warning: ["⚠", "Caution"], info: ["ℹ", "Note"] };
    $("#flags").innerHTML = D.flags.map((f) =>
      `<li class="${f.level}"><span class="ico" aria-hidden="true">${icons[f.level][0]}</span><span><span class="lbl">${icons[f.level][1]}:</span> ${f.text}</span></li>`).join("");

    $("#sources").innerHTML = tableHTML(
      [{ key: "series", label: "Series" }, { key: "source", label: "Source", fmt: (v, r) => `<a href="${r.url}" target="_blank" rel="noopener">${v}</a>` }],
      D.sources);
    $("#foot").innerHTML = `Built ${D.meta.built} from public data (e-Stat, MAFF, Bank of Japan, JMA, JNTO). Percent changes are simple % changes. ` +
      `Mark-up definition: ${D.meta.markup_def}.`;
  }

  // ---------- charts ----------
  function renderAll() {
    if (!D) return;
    hideTip();
    const C = { blue: tok("--blue"), orange: tok("--orange"), aqua: tok("--aqua"), ink: tok("--ink"), ink2: tok("--ink-2"),
                muted: tok("--muted"), shade: tok("--shade"), page: tok("--page"), surface: tok("--surface") };
    const rows = D.monthly.map((r) => ({ ...r, d: parseYM(r.date) }));
    const lastD = rows[rows.length - 1].d, breakD = parseYM(D.meta.break_date);

    // 1. price story
    {
      const key = state.tax === "incl" ? "y" : "y_ex";
      const rr = state.range === "all" ? rows : rows.filter((r) => r.d >= Date.UTC(2023, 0, 1));
      const ev = D.events.map((e, i) => { const r = rows.find((x) => x.date === e.date); return { ...e, n: i + 1, d: r.d, v: r[key] }; })
        .filter((e) => e.d >= rr[0].d);
      const label = state.tax === "incl" ? "Retail (with tax)" : "Retail (without tax)";
      timeChart($("#c-price"), {
        rows: rr, series: [{ key, label, color: C.blue, fmt: yen }],
        y: { domain: [0, d3.max(rows, (r) => r.y) * 1.08], tickFormat: (v) => "¥" + d3.format(",")(v) },
        marks: [
          Plot.rect([{ x1: breakD, x2: lastD }], { x1: "x1", x2: "x2", fill: C.shade }),
          Plot.ruleY([0], { stroke: C.muted }),
          Plot.dot(ev, { x: "d", y: "v", r: 8, fill: C.ink, stroke: C.surface, strokeWidth: 2, dy: -14 }),
          Plot.text(ev, { x: "d", y: "v", text: "n", fill: C.page, fontWeight: 700, fontSize: 10, dy: -14 }),
        ],
        tipExtra: (r) => r.shortage ? `<div class="t">Shortage period</div>` : "",
      });
      tables["c-price"] = () => tableHTML(
        [{ key: "date", label: "Month" }, { key: "y", label: "With tax (¥)", fmt: d3.format(",") },
         { key: "y_ex", label: "Without tax (¥)", fmt: (v) => d3.format(",")(Math.round(v)) }, { key: "yoy_y", label: "YoY %", fmt: (v) => v == null ? "–" : pct(v) }],
        rr.slice().reverse());
    }

    // 2a. retail vs wholesale in the same unit: ¥ per kg of milled rice, without tax
    {
      const kg = (v) => yen(v) + "/kg";
      const series = [{ key: "retail_kg", label: "Retail", color: C.blue, fmt: kg },
                      { key: "wholesale_kg", label: "Wholesale", color: C.orange, fmt: kg }];
      $("#lg-idx").innerHTML = series.map((s) => `<span><i style="background:${s.color}"></i>${s.label}</span>`).join("");
      timeChart($("#c-index"), {
        rows, series,
        y: { domain: [0, d3.max(rows, (r) => r.retail_kg) * 1.08], tickFormat: (v) => "¥" + d3.format(",")(v) },
        marks: [Plot.rect([{ x1: breakD, x2: lastD }], { x1: "x1", x2: "x2", fill: C.shade }),
                Plot.ruleY([0], { stroke: C.muted })],
        tipExtra: (r) => `<div class="t">Retail is ${(r.retail_kg / r.wholesale_kg).toFixed(2)}× wholesale</div>`,
      });
      tables["c-index"] = () => tableHTML(
        [{ key: "date", label: "Month" }, { key: "retail_kg", label: "Retail ¥/kg", fmt: (v) => Math.round(v) },
         { key: "wholesale_kg", label: "Wholesale ¥/kg", fmt: (v) => Math.round(v) },
         { key: "x1", label: "Wholesale ¥/60 kg brown (as published, with tax)", fmt: d3.format(",") }], rows.slice().reverse());
    }

    // 2b. mark-up
    {
      const mean = D.tiles.markup.pre_mean;
      const el = $("#c-markup");
      timeChart(el, {
        rows, series: [{ key: "markup", label: "Mark-up", color: C.aqua, fmt: (v) => v.toFixed(2) + "×" }],
        y: { tickFormat: (v) => v.toFixed(1) + "×" }, height: 240,
        marks: [Plot.rect([{ x1: breakD, x2: lastD }], { x1: "x1", x2: "x2", fill: C.shade }),
                Plot.ruleY([mean], { stroke: C.muted, strokeDasharray: "3,3" })],
      });
      tables["c-markup"] = () => tableHTML([{ key: "date", label: "Month" }, { key: "markup", label: "Mark-up (×)", fmt: (v) => v.toFixed(2) }], rows.slice().reverse());
    }

    // 2c. cross-correlation
    {
      const cc = D.ccf.filter((r) => r.period === state.ccf), band = cc[0].band;
      const el = $("#c-ccf"), opts = base(el, 240);
      const best = cc.filter((r) => r.lag > 0).reduce((a, b) => (b.r > a.r ? b : a));
      el.replaceChildren(Plot.plot({
        ...opts,
        x: { label: null, ticks: d3.range(-6, 7, 2), domain: [-6.5, 6.5] }, y: { label: null, domain: [-0.3, 0.6] },
        marks: [
          gridY(),
          Plot.ruleY([0], { stroke: C.muted }),
          Plot.ruleY([band, -band], { stroke: C.muted, strokeDasharray: "3,3" }),
          Plot.ruleX(cc, { x: "lag", y1: 0, y2: "r", stroke: C.blue, strokeWidth: 2 }),
          Plot.dot(cc, { x: "lag", y: "r", r: 4.5, fill: C.blue, stroke: C.surface, strokeWidth: 2 }),
          tipMark(cc, { x: "lag", y: "r", title: (d) => `Lag ${d.lag}: r = ${d.r.toFixed(2)}${Math.abs(d.r) > band ? " (significant)" : ""}` }),
        ],
      }));
      $("#ccf-take").innerHTML = `Strongest lead: <b>wholesale ${best.lag} month${best.lag > 1 ? "s" : ""} earlier</b>, r = ${best.r.toFixed(2)} (band ±${band.toFixed(2)}).`;
      tables["c-ccf"] = () => tableHTML([{ key: "lag", label: "Lag (months)" }, { key: "r", label: "Correlation", fmt: (v) => v.toFixed(3) },
        { key: "band", label: "±Band", fmt: (v) => v.toFixed(3) }], cc);
    }

    // 3a/3b. weather by crop year
    const cy = D.crop_years;
    tables["c-temp"] = () => tableHTML([{ key: "year", label: "Crop year" }, { key: "aug_temp", label: "August °C" },
      { key: "aug_anom", label: "vs normal", fmt: (v) => (v > 0 ? "+" : "") + v.toFixed(1) }], cy);
    const cyR = cy.map((r) => ({ ...r, dev: r.jja_pct - 100 }));
    {
      const el = $("#c-rain"), opts = base(el, 240), hi = cyR.filter((r) => r.year === 2023);
      el.replaceChildren(Plot.plot({
        ...opts, marginLeft: 44,
        x: { type: "band", label: null, padding: 0.25, tickFormat: (y) => (opts.width > 560 || y % 4 === 2 ? "’" + String(y).slice(-2) : "") },
        y: { label: null, tickFormat: (v) => v + 100 + "%" },
        marks: [
          gridY(),
          Plot.barY(cyR, { x: "year", y: "dev", fill: (d) => (d.dev < 0 ? C.orange : C.blue), rx: 2, insetLeft: 1, insetRight: 1 }),
          Plot.ruleY([0], { stroke: C.muted }),
          Plot.text(hi, { x: "year", y: "dev", text: () => `Aug 2023: ${D.meta.aug23_rain_mm} mm`, dy: 12, fill: C.ink, fontWeight: 600 }),
          tipMark(cyR, { x: "year", y: "dev", title: (d) => `Crop year ${d.year}\nJun–Aug ${d.jja_mm} mm (${Math.round(d.jja_pct)}% of normal)` }),
        ],
      }));
      tables["c-rain"] = () => tableHTML([{ key: "year", label: "Crop year" }, { key: "jja_mm", label: "Jun–Aug mm" },
        { key: "jja_pct", label: "% of normal", fmt: (v) => Math.round(v) + "%" }], cyR);
    }
    // August temperature anomaly
    {
      const el = $("#c-temp"), opts = base(el, 240), hi = cy.filter((r) => r.year === 2023);
      el.replaceChildren(Plot.plot({
        ...opts, marginLeft: 44,
        x: { type: "band", label: null, padding: 0.25, tickFormat: (y) => (opts.width > 560 || y % 4 === 2 ? "’" + String(y).slice(-2) : "") },
        y: { label: null, tickFormat: (v) => (v > 0 ? "+" : "") + v + "°" },
        marks: [
          gridY(),
          Plot.barY(cy, { x: "year", y: "aug_anom", fill: (d) => (d.aug_anom >= 0 ? C.orange : C.blue), rx: 2, insetLeft: 1, insetRight: 1 }),
          Plot.ruleY([0], { stroke: C.muted }),
          Plot.text(hi, { x: "year", y: "aug_anom", text: () => "2023: record heat", dy: -10, fill: C.ink, fontWeight: 600 }),
          tipMark(cy, { x: "year", y: "aug_anom", title: (d) => `Crop year ${d.year}\nAugust ${d.aug_temp.toFixed(1)} °C (${d.aug_anom > 0 ? "+" : ""}${d.aug_anom.toFixed(1)} °C vs normal)` }),
        ],
      }));
    }

    // 3c. not the weak yen
    {
      const series = [{ key: "yoy_y", label: "Retail rice", color: C.blue, fmt: (v) => pct(v) },
                      { key: "yoy_x2", label: "Import prices (yen)", color: C.aqua, fmt: (v) => pct(v) }];
      $("#lg-yoy").innerHTML = series.map((s) => `<span><i style="background:${s.color}"></i>${s.label}</span>`).join("");
      timeChart($("#c-yoy"), {
        rows, series, y: { tickFormat: (v) => (v > 0 ? "+" : "") + v + "%" },
        marks: [Plot.ruleY([0], { stroke: C.muted }), Plot.rect([{ x1: breakD, x2: lastD }], { x1: "x1", x2: "x2", fill: C.shade })],
      });
      tables["c-yoy"] = () => tableHTML([{ key: "date", label: "Month" }, { key: "yoy_y", label: "Retail YoY", fmt: (v) => v == null ? "–" : pct(v) },
        { key: "yoy_x2", label: "Import prices YoY", fmt: (v) => v == null ? "–" : pct(v) }], rows.slice().reverse());
    }

    // 3d. visitors (only when the panel is open, so width is known)
    const det = $("#c-visitors").closest("details");
    if (det.open) timeChart($("#c-visitors"), {
      rows: rows.map((r) => ({ ...r, xm: r.x4 / 1e6 })), series: [{ key: "xm", label: "Visitors", color: C.ink2, fmt: (v) => v.toFixed(2) + " m" }],
      y: { domain: [0, null], tickFormat: (v) => v + "m" }, height: 220,
    });

    // 5. coverage
    {
      const el = $("#c-coverage"), opts = base(el, 230);
      const spans = D.coverage.flatMap((c) => c.spans.map(([a, b]) => ({ series: c.series, a: parseYM(a), b: parseYM(b), months: c.months })));
      el.replaceChildren(Plot.plot({
        ...opts, marginLeft: Math.min(150, opts.width * 0.36),
        x: { type: "utc", label: null, ticks: Math.max(3, Math.floor(opts.width / 120)) },
        y: { label: null, domain: D.coverage.map((c) => c.series) },
        marks: [
          Plot.barX(spans, { x1: "a", x2: "b", y: "series", fill: C.blue, insetTop: 6, insetBottom: 6, rx: 2 }),
          Plot.ruleX([parseYM(D.meta.window_start)], { stroke: C.ink, strokeDasharray: "4,3" }),
          Plot.tip(spans, Plot.pointer({ x: (d) => new Date((+d.a + +d.b) / 2), y: "series",
            title: (d) => `${d.series}\n${fmtYM(d.a)} – ${fmtYM(d.b)}`, fill: C.surface, stroke: tok("--border") })),
        ],
      }));
    }
  }
  $("#c-visitors").closest("details").addEventListener("toggle", renderAll);

  // ---------- resize ----------
  let lastW = 0, timer;
  new ResizeObserver((entries) => {
    const w = Math.round(entries[0].contentRect.width);
    if (w === lastW) return; lastW = w;
    clearTimeout(timer); timer = setTimeout(renderAll, 120);
  }).observe(document.querySelector("main"));

  // ---------- boot ----------
  fetch("data.json", { cache: "no-cache" })
    .then((r) => { if (!r.ok) throw new Error(r.status); return r.json(); })
    .then((json) => { D = json; renderStatic(); renderAll(); })
    .catch((err) => { $("#meta").textContent = "Could not load data.json (" + err.message + "). Serve this folder over HTTP."; console.error(err); });
})();
