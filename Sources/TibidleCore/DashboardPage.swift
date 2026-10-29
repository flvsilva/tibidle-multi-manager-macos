/// The dashboard served at `/`. Self-contained (no CDN), so it also works without internet.
/// Every game value is written with `textContent`, never as HTML.
public enum DashboardPage {
    public static let html = #"""
    <!doctype html>
    <html lang="pt-BR">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Tibidle Hunts</title>
    <style>
    :root {
      color-scheme: light;
      --page: #f6f5f1; --surface: #fcfcfb; --surface-2: #f0efea; --border: rgba(11,11,11,.10);
      --ink: #0b0b0b; --ink-2: #52514e; --muted: #77756f; --grid: #e1e0d9; --axis: #c3c2b7;
      --accent: #8a6a1f; --accent-bg: #f3e7c6;
      --s0: #2a78d6; --s1: #eb6834; --s2: #1baf7a; --s3: #eda100;
      --good: #0ca30c; --good-text: #006300; --warning: #b77800; --warn-text: #8a5a00; --critical: #d03b3b; --bad-text: #b02a2a;
    }
    @media (prefers-color-scheme: dark) {
      :root:not([data-theme="light"]) {
        color-scheme: dark;
        --page: #0f1116; --surface: #161a21; --surface-2: #1d222b; --border: rgba(255,255,255,.09);
        --ink: #eef0f4; --ink-2: #b9bfcb; --muted: #858d9b; --grid: #262b34; --axis: #343a45;
        --accent: #e8d39c; --accent-bg: #413620;
        --s0: #3987e5; --s1: #d95926; --s2: #199e70; --s3: #c98500;
        --good: #0ca30c; --good-text: #3ccf3c; --warning: #fab219; --warn-text: #fab219; --critical: #e66767; --bad-text: #ff8a8a;
      }
    }
    :root[data-theme="dark"] {
      color-scheme: dark;
      --page: #0f1116; --surface: #161a21; --surface-2: #1d222b; --border: rgba(255,255,255,.09);
      --ink: #eef0f4; --ink-2: #b9bfcb; --muted: #858d9b; --grid: #262b34; --axis: #343a45;
      --accent: #e8d39c; --accent-bg: #413620;
      --s0: #3987e5; --s1: #d95926; --s2: #199e70; --s3: #c98500;
      --good: #0ca30c; --good-text: #3ccf3c; --warning: #fab219; --warn-text: #fab219; --critical: #e66767; --bad-text: #ff8a8a;
    }
    * { box-sizing: border-box; }
    body { margin: 0; background: var(--page); color: var(--ink); font: 14px/1.45 system-ui, -apple-system, "Segoe UI", sans-serif; }
    main { max-width: 1280px; margin: 0 auto; padding: 20px 16px 48px; }
    header { display: flex; flex-wrap: wrap; align-items: baseline; gap: 8px 16px; margin-bottom: 18px; }
    h1 { font-size: 20px; margin: 0; letter-spacing: -.01em; }
    h1 span { color: var(--accent); }
    h2 { font-size: 15px; margin: 0 0 10px; }
    .meta { color: var(--muted); font-size: 12px; margin-left: auto; }
    .theme { background: none; border: 1px solid var(--border); color: var(--ink-2); border-radius: 6px; padding: 3px 9px; font: inherit; font-size: 12px; cursor: pointer; }

    .cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(280px, 100%), 1fr)); gap: 12px; margin-bottom: 22px; }
    .card { background: var(--surface); border: 1px solid var(--border); border-radius: 10px; padding: 14px; min-width: 0; }
    .card-top { display: flex; align-items: center; gap: 8px; margin-bottom: 4px; }
    .swatch { width: 10px; height: 10px; border-radius: 3px; flex: none; }
    .label { font-weight: 600; font-size: 15px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .status { margin-left: auto; font-size: 12px; display: inline-flex; align-items: center; gap: 5px; color: var(--ink-2); white-space: nowrap; }
    .status i { width: 8px; height: 8px; border-radius: 50%; display: inline-block; }
    .sub { color: var(--muted); font-size: 12px; margin-bottom: 10px; min-height: 18px; overflow-wrap: anywhere; }
    .hero { display: flex; gap: 18px; margin: 4px 0 12px; }
    .hero div { min-width: 0; }
    .hero b { display: block; font-size: 24px; line-height: 1.15; font-weight: 650; letter-spacing: -.01em; }
    .hero small, .stats small { color: var(--muted); font-size: 11px; text-transform: uppercase; letter-spacing: .04em; }
    .stats { display: grid; grid-template-columns: repeat(3, 1fr); gap: 8px 10px; padding-top: 10px; border-top: 1px solid var(--grid); }
    .stats b { display: block; font-weight: 600; font-variant-numeric: tabular-nums; }
    .pos { color: var(--good-text); } .neg { color: var(--bad-text); }
    .party { margin-top: 10px; display: grid; gap: 5px; }
    .member { display: grid; grid-template-columns: minmax(0, 1fr) 70px; gap: 2px 8px; font-size: 12px; align-items: center; }
    .with-supplies .member { grid-template-columns: minmax(0, 1fr) minmax(96px, 120px) 70px; }
    .share { display: grid; gap: 2px; font-size: 11px; font-variant-numeric: tabular-nums; }
    .share .bar { height: 4px; }
    .share span { color: var(--muted); text-align: right; }
    .share span.warn-text { color: var(--warn-text); font-weight: 600; }
    .member span { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; color: var(--ink-2); }
    .bars { display: grid; gap: 2px; }
    .bar { height: 4px; border-radius: 2px; background: var(--grid); overflow: hidden; }
    .bar > div { height: 100%; border-radius: 2px; }
    .monsters { margin-top: 10px; font-size: 12px; color: var(--ink-2); overflow-wrap: anywhere; }
    .note { margin-top: 8px; font-size: 12px; color: var(--ink-2); background: var(--surface-2); border-radius: 6px; padding: 6px 8px; }
    .missions { margin-top: 12px; padding-top: 10px; border-top: 1px solid var(--grid); display: grid; gap: 10px; }
    .mhead { color: var(--muted); font-size: 11px; text-transform: uppercase; letter-spacing: .04em; }
    .mission { display: grid; gap: 3px; min-width: 0; }
    .mtop { display: flex; justify-content: space-between; gap: 8px; font-size: 12px; font-weight: 600; }
    .mcount { font-variant-numeric: tabular-nums; color: var(--ink-2); font-weight: 500; white-space: nowrap; }
    .mtitle { font-size: 13px; overflow-wrap: anywhere; }
    .madvice { font-size: 12px; color: var(--ink-2); overflow-wrap: anywhere; }
    .streak { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; }
    .dots { display: inline-flex; gap: 3px; }
    .dot { width: 8px; height: 8px; border-radius: 50%; background: var(--grid); display: inline-block; }
    .dot.on { background: var(--good); } .dot.miss { background: var(--warn-text); } .dot.now { box-shadow: 0 0 0 1.5px var(--accent); }
    .goal { display: grid; grid-template-columns: minmax(0, 1fr) 70px auto; gap: 8px; align-items: center; font-size: 12px; }
    .alert { margin-top: 8px; font-size: 12px; border-radius: 6px; padding: 6px 8px; background: var(--surface-2); }
    .alert.warn { color: var(--warn-text); } .alert.bad { color: var(--bad-text); }
    .summary { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(150px, 45%), 1fr)); gap: 10px; margin-bottom: 14px; }
    .summary > div { background: var(--surface); border: 1px solid var(--border); border-radius: 10px; padding: 10px 12px; min-width: 0; }
    .summary small { display: block; color: var(--muted); font-size: 11px; text-transform: uppercase; letter-spacing: .04em; }
    .summary b { font-size: 20px; font-weight: 650; font-variant-numeric: tabular-nums; }
    .attention { margin-bottom: 14px; display: grid; gap: 6px; }
    .attention .item { display: flex; gap: 8px; align-items: baseline; background: var(--surface); border: 1px solid var(--border);
      border-left: 4px solid var(--axis); border-radius: 8px; padding: 7px 10px; font-size: 13px; }
    .attention .item.bad { border-left-color: var(--critical); } .attention .item.warn { border-left-color: var(--warning); }
    .attention .item.info { border-left-color: var(--s0); }
    .attention .ok { color: var(--muted); font-size: 12px; }
    .linkbtn { color: var(--ink-2); border: 1px solid var(--border); border-radius: 6px; padding: 3px 9px; font-size: 12px; text-decoration: none; }
    .linkbtn:hover { color: var(--ink); }
    tr.run { cursor: pointer; } tr.run:hover td { background: var(--surface-2); }
    tr.detail td { white-space: normal; background: var(--surface-2); font-size: 12px; color: var(--ink-2); }
    .detail-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 6px 16px; }
    .detail-grid b { color: var(--ink); font-weight: 600; }
    td.clip { max-width: 220px; overflow: hidden; text-overflow: ellipsis; }
    select { background: var(--surface); color: var(--ink); border: 1px solid var(--border); border-radius: 6px; font: inherit; font-size: 12px; padding: 3px 6px; }
    .hbar { display: inline-block; height: 6px; border-radius: 3px; background: var(--s0); vertical-align: middle; min-width: 2px; }
    .empty { color: var(--muted); font-size: 13px; padding: 14px 0 4px; }

    .section { background: var(--surface); border: 1px solid var(--border); border-radius: 10px; padding: 14px; margin-bottom: 16px; }
    .toolbar { display: flex; flex-wrap: wrap; align-items: center; gap: 8px; margin-bottom: 12px; }
    .toolbar h2 { margin: 0 auto 0 0; }
    .seg { display: inline-flex; border: 1px solid var(--border); border-radius: 7px; overflow: hidden; }
    .seg button { background: none; border: 0; color: var(--ink-2); font: inherit; font-size: 12px; padding: 4px 10px; cursor: pointer; }
    .seg button[aria-pressed="true"] { background: var(--accent-bg); color: var(--accent); font-weight: 600; }
    .legend { display: flex; flex-wrap: wrap; gap: 4px 14px; font-size: 12px; color: var(--ink-2); margin-bottom: 6px; }
    .legend span { display: inline-flex; align-items: center; gap: 6px; }
    .legend i { width: 14px; height: 2px; border-radius: 1px; display: inline-block; }
    .charts { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(340px, 100%), 1fr)); gap: 18px; }
    .chart { position: relative; min-width: 0; }
    .chart h3 { font-size: 13px; font-weight: 600; margin: 0 0 4px; color: var(--ink-2); }
    .chart svg { display: block; width: 100%; height: 220px; overflow: visible; touch-action: pan-y; }
    .chart .axis text { fill: var(--muted); font-size: 11px; font-variant-numeric: tabular-nums; }
    .tip { position: absolute; pointer-events: none; background: var(--surface); border: 1px solid var(--border); border-radius: 8px;
           box-shadow: 0 4px 16px rgba(0,0,0,.18); padding: 7px 9px; font-size: 12px; min-width: 150px; display: none; z-index: 2; }
    .tip .t { color: var(--muted); margin-bottom: 3px; }
    .tip .r { display: flex; align-items: center; gap: 6px; }
    .tip .r b { margin-left: auto; font-variant-numeric: tabular-nums; font-weight: 600; padding-left: 10px; }
    .bestiary { margin-top: 10px; }
    .bstages { position: relative; height: 8px; margin: 6px 0 4px; border-radius: 4px; background: var(--grid); overflow: hidden; }
    .bstages .fill { height: 100%; background: linear-gradient(90deg, #a97a1c, #f0c23a); }
    .bstages.done .fill { background: linear-gradient(90deg, #2f7a4f, #5fd18a); }
    .bstages i { position: absolute; top: 0; bottom: 0; width: 2px; background: var(--surface); }
    .skills-btn { display: flex; align-items: center; justify-content: space-between; gap: 8px; width: 100%; margin-top: 10px; padding: 8px 10px;
      font: inherit; font-size: 12px; color: var(--ink); background: var(--surface-2); border: 1px solid var(--border); border-radius: 8px; cursor: pointer; }
    .skills-btn:hover { border-color: var(--axis); }
    .skills-btn span { color: var(--ink-2); }
    .modal { position: fixed; inset: 0; z-index: 50; display: none; align-items: center; justify-content: center; padding: 16px; background: rgba(0,0,0,.5); }
    .modal.open { display: flex; }
    .modal-box { width: min(760px, 100%); max-height: min(86vh, 900px); display: flex; flex-direction: column; background: var(--surface);
      border: 1px solid var(--border); border-radius: 12px; box-shadow: 0 20px 60px rgba(0,0,0,.35); }
    .modal-head { display: flex; align-items: center; gap: 10px; padding: 14px 16px; border-bottom: 1px solid var(--border); }
    .modal-head h2 { margin: 0; flex: 1; font-size: 16px; font-weight: 650; }
    .modal-head button { font: inherit; font-size: 20px; line-height: 1; padding: 2px 8px; color: var(--ink-2); background: none; border: 0; cursor: pointer; border-radius: 6px; }
    .modal-head button:hover { background: var(--surface-2); }
    .modal-body { padding: 14px 16px 16px; overflow-y: auto; }
    .sk-member { padding: 12px; margin-bottom: 12px; background: var(--surface-2); border-radius: 10px; }
    .sk-top { display: flex; flex-wrap: wrap; align-items: baseline; gap: 4px 14px; margin-bottom: 8px; }
    .sk-top b { font-size: 15px; }
    .sk-top span { font-size: 12px; color: var(--ink-2); }
    .sk-top span.warn-text { color: var(--warn-text); font-weight: 600; }
    .sk-row { display: grid; grid-template-columns: minmax(110px, 1.3fr) 60px 52px minmax(80px, 1.2fr); gap: 4px 10px; align-items: center; padding: 5px 0; font-size: 12px; border-top: 1px solid var(--border); }
    .sk-row.head { border-top: 0; color: var(--muted); font-size: 11px; text-transform: uppercase; letter-spacing: .04em; }
    .sk-bar { display: flex; align-items: center; gap: 8px; }
    .sk-bar .bar { flex: 1; height: 6px; }
    .sk-cost { grid-column: 1 / -1; color: var(--muted); font-size: 11px; }
    .sk-note { margin-top: 8px; padding: 6px 8px; font-size: 12px; border-radius: 6px; background: var(--surface); }
    .sk-note.warn { color: var(--warn-text); } .sk-note.good { color: var(--good-text); }
    .pr-section { margin-bottom: 16px; }
    .pr-section h3 { margin: 0 0 8px; font-size: 12px; text-transform: uppercase; letter-spacing: .04em; color: var(--muted); font-weight: 600; }
    .pr-row { display: flex; flex-wrap: wrap; align-items: center; gap: 8px; padding: 8px 0; border-top: 1px solid var(--border); }
    .pr-row:first-of-type { border-top: 0; }
    .pr-row .grow { flex: 1; min-width: 160px; }
    .pr-row small { display: block; color: var(--muted); font-size: 11px; }
    .pr-btn, .pr-input, .pr-area { font: inherit; font-size: 12px; color: var(--ink); background: var(--surface-2); border: 1px solid var(--border); border-radius: 6px; padding: 5px 9px; }
    .pr-btn { cursor: pointer; } .pr-btn:hover { border-color: var(--axis); } .pr-btn.danger:hover { color: var(--bad-text); }
    .pr-input { min-width: 0; flex: 1; } .pr-area { width: 100%; box-sizing: border-box; min-height: 64px; font-family: ui-monospace, monospace; }
    .pr-detail { width: 100%; padding: 8px 10px; margin-top: 4px; border-radius: 8px; background: var(--surface-2); font-size: 12px; }
    .pr-detail ol { margin: 6px 0 0; padding-left: 20px; } .pr-detail li { margin: 2px 0; }
    .pr-msg { padding: 6px 10px; margin-bottom: 12px; border-radius: 6px; font-size: 12px; background: var(--surface-2); }
    .pr-msg.bad { color: var(--bad-text); } .pr-msg.ok { color: var(--good-text); }
    .sk-foot { font-size: 11px; color: var(--muted); }
    details { margin-top: 10px; font-size: 12px; color: var(--ink-2); }
    summary { cursor: pointer; }

    .table-wrap { overflow-x: auto; }
    table { width: 100%; border-collapse: collapse; font-size: 13px; }
    th, td { text-align: left; padding: 7px 8px; border-bottom: 1px solid var(--grid); white-space: nowrap; }
    th { color: var(--muted); font-weight: 500; font-size: 12px; }
    td.n, th.n { text-align: right; font-variant-numeric: tabular-nums; }
    table.mini { margin-top: 4px; font-size: 12px; }
    table.mini th, table.mini td { padding: 3px 4px; }
    table.mini th { font-size: 11px; }
    .swatch.me { box-shadow: 0 0 0 1.5px var(--ink); }
    td.neg-cell { color: var(--bad-text); font-weight: 600; }
    .cmp-group + .cmp-group { margin-top: 16px; }
    .cmp-group h3 { margin: 0 0 6px; font-size: 13px; font-weight: 600; color: var(--ink-2); }
    td .swatch { display: inline-block; margin-right: 6px; vertical-align: 0; }
    @media (max-width: 520px) { main { padding: 14px 16px 40px; } .summary b { font-size: 17px; } td.clip { max-width: 140px; } .hero b { font-size: 21px; } .stats { grid-template-columns: repeat(2, 1fr); } }
    @media (forced-colors: active) { .swatch, .legend i, .status i { forced-color-adjust: none; } }
    </style>
    </head>
    <body>
    <div class="modal" id="presets-modal" role="dialog" aria-modal="true" aria-labelledby="presets-title">
      <div class="modal-box">
        <div class="modal-head"><h2 id="presets-title">Presets de batalha</h2><button type="button" id="presets-close" aria-label="Fechar">×</button></div>
        <div class="modal-body" id="presets-body"></div>
      </div>
    </div>
    <div class="modal" id="setup-modal" role="dialog" aria-modal="true" aria-labelledby="setup-title">
      <div class="modal-box">
        <div class="modal-head"><h2 id="setup-title">Setup da hunt</h2><button type="button" id="setup-close" aria-label="Fechar">×</button></div>
        <div class="modal-body" id="setup-body"></div>
      </div>
    </div>
    <div class="modal" id="skills-modal" role="dialog" aria-modal="true" aria-labelledby="skills-title">
      <div class="modal-box">
        <div class="modal-head"><h2 id="skills-title">Skills</h2><button type="button" id="skills-close" aria-label="Fechar">×</button></div>
        <div class="modal-body" id="skills-body"></div>
      </div>
    </div>
    <main>
      <header>
        <h1><span>Tibidle</span> Hunts</h1>
        <span class="meta" id="meta">Conectando…</span>
        <button class="theme" id="presets-open" type="button">Presets</button>
        <button class="theme" id="theme" type="button">Tema</button>
      </header>
      <div class="summary" id="summary"></div>
      <div class="attention" id="attention"></div>
      <div class="cards" id="cards"></div>

      <section class="section" id="compare-section" hidden>
        <div class="toolbar"><h2>Mesma hunt, lado a lado</h2></div>
        <div id="compare"></div>
      </section>

      <section class="section">
        <div class="toolbar">
          <h2>Ao longo do tempo</h2>
          <a class="linkbtn" id="csv-history" href="/api/history.csv" download>CSV</a>
          <div class="seg" id="range">
            <button type="button" data-h="1">1h</button><button type="button" data-h="6">6h</button>
            <button type="button" data-h="12" aria-pressed="true">12h</button><button type="button" data-h="24">24h</button>
            <button type="button" data-h="168">7d</button>
          </div>
        </div>
        <div class="legend" id="legend"></div>
        <div class="charts">
          <div class="chart" id="chart-xp"><h3>XP por hora</h3></div>
          <div class="chart" id="chart-profit"><h3>Lucro por hora (loot − supplies)</h3></div>
        </div>
        <details><summary>Ver dados em tabela</summary><div class="table-wrap" id="series-table"></div></details>
      </section>

      <section class="section">
        <div class="toolbar"><h2>Lucro por nível</h2>
          <select id="level-hunt" aria-label="Hunt"></select>
          <select id="level-metric" aria-label="Medida">
            <option value="profit">Lucro/h</option><option value="supplies">Supplies/h</option><option value="xp">XP/h</option><option value="kills">Kills/h</option>
          </select>
        </div>
        <div class="legend" id="level-legend"></div>
        <div class="chart" id="chart-level"><h3 id="level-title">Lucro por hora em cada hunt encerrada, pelo nível</h3></div>
        <div class="sk-foot">Cada ponto é uma hunt encerrada de 30 min ou mais; quanto maior o ponto, mais longa a hunt.</div>
        <details><summary>Ver dados em tabela</summary><div class="table-wrap" id="level-table"></div></details>
      </section>

      <section class="section">
        <div class="toolbar"><h2>Totais por dia</h2></div>
        <div class="table-wrap" id="daily"></div>
      </section>

      <section class="section">
        <div class="toolbar"><h2>Ranking de hunts</h2>
          <select id="rank-account" aria-label="Conta"></select>
          <select id="rank-sort" aria-label="Ordenar por">
            <option value="profitPerHour">Lucro/h</option><option value="xpPerHour">XP/h</option><option value="killsPerHour">Kills/h</option>
          </select>
        </div>
        <div class="table-wrap" id="ranking"></div>
      </section>

      <section class="section">
        <div class="toolbar"><h2>Hunts encerradas</h2><a class="linkbtn" href="/api/hunts.csv" download>CSV</a></div>
        <div class="table-wrap" id="hunts"></div>
      </section>
    </main>
    <div class="tip" id="tip"></div>
    <script>
    'use strict';
    const $ = (id) => document.getElementById(id);
    const SERIES = ['var(--s0)', 'var(--s1)', 'var(--s2)', 'var(--s3)'];
    const REASONS = { stop: 'Parou', death: 'Morte', expired: 'Tempo esgotado', victory: 'Vitória', tower_top: 'Topo da torre',
      no_gold: 'Sem gold', cap_full: 'Cap cheio', level_cap: 'Level máximo', prey_resync_failed: 'Falha no prey' };
    const STATUS = {
      hunting: ['Caçando', 'var(--good)'], city: ['Na cidade', 'var(--axis)'], offline: ['App sem conexão', 'transparent'],
      replaced: ['Sessão em outro lugar', 'var(--warning)'],
    };
    const MISSION = {
      claimed:   ['✓', 'Resgatada', 'var(--good-text)'],
      ready:     ['●', 'Concluída — resgate no jogo', 'var(--accent)'],
      on_track:  ['▶', 'Contando nesta hunt', 'var(--good-text)'],
      off_track: ['⚠', 'A hunt atual não conta', 'var(--warn-text)'],
      pending:   ['○', 'Pendente', 'var(--ink-2)'],
      no_count:  ['⚠', 'Esta hunt não conta (Tower, Elite ou Boss)', 'var(--warn-text)'],
      unknown:   ['?', 'Hunt atual fora do catálogo', 'var(--ink-2)'],
      elite:     ['★', 'Elite', 'var(--ink-2)'],
      forge:     ['⚒', 'Forja (na cidade)', 'var(--ink-2)'],
    };
    const WEEKLY = { monstros: 'Matar monstros', elites: 'Vencer elites', doacoes: 'Doações', ouroConsumido: 'Gastar gold',
      mercado: 'Mercado', prey: 'Prey', revelar: 'Revelar itens', desmanchar: 'Desmanchar', refinar: 'Refinar', gema: 'Gemas', invasao: 'Invasão' };
    const VOC = { knight: 'Knight', paladin: 'Paladin', sorcerer: 'Sorcerer', druid: 'Druid', monk: 'Monk' };
    let rangeHours = 12, lastAccounts = [], lastHistory = null;

    function el(tag, props, ...children) {
      const node = document.createElement(tag);
      if (props) for (const [k, v] of Object.entries(props)) {
        if (k === 'style') Object.assign(node.style, v);
        else if (k === 'class') node.className = v;
        else node.setAttribute(k, v);
      }
      for (const c of children.flat()) if (c != null && c !== false) node.append(c instanceof Node ? c : String(c));
      return node;
    }
    const svg = (tag, attrs) => {
      const node = document.createElementNS('http://www.w3.org/2000/svg', tag);
      for (const [k, v] of Object.entries(attrs || {})) node.setAttribute(k, v);
      return node;
    };
    const num = (v) => { const n = typeof v === 'string' ? Number(v) : v; return Number.isFinite(n) ? n : 0; };
    const full = new Intl.NumberFormat('pt-BR');
    const short = new Intl.NumberFormat('pt-BR', { notation: 'compact', maximumFractionDigits: 1 });
    const fmt = (v) => Math.abs(num(v)) >= 100000 ? short.format(num(v)) : full.format(Math.round(num(v)));
    const signed = (v) => (num(v) > 0 ? '+' : '') + fmt(v);
    const duration = (ms) => {
      const m = Math.max(0, Math.floor(num(ms) / 60000)), h = Math.floor(m / 60);
      return h ? `${h}h ${String(m % 60).padStart(2, '0')}min` : `${m}min`;
    };
    const time = (ms) => new Date(ms).toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });
    const dateTime = (ms) => new Date(ms).toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' });
    const perHour = (value, ms) => num(ms) > 60000 ? num(value) / (num(ms) / 3600000) : 0;
    const topKills = (kills, n = 3) => Object.entries(kills || {}).sort((a, b) => b[1] - a[1]).slice(0, n);
    // Efficiency ratios shared by the cards, the side-by-side table and the hunt details.
    const ratio = (a, b) => num(b) > 0 ? num(a) / num(b) : null;
    const orDash = (v, f) => v === null ? '—' : f(v);
    const pct = (v) => `${Math.round(v * 100)}%`;
    const perKXp = (profit, xp) => ratio(profit, num(xp) / 1000);
    const vocation = (v) => VOC[String(v || '').toLowerCase()] || v || '';

    const until = (ms) => {
      const m = Math.max(0, Math.floor((num(ms) - Date.now()) / 60000)), h = Math.floor(m / 60);
      return h ? `${h}h ${String(m % 60).padStart(2, '0')}min` : `${m}min`;
    };

    const ELEMENT = { COMBAT_PHYSICALDAMAGE: 'físico', COMBAT_FIREDAMAGE: 'fogo', COMBAT_ENERGYDAMAGE: 'energia', COMBAT_EARTHDAMAGE: 'terra',
      COMBAT_ICEDAMAGE: 'gelo', COMBAT_HOLYDAMAGE: 'sagrado', COMBAT_DEATHDAMAGE: 'morte' };
    const BONUS = { maxHealth: 'Vida máxima', maxMana: 'Mana máxima', capacity: 'Capacidade', armor: 'Armadura', attack: 'Ataque', melee: 'Corpo a corpo',
      distance: 'Distância', shielding: 'Escudo', magicLevel: 'Nível mágico', hpRegen: 'Regen. de vida', manaRegen: 'Regen. de mana' };
    function bestiary(a) {
      const b = a.bestiary;
      if (!b || !b.stages || !b.stages.length) return null;
      const final = num(b.stages[b.stages.length - 1].kills);
      const bar = el('div', { class: 'bstages' + (b.done ? ' done' : '') }, el('div', { class: 'fill', style: { width: `${Math.min(100, 100 * num(b.kills) / final)}%` } }),
        b.stages.slice(0, -1).map((st) => el('i', { style: { left: `${100 * num(st.kills) / final}%` } })));
      let text;
      if (b.done) text = `Completo · ${fmt(b.kills)} kills · bônus ${BONUS[b.bonus] || b.bonus} +${b.stages[b.stages.length - 1].value}`;
      else {
        const n = b.next;
        text = `${fmt(b.kills)}/${fmt(final)} kills · marco ${Math.min(3, num(b.reached) + 1)}/${b.stages.length}`;
        if (n) text += ` em ${fmt(n.remaining)} kills${n.etaMs ? ` (~${duration(n.etaMs)})` : ''}`;
        if (b.etaMs) text += ` · completo em ~${duration(b.etaMs)}`;
        else text += ' · estimativa de tempo após alguns minutos de hunt';
      }
      return el('div', { class: 'bestiary' }, el('div', { class: 'mhead' }, `Bestiário da hunt · ${BONUS[b.bonus] || b.bonus}`), bar, el('div', { class: 'madvice' }, text));
    }

    // Finished hunts on this map near the current level: is the gap the level or the setup?
    function benchmark(a) {
      const b = a.benchmark;
      if (!b || !b.rows || !b.rows.length) return null;
      const cell = (v, cls) => el('td', { class: 'n' + (cls ? ' ' + cls : '') }, v);
      return el('div', { class: 'bestiary' }, el('div', { class: 'mhead' }, `Histórico nesta hunt no nível ${b.level} (±${b.range})`),
        el('table', { class: 'mini' },
          el('thead', null, el('tr', null, el('th', null, 'Conta'), ['Lucro/h', 'Supplies/h', 'Kills/h', 'Horas'].map((h) => el('th', { class: 'n' }, h)))),
          el('tbody', null, b.rows.map((r) => el('tr', { title: `${r.runs} hunt(s), nível ${r.levels}, recebido ${fmt(r.damageTakenPerHour)}/h` },
            el('td', null, el('span', { class: 'swatch' + (r.account === a.index ? ' me' : ''), style: { background: SERIES[r.account] } }), r.label),
            cell(signed(r.profitPerHour), r.profitPerHour >= 0 ? 'pos' : 'neg'), cell(fmt(r.suppliesPerHour)), cell(fmt(r.killsPerHour)),
            cell(r.hours.toLocaleString('pt-BR')))))));
    }

    // The account's best recent hunt on this map and what changed in the battle setup since then.
    function insights(a) {
      const d = a.insights;
      if (!d || !d.reference) return null;
      const r = d.reference;
      const box = el('div', { class: 'bestiary' }, el('div', { class: 'mhead' }, 'Comparado à sua melhor hunt recente aqui'));
      const drop = d.drop != null && d.drop >= 0.2;
      box.append(el('div', { class: 'madvice' }, `${dateTime(r.endedAt)} · nível ${r.levels} · ${r.hours.toLocaleString('pt-BR')}h · ${signed(r.profitPerHour)}/h`,
        d.profitPerHour != null ? el('span', { class: drop ? 'warn-text' : '' },
          ` → agora ${signed(d.profitPerHour)}/h${d.drop != null ? ` (${d.drop > 0 ? '−' : '+'}${Math.round(Math.abs(d.drop) * 100)}%)` : ''}`) : null));
      const changes = d.changes || [];
      if (!changes.length) box.append(el('div', { class: 'madvice' }, 'Mesmo setup de batalha daquela hunt.'));
      for (const c of changes) {
        box.append(el('div', { class: 'madvice' }, el('b', null, `${c.label} mudou: `), c.differences.join(' · ')));
      }
      if (drop && changes.length) box.append(el('div', { class: 'alert warn' }, 'O lucro caiu e o setup é outro: comece revertendo essas mudanças (Hunts recentes → Setup desta hunt mostra o setup completo daquela hunt).'));
      return box;
    }

    let openSkills = null;
    function skillsButton(a) {
      const d = a.skills;
      if (!d || !d.members || !d.members.length) return null;
      const total = d.members.reduce((sum, m) => sum + num(m.dps), 0);
      const tips = d.members.reduce((sum, m) => sum + (m.suggestions || []).length, 0);
      const btn = el('button', { class: 'skills-btn', type: 'button' }, el('b', null, 'Análise de skills'),
        el('span', null, `~${fmt(total)}/s${tips ? ` · ${tips} sugest${tips > 1 ? 'ões' : 'ão'}` : ''}`));
      btn.addEventListener('click', () => { openSkills = a.index; renderSkillsModal(); });
      return btn;
    }
    function skillsBody(a) {
      const d = a.skills;
      const body = el('div');
      if (!d || !d.members) return el('div', { class: 'empty' }, 'Sem dados de skills no momento (a conta precisa estar caçando).');
      for (const m of d.members) {
        const top = Math.max(1, ...(m.skills || []).map((s) => num(s.dps)));
        const box = el('div', { class: 'sk-member' }, el('div', { class: 'sk-top' }, el('b', null, `${m.name} · ${vocation(m.vocation)}`),
          el('span', null, `${fmt(m.dps)} dano/s`), el('span', null, `${fmt(m.manaPerMinute)} mana/min`),
          m.manaAverage != null ? el('span', { class: m.manaAverage < 0.25 ? 'warn-text' : '' }, `mana média na hunt ${Math.round(m.manaAverage * 100)}%`) : null));
        box.append(el('div', { class: 'sk-row head' }, el('span', null, 'Skill'), el('span', null, 'Elemento'), el('span', null, 'Alvos'), el('span', null, 'Contribuição')));
        for (const sk of m.skills || []) {
          const cls = num(sk.multiplier) < 0.5 ? 'warn' : num(sk.multiplier) >= 1.1 ? 'good' : '';
          box.append(el('div', { class: 'sk-row' }, el('span', null, sk.name), el('span', null, ELEMENT[sk.element] || sk.element),
            el('span', { class: cls ? 'sk-note ' + cls : '', style: cls ? { margin: 0, padding: '0 4px', background: 'none' } : {} }, `${Math.round(num(sk.multiplier) * 100)}%`),
            el('div', { class: 'sk-bar' }, el('div', { class: 'bar' }, el('div', { style: { width: `${100 * num(sk.dps) / top}%`, background: 'var(--s0)' } })),
              el('span', { class: 'mcount' }, `${fmt(sk.dps)}/s`)),
            el('span', { class: 'sk-cost' }, `${fmt(sk.mana)} mana · recarga ${sk.cooldown}s`)));
        }
        for (const sk of m.skills || []) if (sk.warning) box.append(el('div', { class: 'sk-note warn' }, `${sk.name}: ${sk.warning}`));
        for (const sg of m.suggestions || []) {
          const what = sg.replace ? `Trocar ${sg.replace} por ${sg.add}` : `Adicionar ${sg.add}`;
          const mana = num(sg.manaPerMinuteDelta);
          const text = `${what}: ${sg.fromZero ? 'hoje causa 0 de dano' : `+${Math.round(num(sg.gain) * 100)}% de dano estimado`}, ${mana >= 0 ? '+' : ''}${fmt(mana)} mana/min.`;
          box.append(sg.manaLimited
            ? el('div', { class: 'sk-note warn' }, `${text} Atenção: ${m.name} já passa a hunt com ~${Math.round(num(m.manaAverage) * 100)}% de mana em média; a mana extra deve vir de poção (mais supplies) ou a skill vai falhar por falta de mana.`)
            : el('div', { class: 'sk-note good' }, text));
        }
        if (!(m.suggestions || []).length && !(m.skills || []).some((sk) => sk.warning)) box.append(el('div', { class: 'sk-note' }, 'Nenhuma troca com ganho relevante encontrada.'));
        body.append(box);
      }
      body.append(el('div', { class: 'sk-foot' },
        `${d.calibrated ? `Calibrado com ${d.samples} hunts suas.` : 'Ainda sem calibração (precisa de 3 hunts completas).'} Pull médio assumido: ${d.crowd} criaturas.` +
        `${d.coverage < 1 ? ` Resistências conhecidas para ${Math.round(num(d.coverage) * 100)}% dos kills.` : ''} É uma estimativa por modelo, não uma garantia.`));
      return body;
    }
    function renderSkillsModal() {
      const modal = $('skills-modal');
      const a = openSkills === null ? null : lastAccounts.find((x) => x.index === openSkills);
      if (!a) { modal.classList.remove('open'); openSkills = null; return; }
      const scroll = $('skills-body').scrollTop;
      $('skills-title').textContent = `Skills · ${a.label}`;
      $('skills-body').replaceChildren(skillsBody(a));
      $('skills-body').scrollTop = scroll;
      modal.classList.add('open');
    }
    function closeSkills() { openSkills = null; renderSkillsModal(); }

    function missions(a) {
      const d = a.daily;
      if (!d || !d.missions || !d.missions.length) return null;
      const box = el('div', { class: 'missions' },
        el('div', { class: 'mhead' }, 'Missões diárias' + (d.dailyResetAt ? ` · reseta em ${until(d.dailyResetAt)}` : '')));
      for (const m of d.missions) {
        const [icon, label, color] = MISSION[m.state] || MISSION.pending;
        const pct = m.quantity ? Math.min(100, 100 * m.progress / m.quantity) : 0;
        const done = m.state === 'claimed' || m.state === 'ready';
        const row = el('div', { class: 'mission' },
          el('div', { class: 'mtop' }, el('span', { style: { color } }, `${icon} ${label}`), el('span', { class: 'mcount' }, `${fmt(m.progress)}/${fmt(m.quantity)}`)),
          el('div', { class: 'mtitle' }, m.title || (m.targets || []).join(', ')),
          el('div', { class: 'bar' }, el('div', { style: { width: `${pct}%`, background: done ? 'var(--good)' : 'var(--s0)' } })));
        if (m.kind === 'monster' && !done) {
          const maps = (m.candidates || []).map((c) => c.title + (c.full ? '' : ' (parcial)'));
          if (m.state === 'on_track') {
            row.append(el('div', { class: 'madvice' }, `Hunt atual: ${d.currentHunt ? d.currentHunt.title : '—'}`));
            if (m.eta) {
              const ok = m.eta.fits !== false;
              row.append(el('div', { class: 'madvice', style: { color: ok ? 'var(--good-text)' : 'var(--warn-text)' } },
                `${fmt(m.eta.perHour)} kills/h → faltam ${fmt(m.eta.remaining)}, conclui em ~${duration(m.eta.etaMs)}` +
                (m.eta.fits === undefined ? '' : ok ? ' (antes do reset)' : ' — não dá tempo antes do reset')));
            }
          }
          else if (m.state === 'no_count') row.append(el('div', { class: 'madvice' }, `Hunt sugerida: ${maps.join(' · ') || '—'}`));
          else {
            const now = d.currentHunt && a.status === 'hunting' ? `Hunt atual: ${d.currentHunt.title}. ` : '';
            row.append(el('div', { class: 'madvice' }, maps.length ? `${now}Hunt sugerida: ${maps.join(' · ')}` : `${now}Sem hunt conhecida para: ${(m.targets || []).join(', ')}`));
          }
        } else if (m.kind === 'elite' && !done) {
          row.append(el('div', { class: 'madvice' }, `Elite alvo: ${(m.targets || [])[0] || '—'}`));
        }
        box.append(row);
      }
      const st = d.streak;
      if (st) {
        const dots = (st.days || []).map((s) => el('i', { class: 'dot ' + (s === 'resgatado' || s === 'cumprido' ? 'on' : s === 'recuperar' ? 'miss' : s === 'hoje' ? 'now' : ''), title: s }));
        const risk = st.atRisk ? ` · ⚠ ${st.open} missão(ões) sem resgatar e o dia fecha em ${until(d.dailyResetAt)}` : '';
        const miss = st.toRecover ? ` · ${st.toRecover} dia(s) perdido(s) — recuperar custa ${fmt(st.recoverCost)} coins` : '';
        box.append(el('div', { class: 'streak' }, el('span', { class: 'dots' }, dots),
          el('span', { class: 'madvice', style: { color: st.atRisk || st.toRecover ? 'var(--warn-text)' : '' } },
            `Sequência: dia ${st.day}/7${risk}${miss}`)));
      }
      if (d.weeklyGoals && d.weeklyGoals.length) {
        box.append(el('div', { class: 'mhead' }, `Metas semanais${d.weekly && d.weekly.needed ? ` · ${d.weekly.done}/${d.weekly.needed} (precisa de ${d.weekly.needed})` : ''}`));
        for (const g of d.weeklyGoals) {
          const pct = g.goal ? Math.min(100, 100 * g.progress / g.goal) : 0;
          box.append(el('div', { class: 'goal' }, el('span', null, WEEKLY[g.id] || g.id),
            el('div', { class: 'bar' }, el('div', { style: { width: `${pct}%`, background: pct >= 100 ? 'var(--good)' : 'var(--s0)' } })),
            el('span', { class: 'mcount' }, `${fmt(g.progress)}/${fmt(g.goal)}`)));
        }
      } else if (d.weekly && d.weekly.needed) box.append(el('div', { class: 'madvice' }, `Semanais: ${d.weekly.done}/${d.weekly.needed} concluídas`));
      return box;
    }

    async function getJSON(path) {
      const r = await fetch(path, { cache: 'no-store' });
      if (!r.ok) throw new Error(r.status);
      return r.json();
    }

    // ---- account cards ----
    function stat(label, value, cls) { return el('div', null, el('small', null, label), el('b', cls ? { class: cls } : null, value)); }

    function card(a) {
      const [statusText, statusColor] = STATUS[a.status] || STATUS.offline;
      const statusDot = el('i', { style: { background: statusColor, border: a.status === 'offline' ? '1px solid var(--muted)' : '0' } });
      const top = el('div', { class: 'card-top' },
        el('span', { class: 'swatch', style: { background: SERIES[a.index] } }),
        el('span', { class: 'label' }, a.label),
        el('span', { class: 'status' }, statusDot, statusText));
      const state = a.state || {}, character = state.character || {}, account = a.account || {};
      const who = character.name || account.name;
      const level = character.level || account.level;
      const huntNow = a.status === 'hunting' && a.daily && a.daily.currentHunt ? ` · ${a.daily.currentHunt.title}` : '';
      const sub = el('div', { class: 'sub' }, who ? `${who}${level ? ` · level ${level}` : ''}${a.training ? ' · treino' : ''}${huntNow}` : '');
      const node = el('div', { class: 'card' }, top, sub);
      const an = a.analyzer;
      if (a.status === 'hunting' && an) {
        const elapsed = an.elapsedMs, profit = num(an.lootGold) - num(an.suppliesGold);
        node.append(el('div', { class: 'hero' },
          el('div', null, el('small', null, 'XP/h'), el('b', null, fmt(an.xpPerHour))),
          el('div', null, el('small', null, 'Lucro/h'), el('b', { class: profit >= 0 ? 'pos' : 'neg' }, signed(perHour(profit, elapsed))))));
        node.append(el('div', { class: 'stats' },
          stat('Tempo', duration(elapsed)), stat('XP', fmt(an.xp)), stat('Kills', fmt(an.killsTotal)),
          stat('Loot', fmt(an.lootGold)), stat('Supplies', fmt(an.suppliesGold)), stat('Balance', signed(profit), profit >= 0 ? 'pos' : 'neg'),
          stat('Dano/h', fmt(perHour(an.damageDealt, elapsed))), stat('Recebido/h', fmt(perHour(an.damageTaken, elapsed))),
          stat('Cura/h', fmt(perHour(an.healingDone, elapsed))), stat('Lucro/kill', num(an.killsTotal) ? signed(profit / num(an.killsTotal)) : '—'),
          stat('Kills/h', fmt(perHour(an.killsTotal, elapsed))),
          stat('Supplies/kill', orDash(ratio(an.suppliesGold, an.killsTotal), fmt)),
          stat('Lucro/1k XP', orDash(perKXp(profit, an.xp), signed))));
        const drops = topKills(an.drops, 12).filter(([n]) => n.toLowerCase() !== 'gold coin').slice(0, 5);
        const kills = topKills(an.kills);
        if (kills.length) node.append(el('div', { class: 'monsters' }, 'Mais abatidos: ' + kills.map(([m, n]) => `${m} ×${fmt(n)}`).join(' · ')));
        if (drops.length) node.append(el('div', { class: 'monsters' }, 'Drops: ' + drops.map(([m, n]) => `${m} ×${fmt(n)}`).join(' · ')));
      } else if (a.lastSummary) {
        const s = a.lastSummary;
        node.append(el('div', { class: 'note' },
          `Última hunt: ${duration(num(s.elapsedSec) * 1000)} · ${REASONS[s.reason] || s.reason || ''} · XP/h ${fmt(s.xpPerHour)} · balance ${signed(s.balance)}`));
      } else {
        node.append(el('div', { class: 'empty' }, a.status === 'offline' ? 'Abra o jogo nesta aba do gerenciador.' : 'Sem hunt em andamento.'));
      }
      const inv = a.invasion;
      if (inv && !inv.finished && inv.next) {
        const when = inv.next.live ? 'em andamento' : `começa às ${time(inv.next.startAt)} (${until(inv.next.startAt)})`;
        node.append(el('div', { class: 'note' }, `${inv.name}${inv.boss ? ` · ${inv.boss}` : ''}: ${inv.joined ? 'inscrito' : 'não inscrito'} · ${when}`));
      }
      const ins = insights(a);
      if (ins) node.append(ins);
      const bm = benchmark(a);
      if (bm) node.append(bm);
      const be = bestiary(a);
      if (be) node.append(be);
      const sk = skillsButton(a);
      if (sk) node.append(sk);
      if (a.supply) {
        for (const x of a.supply.alerts || []) node.append(el('div', { class: 'alert ' + x.level }, x.text));
        const k = a.supply.keys;
        if (k) node.append(el('div', { class: 'madvice' }, `Chaves: ${k.used}/${k.max}` + (k.nextKeyMs && k.used < k.max ? ` · próxima em ~${duration(k.nextKeyMs)}` : '')));
        const c = a.supply.cap;
        if (c) node.append(el('div', { class: 'madvice' }, `Mochila: ${fmt(c.used)}/${fmt(c.total)} (${Math.round(100 * c.used / c.total)}%)`));
      }
      const daily = missions(a);
      if (daily) node.append(daily);
      const party = state.party || (a.status !== 'hunting' ? a.roster : null);
      if (party && party.length) {
        // Who spends the supplies: one member taking most of it points at that member's heal/potion setup.
        const sameName = party.length > 1 && party.every((m) => m.name === party[0].name);
        const spent = a.status === 'hunting' ? party.reduce((sum, m) => sum + num(m.suppliesGold), 0) : 0;
        if (spent > 0) node.append(el('div', { class: 'mhead', style: { marginTop: '12px' } }, 'Party · parte dos supplies na hunt'));
        node.append(el('div', { class: 'party' + (spent > 0 ? ' with-supplies' : '') }, party.map((m) => el('div', { class: 'member' },
          el('span', { title: m.name || '' }, sameName ? `${vocation(m.vocation)} ${m.level || ''}` : `${m.name || ''} · ${vocation(m.vocation)} ${m.level || ''}`),
          spent > 0 ? supplyShare(num(m.suppliesGold), spent, party.length) : null,
          m.maxHp ? el('div', { class: 'bars' },
            el('div', { class: 'bar', title: `HP ${m.hp}/${m.maxHp}` }, el('div', { style: { width: `${Math.max(0, Math.min(100, 100 * num(m.hp) / num(m.maxHp)))}%`, background: 'var(--good)' } })),
            num(m.maxMana) > 0 ? el('div', { class: 'bar', title: `Mana ${m.mana}/${m.maxMana}` }, el('div', { style: { width: `${Math.max(0, Math.min(100, 100 * num(m.mana) / num(m.maxMana)))}%`, background: 'var(--s0)' } })) : null)
            : el('span')))));
      }
      if (a.offline && num(a.offline.elapsedMs) > 0) {
        node.append(el('div', { class: 'note' },
          `Enquanto o app estava fechado (${duration(a.offline.elapsedMs)}): +${fmt(a.offline.xp)} XP · ${fmt(a.offline.killsTotal)} kills · ${fmt(a.offline.lootGold)} gold de loot`));
      }
      return node;
    }

    // ---- accounts on the same hunt, side by side ----
    // better: which direction is good; cells 20%+ worse than the best account of the group turn red.
    const COMPARE = [
      ['Nível', (a) => num((a.state && a.state.character || {}).level || (a.account || {}).level), null, (v) => String(v || '—')],
      ['Tempo', (a) => num(a.analyzer.elapsedMs), null, duration],
      ['Lucro/h', (a) => perHour(num(a.analyzer.lootGold) - num(a.analyzer.suppliesGold), a.analyzer.elapsedMs), 'high', signed],
      ['Loot/h', (a) => perHour(a.analyzer.lootGold, a.analyzer.elapsedMs), 'high', fmt],
      ['Supplies/h', (a) => perHour(a.analyzer.suppliesGold, a.analyzer.elapsedMs), 'low', fmt],
      ['XP/h', (a) => num(a.analyzer.xpPerHour), 'high', fmt],
      ['Kills/h', (a) => perHour(a.analyzer.killsTotal, a.analyzer.elapsedMs), 'high', fmt],
      ['Dano causado/h', (a) => perHour(a.analyzer.damageDealt, a.analyzer.elapsedMs), 'high', fmt],
      ['Dano recebido/h', (a) => perHour(a.analyzer.damageTaken, a.analyzer.elapsedMs), 'low', fmt],
      ['Cura/h', (a) => perHour(a.analyzer.healingDone, a.analyzer.elapsedMs), null, fmt],
      ['Supplies/kill', (a) => ratio(a.analyzer.suppliesGold, a.analyzer.killsTotal), 'low', (v) => orDash(v, fmt)],
      ['Lucro/1k XP', (a) => perKXp(num(a.analyzer.lootGold) - num(a.analyzer.suppliesGold), a.analyzer.xp), 'high', (v) => orDash(v, signed)],
      ['Cura ÷ recebido', (a) => ratio(a.analyzer.healingDone, a.analyzer.damageTaken), null, (v) => orDash(v, pct)],
    ];
    const COMPARE_MIN_MS = 10 * 60000;
    function renderCompare(accounts) {
      const groups = new Map();
      for (const a of accounts) {
        if (a.status !== 'hunting' || a.training || !a.analyzer || a.huntId == null) continue;
        if (!groups.has(a.huntId)) groups.set(a.huntId, []);
        groups.get(a.huntId).push(a);
      }
      const shown = [...groups.values()].filter((g) => g.length >= 2);
      $('compare-section').hidden = !shown.length;
      if (!shown.length) { $('compare').replaceChildren(); return; }
      $('compare').replaceChildren(...shown.map((group) => {
        const title = (group[0].daily && group[0].daily.currentHunt && group[0].daily.currentHunt.title) || `Hunt #${group[0].huntId}`;
        const ranked = group.filter((a) => num(a.analyzer.elapsedMs) >= COMPARE_MIN_MS);
        const rows = COMPARE.map(([label, value, better, format]) => {
          const values = group.map(value);
          const pool = ranked.map(value).filter((v) => v !== null);
          const best = !better || pool.length < 2 ? null : better === 'high' ? Math.max(...pool) : Math.min(...pool);
          return el('tr', null, el('th', null, label), group.map((a, i) => {
            const v = values[i];
            const bad = best !== null && v !== null && ranked.includes(a) &&
              (better === 'high' ? v < best - Math.abs(best) * 0.2 : v > best * 1.2);
            return el('td', { class: 'n' + (bad ? ' neg-cell' : '') }, format(v));
          }));
        });
        return el('div', { class: 'cmp-group' }, el('h3', null, title),
          el('div', { class: 'table-wrap' }, el('table', null,
            el('thead', null, el('tr', null, el('th', null, ''), group.map((a) => el('th', { class: 'n' },
              el('span', { class: 'swatch', style: { background: SERIES[a.index], display: 'inline-block', marginRight: '6px' } }), a.label)))),
            el('tbody', null, rows))),
          el('div', { class: 'sk-foot', style: { marginTop: '6px' } },
            'Em vermelho: 20% ou mais pior que a melhor conta desta hunt. Contas com menos de 10 min de hunt não entram na comparação.'));
      }));
    }

    function supplyShare(value, total, members) {
      const share = total > 0 ? value / total : 0;
      const heavy = members > 1 && share >= 0.5;
      return el('div', { class: 'share', title: `${fmt(value)} gold em supplies (${Math.round(share * 100)}% da party)` },
        el('div', { class: 'bar' }, el('div', { style: { width: `${100 * share}%`, background: heavy ? 'var(--warning)' : 'var(--s0)' } })),
        el('span', { class: heavy ? 'warn-text' : '' }, `${Math.round(share * 100)}% · ${fmt(value)}`));
    }

    // ---- battle presets (local library; writes only work from this Mac) ----
    let presetData = null, presetMsg = null;
    const post = async (path, body) => {
      const r = await fetch(path, { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Tibidle': '1' }, body: JSON.stringify(body) });
      if (!r.ok) throw new Error(r.status === 403 ? 'Salvar só funciona abrindo o dashboard neste Mac (localhost).' : `Erro ${r.status}`);
      return r.json();
    };
    async function presetAction(path, body, okText) {
      try {
        const res = await post(path, body);
        presetMsg = res.ok ? { ok: true, text: okText } : { ok: false, text: res.error || 'Não foi possível concluir.' };
      } catch (e) { presetMsg = { ok: false, text: e.message }; }
      await loadPresets();
    }
    async function loadPresets() {
      try { presetData = await getJSON('/api/presets'); } catch (_) { presetData = null; }
      renderPresets();
    }
    const dateText = (ms) => new Date(ms).toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' });
    async function showPresetDetail(p, box, accountIndex) {
      let data;
      try { data = await getJSON(`/api/presets/compare?id=${p.id}&account=${accountIndex}`); } catch (_) { box.textContent = 'Falha ao carregar.'; return; }
      const parts = [];
      if (data.notice) parts.push(el('div', { class: 'madvice' }, data.notice));
      if (data.differences) parts.push(el('div', null, el('b', null, 'Diferenças em relação à config atual'),
        data.differences.length ? el('ul', null, data.differences.map((d) => el('li', null, d))) : el('div', { class: 'madvice' }, 'Igual à configuração atual.')));
      if (data.damage) parts.push(el('div', { class: 'madvice' }, `Dano estimado (${data.damage.character}): atual ~${fmt(data.damage.current)}/s · preset ~${fmt(data.damage.preset)}/s`));
      for (const w of data.warnings || []) parts.push(el('div', { class: 'madvice warn' }, w));
      parts.push(el('div', null, el('b', null, 'Passo a passo no jogo'), el('ol', null, (data.steps || []).map((x) => el('li', null, x)))));
      box.replaceChildren(...parts);
    }
    function renderPresets() {
      const body = $('presets-body');
      if (!presetData) { body.replaceChildren(el('div', { class: 'empty' }, 'Sem conexão com o gerenciador.')); return; }
      const nodes = [];
      if (presetMsg) nodes.push(el('div', { class: 'pr-msg ' + (presetMsg.ok ? 'ok' : 'bad') }, presetMsg.text));
      if (!presetData.canWrite) nodes.push(el('div', { class: 'pr-msg' }, 'Modo leitura: para salvar, importar ou apagar presets abra o dashboard neste Mac (localhost).'));
      if (presetData.canWrite) {
        const sec = el('div', { class: 'pr-section' }, el('h3', null, 'Salvar a configuração atual'));
        let any = false;
        for (const a of presetData.accounts) for (const v of a.vocations) {
          any = true;
          const input = el('input', { class: 'pr-input', value: v.name, maxlength: '80' });
          const btn = el('button', { class: 'pr-btn', type: 'button' }, 'Salvar');
          btn.addEventListener('click', () => presetAction('/api/presets/save', { account: a.index, vocation: v.vocation, name: input.value }, 'Preset salvo.'));
          sec.append(el('div', { class: 'pr-row' }, el('div', { class: 'grow' }, `${a.label} · ${v.character}`, el('small', null, `${v.vocation}${a.huntTitle ? ` · ${a.huntTitle}` : ' · sem hunt em andamento'}`)), input, btn));
        }
        if (!any) sec.append(el('div', { class: 'madvice' }, 'O app ainda não leu a configuração de batalha de nenhuma conta. Recarregue o jogo (⌘R na aba) e aguarde alguns segundos.'));
        nodes.push(sec);
      }
      const lib = el('div', { class: 'pr-section' }, el('h3', null, `Biblioteca (${presetData.presets.length})`));
      if (!presetData.presets.length) lib.append(el('div', { class: 'madvice' }, 'Nenhum preset salvo ainda.'));
      for (const p of presetData.presets) {
        const detail = el('div', { class: 'pr-detail', style: { display: 'none' } });
        const row = el('div', { class: 'pr-row' }, el('div', { class: 'grow' }, el('b', null, p.name), el('small', null, `${p.vocation} · ${dateText(p.createdAt)} · ${p.steps.length} itens`)));
        const copy = el('button', { class: 'pr-btn', type: 'button' }, 'Copiar texto');
        copy.addEventListener('click', async () => {
          try { await navigator.clipboard.writeText(p.text); copy.textContent = 'Copiado'; }
          catch (_) { window.prompt('Copie o texto do preset:', p.text); }
          setTimeout(() => { copy.textContent = 'Copiar texto'; }, 1500);
        });
        const view = el('button', { class: 'pr-btn', type: 'button' }, 'Ver passos');
        const picker = el('select', { class: 'pr-input', style: { display: 'none', flex: '0 0 auto' } }, presetData.accounts.map((a) => el('option', { value: a.index }, a.label)));
        view.addEventListener('click', () => {
          const open = detail.style.display === 'none';
          detail.style.display = open ? 'block' : 'none'; picker.style.display = open ? '' : 'none';
          if (open) showPresetDetail(p, detail, picker.value);
        });
        picker.addEventListener('change', () => showPresetDetail(p, detail, picker.value));
        row.append(copy, view, picker);
        if (presetData.canWrite) {
          const rename = el('button', { class: 'pr-btn', type: 'button' }, 'Renomear');
          rename.addEventListener('click', () => { const n = window.prompt('Novo nome:', p.name); if (n) presetAction('/api/presets/rename', { id: p.id, name: n }, 'Preset renomeado.'); });
          const del = el('button', { class: 'pr-btn danger', type: 'button' }, 'Excluir');
          del.addEventListener('click', () => { if (window.confirm(`Excluir "${p.name}"?`)) presetAction('/api/presets/delete', { id: p.id }, 'Preset excluído.'); });
          row.append(rename, del);
        }
        row.append(detail);
        lib.append(row);
      }
      nodes.push(lib);
      if (presetData.canWrite) {
        const area = el('textarea', { class: 'pr-area', placeholder: 'Cole aqui um texto de preset (começa com tbp1.)' });
        const name = el('input', { class: 'pr-input', placeholder: 'Nome (opcional)', maxlength: '80' });
        const btn = el('button', { class: 'pr-btn', type: 'button' }, 'Importar');
        btn.addEventListener('click', () => presetAction('/api/presets/import', { text: area.value, name: name.value }, 'Preset importado.'));
        nodes.push(el('div', { class: 'pr-section' }, el('h3', null, 'Importar'), area, el('div', { class: 'pr-row' }, name, btn)));
      }
      const scroll = body.scrollTop;
      body.replaceChildren(...nodes);
      body.scrollTop = scroll;
    }
    $('presets-open').addEventListener('click', () => { presetMsg = null; $('presets-modal').classList.add('open'); loadPresets(); });
    const closePresets = () => $('presets-modal').classList.remove('open');
    $('presets-close').addEventListener('click', closePresets);
    $('presets-modal').addEventListener('click', (e) => { if (e.target === $('presets-modal')) closePresets(); });

    $('skills-close').addEventListener('click', closeSkills);
    $('skills-modal').addEventListener('click', (e) => { if (e.target === $('skills-modal')) closeSkills(); });
    document.addEventListener('keydown', (e) => { if (e.key === 'Escape') { closeSkills(); closePresets(); closeSetup(); } });

    async function refreshState() {
      try {
        const data = await getJSON('/api/state');
        lastAccounts = data.accounts;
        renderSummary(data);
        $('cards').replaceChildren(...data.accounts.map(card));
        renderCompare(data.accounts);
        $('meta').textContent = `Atualizado às ${new Date(data.generatedAt).toLocaleTimeString('pt-BR')}`;
        renderLegend();
        renderSkillsModal();
      } catch (_) {
        $('meta').textContent = 'Sem conexão com o gerenciador — ele está aberto?';
      }
    }

    function renderSummary(data) {
      const hunting = data.accounts.filter((a) => a.status === 'hunting' && a.analyzer);
      let xp = 0, profit = 0;
      for (const a of hunting) {
        xp += num(a.analyzer.xpPerHour);
        profit += perHour(num(a.analyzer.lootGold) - num(a.analyzer.suppliesGold), a.analyzer.elapsedMs);
      }
      const ready = data.accounts.reduce((n, a) => n + (((a.daily || {}).missions || []).filter((m) => m.state === 'ready').length), 0);
      const reset = data.accounts.map((a) => (a.daily || {}).dailyResetAt).filter(Boolean).sort()[0];
      const tile = (label, value, cls) => el('div', null, el('small', null, label), el('b', cls ? { class: cls } : null, value));
      $('summary').replaceChildren(
        tile('XP/h total', fmt(xp)), tile('Lucro/h total', signed(profit), profit >= 0 ? 'pos' : 'neg'),
        tile('Caçando', `${hunting.length}/${data.accounts.length}`), tile('Missões p/ resgatar', String(ready), ready ? 'pos' : ''),
        tile('Reset diário', reset ? `em ${until(reset)}` : '—'));
      const items = data.attention || [];
      $('attention').replaceChildren(...(items.length ? items.map((i) => el('div', { class: 'item ' + i.level },
        el('span', { class: 'swatch', style: { background: SERIES[i.account] } }), i.text))
        : [el('div', { class: 'ok' }, '✓ Nada precisa de atenção agora.')]));
    }

    // ---- charts ----
    function renderLegend() {
      $('legend').replaceChildren(...lastAccounts.map((a) => el('span', null, el('i', { style: { background: SERIES[a.index] } }), a.label)));
    }

    // Round tick step (1, 2, 2.5, 5 × 10^n) so the axis reads 0, 500 mil, 1 mi…
    function niceStep(range) {
      const raw = range / 4, p = 10 ** Math.floor(Math.log10(raw)), f = raw / p;
      return (f <= 1 ? 1 : f <= 2 ? 2 : f <= 2.5 ? 2.5 : f <= 5 ? 5 : 10) * p;
    }
    const axisFmt = (v) => Math.abs(v) >= 10000 ? short.format(v) : full.format(v);

    function drawChart(host, series, valueIndex) {
      host.querySelector('svg')?.remove();
      host.querySelector('.empty')?.remove();
      const entries = Object.entries(series).map(([k, pts]) => [Number(k), pts]).filter(([, pts]) => pts.length);
      if (!entries.length) { host.append(el('div', { class: 'empty' }, 'Sem amostras neste período. Os dados aparecem durante as hunts.')); return; }
      const W = Math.max(host.clientWidth, 300), H = 220, L = 52, R = 70, T = 10, B = 24;
      const t1 = Date.now(), t0 = t1 - rangeHours * 3600000;
      let lo = 0, hi = 0;
      for (const [, pts] of entries) for (const p of pts) { lo = Math.min(lo, p[valueIndex]); hi = Math.max(hi, p[valueIndex]); }
      const step = niceStep(Math.max(hi - lo, 1));
      hi = Math.max(Math.ceil(hi / step) * step, step); lo = Math.floor(lo / step) * step;
      const x = (t) => L + (t - t0) / (t1 - t0) * (W - L - R);
      const y = (v) => T + (hi - v) / (hi - lo) * (H - T - B);
      const root = svg('svg', { viewBox: `0 0 ${W} ${H}`, role: 'img', 'aria-label': host.querySelector('h3').textContent });
      const axis = svg('g', { class: 'axis' });
      for (let v = lo; v <= hi + step / 2; v += step) {
        axis.append(svg('line', { x1: L, x2: W - R, y1: y(v), y2: y(v), stroke: Math.abs(v) < step / 2 ? 'var(--axis)' : 'var(--grid)', 'stroke-width': 1 }));
        const label = svg('text', { x: L - 8, y: y(v) + 4, 'text-anchor': 'end' }); label.textContent = axisFmt(v); axis.append(label);
      }
      for (let i = 0; i <= 4; i++) {
        const t = t0 + (t1 - t0) * i / 4;
        const label = svg('text', { x: x(t), y: H - 6, 'text-anchor': i === 0 ? 'start' : i === 4 ? 'end' : 'middle' });
        label.textContent = rangeHours > 24 ? dateTime(t) : time(t); axis.append(label);
      }
      root.append(axis);
      const ends = [];
      for (const [account, pts] of entries) {
        let d = '', prev = null;
        for (const p of pts) {
          d += `${prev && p[0] - prev[0] <= 180000 ? 'L' : 'M'}${x(p[0]).toFixed(1)},${y(p[valueIndex]).toFixed(1)}`;
          prev = p;
        }
        root.append(svg('path', { d, fill: 'none', stroke: SERIES[account], 'stroke-width': 2, 'stroke-linejoin': 'round', 'stroke-linecap': 'round' }));
        const last = pts[pts.length - 1];
        ends.push({ account, y: y(last[valueIndex]), x: x(last[0]) });
      }
      // Direct labels at line ends, nudged apart so they never overlap.
      ends.sort((a, b) => a.y - b.y);
      for (let i = 1; i < ends.length; i++) ends[i].y = Math.max(ends[i].y, ends[i - 1].y + 13);
      for (const e of ends) {
        const name = (lastAccounts[e.account] || {}).label || `Conta ${e.account + 1}`;
        const label = svg('text', { x: Math.min(e.x + 6, W - R + 6), y: e.y + 4, fill: 'var(--ink-2)', 'font-size': 11 });
        label.textContent = name.length > 10 ? name.slice(0, 9) + '…' : name;
        root.append(label);
      }
      // Hover layer: crosshair + tooltip with every account's nearest sample.
      const cross = svg('line', { y1: T, y2: H - B, stroke: 'var(--muted)', 'stroke-width': 1, visibility: 'hidden' });
      const dots = svg('g', { visibility: 'hidden' });
      const hit = svg('rect', { x: L, y: T, width: W - L - R, height: H - T - B, fill: 'transparent' });
      root.append(cross, dots, hit);
      const tip = $('tip');
      const move = (ev) => {
        const box = root.getBoundingClientRect(), px = (ev.clientX - box.left) * W / box.width;
        const t = t0 + (px - L) / (W - L - R) * (t1 - t0);
        const rows = [];
        dots.replaceChildren();
        for (const [account, pts] of entries) {
          let best = null;
          for (const p of pts) if (!best || Math.abs(p[0] - t) < Math.abs(best[0] - t)) best = p;
          if (!best || Math.abs(best[0] - t) > Math.max(180000, (t1 - t0) / 60)) continue;
          rows.push([account, best]);
          dots.append(svg('circle', { cx: x(best[0]), cy: y(best[valueIndex]), r: 4, fill: SERIES[account], stroke: 'var(--surface)', 'stroke-width': 2 }));
        }
        if (!rows.length) { leave(); return; }
        cross.setAttribute('x1', px); cross.setAttribute('x2', px);
        cross.setAttribute('visibility', 'visible'); dots.setAttribute('visibility', 'visible');
        tip.replaceChildren(el('div', { class: 't' }, rangeHours > 24 ? dateTime(rows[0][1][0]) : time(rows[0][1][0])),
          ...rows.map(([account, p]) => el('div', { class: 'r' }, el('span', { class: 'swatch', style: { background: SERIES[account] } }),
            (lastAccounts[account] || {}).label || `Conta ${account + 1}`, el('b', null, fmt(p[valueIndex])))));
        tip.style.display = 'block';
        const left = ev.clientX + 14 + tip.offsetWidth > window.innerWidth ? ev.clientX - tip.offsetWidth - 14 : ev.clientX + 14;
        tip.style.left = `${left + window.scrollX}px`;
        tip.style.top = `${ev.clientY + window.scrollY - tip.offsetHeight - 10}px`;
      };
      const leave = () => { cross.setAttribute('visibility', 'hidden'); dots.setAttribute('visibility', 'hidden'); tip.style.display = 'none'; };
      hit.addEventListener('pointermove', move);
      hit.addEventListener('pointerdown', move);
      hit.addEventListener('pointerleave', leave);
      host.append(root);
    }

    function renderSeriesTable(series) {
      const rows = [];
      for (const [account, pts] of Object.entries(series)) for (const p of pts) rows.push([Number(account), p]);
      rows.sort((a, b) => b[1][0] - a[1][0]);
      if (!rows.length) { $('series-table').replaceChildren(el('div', { class: 'empty' }, 'Sem amostras.')); return; }
      $('series-table').replaceChildren(el('table', null,
        el('thead', null, el('tr', null, el('th', null, 'Horário'), el('th', null, 'Conta'), el('th', { class: 'n' }, 'XP/h'),
          el('th', { class: 'n' }, 'Loot/h'), el('th', { class: 'n' }, 'Lucro/h'))),
        el('tbody', null, rows.slice(0, 300).map(([account, p]) => el('tr', null,
          el('td', null, dateTime(p[0])), el('td', null, (lastAccounts[account] || {}).label || `Conta ${account + 1}`),
          el('td', { class: 'n' }, fmt(p[1])), el('td', { class: 'n' }, fmt(p[2])), el('td', { class: 'n' }, signed(p[3])))))));
    }

    function renderCharts() {
      if (!lastHistory) return;
      drawChart($('chart-xp'), lastHistory.series, 1);
      drawChart($('chart-profit'), lastHistory.series, 3);
      renderSeriesTable(lastHistory.series);
    }

    async function refreshHistory() {
      try { lastHistory = await getJSON(`/api/history?hours=${rangeHours}`); renderCharts(); } catch (_) {}
    }

    // ---- hunts table ----
    let lastHunts = [];
    const openDetails = new Set();
    async function refreshHunts() {
      try {
        const { hunts } = await getJSON('/api/hunts?limit=100');
        lastHunts = hunts;
        if (!hunts.length) { $('hunts').replaceChildren(el('div', { class: 'empty' }, 'Nenhuma hunt encerrada registrada ainda.')); return; }
        $('hunts').replaceChildren(el('table', null,
          el('thead', null, el('tr', null, ['Fim', 'Conta', 'Hunt', 'Personagens', 'Duração', 'Motivo'].map((h) => el('th', null, h)),
            ['Level', 'XP', 'XP/h', 'Loot', 'Supplies', 'Balance', 'Mortes'].map((h) => el('th', { class: 'n' }, h)))),
          el('tbody', null, hunts.flatMap((h) => [huntRow(h), huntDetail(h)]))));
      } catch (_) {}
    }

    function huntDetail(h) {
      const hours = num(h.elapsedSec) / 3600, bal = num(h.balance);
      const item = (k, v) => el('div', null, `${k}: `, el('b', null, v));
      const list = (o, n) => topKills(o, n).filter(([name]) => name.toLowerCase() !== 'gold coin').map(([m, c]) => `${m} ×${fmt(c)}`).join(' · ') || '—';
      const cells = [
        item('Lucro/h', hours ? signed(bal / hours) : '—'), item('Lucro/kill', num(h.killsTotal) ? signed(bal / num(h.killsTotal)) : '—'),
        item('Kills', fmt(h.killsTotal)), item('Kills/h', hours ? fmt(num(h.killsTotal) / hours) : '—'),
        item('Dano recebido', fmt(h.damageTaken)), item('Cura', fmt(h.healingDone)),
        item('Supplies/kill', orDash(ratio(h.suppliesGold, h.killsTotal), fmt)), item('Lucro/1k XP', orDash(perKXp(bal, h.xp), signed)),
        item('Cura ÷ recebido', orDash(ratio(h.healingDone, h.damageTaken), pct)),
        item('Mortes', num(h.deaths) ? `${fmt(h.deaths)}${h.deathCause ? ` (${h.deathCause})` : ''}` : '0'),
        item('Personagens', (h.characters || []).join(', ') || '—'),
      ];
      const members = (h.members || []).filter((m) => num(m.suppliesGold) > 0);
      const spent = members.reduce((sum, m) => sum + num(m.suppliesGold), 0);
      let setupBtn = null;
      if (h.hasSetup) {
        setupBtn = el('button', { class: 'pr-btn', type: 'button', style: { marginTop: '8px' } }, 'Setup desta hunt / comparar com outra');
        setupBtn.addEventListener('click', (e) => { e.stopPropagation(); openSetup(h); });
      }
      const tr = el('tr', { class: 'detail' }, el('td', { colspan: '13' }, el('div', { class: 'detail-grid' }, cells),
        spent > 0 ? el('div', { style: { marginTop: '6px' } }, 'Supplies por membro: ' + members.slice().sort((x, y) => num(y.suppliesGold) - num(x.suppliesGold))
          .map((m) => `${vocation(m.vocation)} ${Math.round(100 * num(m.suppliesGold) / spent)}% (${fmt(m.suppliesGold)})`).join(' · ')) : null,
        el('div', { style: { marginTop: '6px' } }, 'Mais abatidos: ' + list(h.kills, 6)),
        el('div', null, 'Drops: ' + list(h.drops, 12)), setupBtn));
      tr.hidden = !openDetails.has(h.id);
      h._detail = tr;
      return tr;
    }

    function huntRow(h) {
      const row = el('tr', { class: 'run', title: 'Clique para ver detalhes' },
            el('td', null, dateTime(h.endedAt)),
            el('td', null, el('span', { class: 'swatch', style: { background: SERIES[h.account] } }), h.label),
            el('td', null, h.huntTitle || (h.huntId ? `#${h.huntId}` : '—')),
            el('td', { class: 'clip' }, (h.characters || []).join(', ') || '—'),
            el('td', null, duration(num(h.elapsedSec) * 1000)),
            el('td', null, REASONS[h.reason] || h.reason || '—'),
            el('td', { class: 'n' }, h.level ? (h.level.end > h.level.start ? `${h.level.start}→${h.level.end}` : h.level.end) : '—'),
            el('td', { class: 'n' }, fmt(h.xp)), el('td', { class: 'n' }, fmt(h.xpPerHour)),
            el('td', { class: 'n' }, fmt(h.lootGold)), el('td', { class: 'n' }, fmt(h.suppliesGold)),
            el('td', { class: 'n ' + (num(h.balance) >= 0 ? 'pos' : 'neg') }, signed(h.balance)),
            el('td', { class: 'n' }, fmt(h.deaths)));
      row.addEventListener('click', () => {
        h._detail.hidden = !h._detail.hidden;
        if (h._detail.hidden) openDetails.delete(h.id); else openDetails.add(h.id);
      });
      return row;
    }

    // ---- battle setup of a finished hunt, and what changed since another one ----
    let setupRun = null, setupCompare = null;
    const runLabel = (h) => `${dateTime(h.endedAt)} · ${h.label} · ${h.huntTitle || `#${h.huntId}`} · ${signed(num(h.elapsedSec) ? num(h.balance) / (num(h.elapsedSec) / 3600) : 0)}/h`;
    function openSetup(h) {
      setupRun = h;
      // Default: the previous hunt of the same account on the same map, else the previous one on that map.
      const older = lastHunts.filter((x) => x.hasSetup && x.id !== h.id && x.endedAt < h.endedAt);
      const pick = older.find((x) => x.account === h.account && x.huntId === h.huntId) || older.find((x) => x.huntId === h.huntId) || null;
      setupCompare = pick ? pick.id : null;
      $('setup-modal').classList.add('open');
      renderSetup();
    }
    async function renderSetup() {
      const h = setupRun;
      if (!h) return;
      $('setup-title').textContent = `Setup · ${h.label} · ${h.huntTitle || `#${h.huntId}`}`;
      const picker = el('select', { class: 'pr-input', 'aria-label': 'Comparar com' }, el('option', { value: '' }, 'Não comparar'),
        lastHunts.filter((x) => x.hasSetup && x.id !== h.id).map((x) => el('option', { value: String(x.id) }, runLabel(x))));
      picker.value = setupCompare === null ? '' : String(setupCompare);
      picker.addEventListener('change', () => { setupCompare = picker.value ? Number(picker.value) : null; renderSetup(); });
      const head = el('div', { class: 'pr-section' }, el('div', { class: 'madvice' }, `Esta hunt: ${runLabel(h)}`),
        el('div', { class: 'pr-row' }, el('span', null, 'Comparar com'), picker));
      $('setup-body').replaceChildren(head, el('div', { class: 'empty' }, 'Carregando…'));
      let data;
      try { data = await getJSON(`/api/hunts/setup?id=${h.id}${setupCompare === null ? '' : `&compare=${setupCompare}`}`); }
      catch (_) { data = { error: 'Falha ao carregar.' }; }
      if (setupRun !== h) return;
      const parts = [];
      if (data.error) parts.push(el('div', { class: 'pr-msg bad' }, data.error));
      for (const v of data.vocations || []) {
        const box = el('div', { class: 'sk-member' }, el('div', { class: 'sk-top' }, el('b', null, v.label)));
        if (data.compared) {
          const diff = v.differences || [];
          box.append(el('div', { class: 'sk-note ' + (diff.length ? 'warn' : '') }, diff.length
            ? el('div', null, el('b', null, 'O que mudou em relação à outra hunt'), el('ul', { style: { margin: '4px 0 0', paddingLeft: '18px' } }, diff.map((d) => el('li', null, d))))
            : 'Igual à outra hunt.'));
        }
        if ((v.steps || []).length) box.append(el('ol', { style: { margin: '8px 0 0', paddingLeft: '20px', fontSize: '12px' } }, v.steps.map((x) => el('li', null, x))));
        parts.push(box);
      }
      parts.push(el('div', { class: 'sk-foot' }, 'O setup é o que o app leu ao abrir o jogo ou retomar a hunt. Se você mudou a configuração no meio da hunt sem recarregar o jogo, a mudança não aparece aqui.'));
      $('setup-body').replaceChildren(head, ...parts);
    }
    const closeSetup = () => { setupRun = null; $('setup-modal').classList.remove('open'); };
    $('setup-close').addEventListener('click', closeSetup);
    $('setup-modal').addEventListener('click', (e) => { if (e.target === $('setup-modal')) closeSetup(); });

    // ---- yield by level on one map: one dot per finished hunt ----
    const LEVEL_METRICS = {
      profit: ['Lucro por hora', (h, hours) => num(h.balance) / hours, signed],
      supplies: ['Supplies por hora', (h, hours) => num(h.suppliesGold) / hours, fmt],
      xp: ['XP por hora', (h, hours) => num(h.xp) / hours, fmt],
      kills: ['Kills por hora', (h, hours) => num(h.killsTotal) / hours, fmt],
    };
    let levelRuns = [];
    async function refreshLevels() {
      try {
        const { hunts } = await getJSON('/api/hunts?limit=500');
        levelRuns = hunts.filter((h) => num(h.elapsedSec) >= 1800 && h.level && h.huntId != null);
        const hours = new Map(), titles = new Map();
        for (const h of levelRuns) {
          hours.set(h.huntId, (hours.get(h.huntId) || 0) + num(h.elapsedSec) / 3600);
          titles.set(h.huntId, h.huntTitle || `#${h.huntId}`);
        }
        const select = $('level-hunt');
        let keep = select.value;
        if (!keep) { try { keep = localStorage.getItem('levelHunt') || ''; } catch (_) {} }
        const order = [...hours.entries()].sort((a, b) => b[1] - a[1]);
        select.replaceChildren(...order.map(([id, h]) => el('option', { value: String(id) }, `${titles.get(id)} (${h.toFixed(0)}h)`)));
        if (order.some(([id]) => String(id) === keep)) select.value = keep;
        renderLevels();
      } catch (_) {}
    }
    function renderLevels() {
      const host = $('chart-level');
      host.querySelector('svg')?.remove();
      host.querySelector('.empty')?.remove();
      const huntId = Number($('level-hunt').value);
      const [title, value, format] = LEVEL_METRICS[$('level-metric').value] || LEVEL_METRICS.profit;
      $('level-title').textContent = `${title} em cada hunt encerrada, pelo nível`;
      const points = levelRuns.filter((h) => h.huntId === huntId).map((h) => {
        const hours = num(h.elapsedSec) / 3600;
        return { h, hours, level: (num(h.level.start || h.level.end) + num(h.level.end)) / 2, v: value(h, hours) };
      });
      const accounts = [...new Set(points.map((p) => p.h.account))].sort();
      $('level-legend').replaceChildren(...accounts.map((i) => el('span', null,
        el('span', { class: 'swatch', style: { background: SERIES[i], borderRadius: '50%' } }), (lastAccounts[i] || {}).label || `Conta ${i + 1}`)));
      $('level-table').replaceChildren(points.length ? el('table', null,
        el('thead', null, el('tr', null, el('th', null, 'Fim'), el('th', null, 'Conta'), el('th', { class: 'n' }, 'Nível'), el('th', { class: 'n' }, 'Horas'), el('th', { class: 'n' }, title))),
        el('tbody', null, points.slice().sort((a, b) => a.level - b.level).map((p) => el('tr', null, el('td', null, dateTime(p.h.endedAt)), el('td', null, p.h.label),
          el('td', { class: 'n' }, p.level.toLocaleString('pt-BR')), el('td', { class: 'n' }, p.hours.toFixed(1)), el('td', { class: 'n' }, format(p.v))))))
        : el('div', { class: 'empty' }, 'Sem hunts.'));
      if (!points.length) { host.append(el('div', { class: 'empty' }, 'Ainda sem hunts de 30+ min encerradas nesta hunt.')); return; }
      const W = Math.max(host.clientWidth, 300), H = 240, L = 56, R = 16, T = 12, B = 30;
      let x0 = Math.min(...points.map((p) => p.level)), x1 = Math.max(...points.map((p) => p.level));
      if (x1 - x0 < 4) { x0 -= 2; x1 += 2; }
      let lo = Math.min(0, ...points.map((p) => p.v)), hi = Math.max(0, ...points.map((p) => p.v));
      const step = niceStep(Math.max(hi - lo, 1));
      hi = Math.max(Math.ceil(hi / step) * step, step); lo = Math.floor(lo / step) * step;
      const pad = (x1 - x0) * 0.04;
      x0 -= pad; x1 += pad;
      const x = (v) => L + (v - x0) / (x1 - x0) * (W - L - R);
      const y = (v) => T + (hi - v) / (hi - lo) * (H - T - B);
      const root = svg('svg', { viewBox: `0 0 ${W} ${H}`, role: 'img', 'aria-label': $('level-title').textContent, style: { height: `${H}px` } });
      const axis = svg('g', { class: 'axis' });
      for (let v = lo; v <= hi + step / 2; v += step) {
        axis.append(svg('line', { x1: L, x2: W - R, y1: y(v), y2: y(v), stroke: Math.abs(v) < step / 2 ? 'var(--axis)' : 'var(--grid)', 'stroke-width': 1 }));
        const label = svg('text', { x: L - 8, y: y(v) + 4, 'text-anchor': 'end' }); label.textContent = axisFmt(v); axis.append(label);
      }
      const levelStep = Math.max(1, Math.ceil((x1 - x0) / 8));
      for (let v = Math.ceil(x0 / levelStep) * levelStep; v <= x1; v += levelStep) {
        const label = svg('text', { x: x(v), y: H - 10, 'text-anchor': 'middle' }); label.textContent = String(v); axis.append(label);
      }
      const caption = svg('text', { x: W - R, y: H - 10, 'text-anchor': 'end' }); caption.textContent = 'nível'; axis.append(caption);
      root.append(axis);
      const maxHours = Math.max(...points.map((p) => p.hours));
      const tip = $('tip');
      for (const p of points.slice().sort((a, b) => b.hours - a.hours)) {
        const r = 4 + 5 * Math.sqrt(p.hours / maxHours);
        const dot = svg('circle', { cx: x(p.level), cy: y(p.v), r, fill: SERIES[p.h.account], stroke: 'var(--surface)', 'stroke-width': 2, 'fill-opacity': 0.9 });
        // A larger invisible target than the dot, for touch and small marks.
        const hit = svg('circle', { cx: x(p.level), cy: y(p.v), r: Math.max(r, 12), fill: 'transparent' });
        const show = (ev) => {
          tip.replaceChildren(el('div', { class: 't' }, dateTime(p.h.endedAt)),
            el('div', { class: 'r' }, el('span', { class: 'swatch', style: { background: SERIES[p.h.account] } }), p.h.label, el('b', null, `${format(p.v)}/h`)),
            el('div', { class: 'r' }, 'Nível', el('b', null, p.h.level.start !== p.h.level.end ? `${p.h.level.start}→${p.h.level.end}` : String(p.h.level.end))),
            el('div', { class: 'r' }, 'Duração', el('b', null, duration(p.hours * 3600000))));
          tip.style.display = 'block';
          const left = ev.clientX + 14 + tip.offsetWidth > window.innerWidth ? ev.clientX - tip.offsetWidth - 14 : ev.clientX + 14;
          tip.style.left = `${left + window.scrollX}px`;
          tip.style.top = `${ev.clientY + window.scrollY - tip.offsetHeight - 10}px`;
          dot.setAttribute('stroke', 'var(--ink)');
        };
        const hide = () => { tip.style.display = 'none'; dot.setAttribute('stroke', 'var(--surface)'); };
        hit.addEventListener('pointermove', show);
        hit.addEventListener('pointerdown', show);
        hit.addEventListener('pointerleave', hide);
        root.append(dot, hit);
      }
      host.append(root);
    }
    $('level-hunt').addEventListener('change', () => { try { localStorage.setItem('levelHunt', $('level-hunt').value); } catch (_) {} renderLevels(); });
    $('level-metric').addEventListener('change', renderLevels);

    // ---- daily totals ----
    async function refreshDaily() {
      try {
        const { days } = await getJSON('/api/daily?days=14');
        if (!days.length) { $('daily').replaceChildren(el('div', { class: 'empty' }, 'Sem dados ainda.')); return; }
        const maxHunted = Math.max(1, ...days.map((d) => d.total.huntedSeconds));
        $('daily').replaceChildren(el('table', null,
          el('thead', null, el('tr', null, el('th', null, 'Dia'), el('th', null, 'Tempo caçado'), el('th', null, 'Por conta (horas caçadas)'),
            ['XP', 'Lucro', 'Kills', 'Hunts', 'Mortes'].map((h) => el('th', { class: 'n' }, h)))),
          el('tbody', null, days.map((d) => el('tr', null,
            el('td', null, d.date.split('-').reverse().slice(0, 2).join('/')),
            el('td', null, el('span', { class: 'hbar', style: { width: `${Math.max(2, 70 * d.total.huntedSeconds / maxHunted)}px` } }), ' ', duration(d.total.huntedSeconds * 1000)),
            el('td', null, lastAccounts.map((a) => {
              const c = d.accounts[String(a.index)];
              return el('span', { style: { marginRight: '10px' } }, el('span', { class: 'swatch', style: { background: SERIES[a.index] } }),
                c ? `${(c.huntedSeconds / 3600).toFixed(1)}h` : '0h');
            })),
            el('td', { class: 'n' }, fmt(d.total.xp)), el('td', { class: 'n ' + (d.total.balance >= 0 ? 'pos' : 'neg') }, signed(d.total.balance)),
            el('td', { class: 'n' }, fmt(d.total.kills)), el('td', { class: 'n' }, fmt(d.total.runs)), el('td', { class: 'n' }, fmt(d.total.deaths)))))));
      } catch (_) {}
    }

    // ---- hunt ranking ----
    let rankingData = null;
    function renderRanking() {
      if (!rankingData) return;
      const account = $('rank-account').value, sort = $('rank-sort').value;
      const rows = rankingData.rows.filter((r) => String(r.account === null ? 'all' : r.account) === account)
        .sort((a, b) => b[sort] - a[sort]);
      if (!rows.length) { $('ranking').replaceChildren(el('div', { class: 'empty' }, `Ainda sem hunts de ${rankingData.minMinutes}+ min para comparar.`)); return; }
      $('ranking').replaceChildren(el('table', null,
        el('thead', null, el('tr', null, el('th', null, '#'), el('th', null, 'Hunt'),
          ['Hunts', 'Horas', 'XP/h', 'Lucro/h', 'Kills/h', 'Mortes'].map((h) => el('th', { class: 'n' }, h)))),
        el('tbody', null, rows.slice(0, 30).map((r, i) => el('tr', null, el('td', null, String(i + 1)), el('td', null, r.title),
          el('td', { class: 'n' }, fmt(r.runs)), el('td', { class: 'n' }, r.hours.toFixed(1)), el('td', { class: 'n' }, fmt(r.xpPerHour)),
          el('td', { class: 'n ' + (r.profitPerHour >= 0 ? 'pos' : 'neg') }, signed(r.profitPerHour)),
          el('td', { class: 'n' }, fmt(r.killsPerHour)), el('td', { class: 'n' }, fmt(r.deaths)))))));
    }
    async function refreshRanking() {
      try {
        rankingData = await getJSON('/api/ranking');
        const select = $('rank-account'), keep = select.value || 'all';
        select.replaceChildren(el('option', { value: 'all' }, 'Todas as contas'),
          ...lastAccounts.map((a) => el('option', { value: String(a.index) }, a.label)));
        select.value = keep;
        renderRanking();
      } catch (_) {}
    }
    $('rank-account').addEventListener('change', renderRanking);
    $('rank-sort').addEventListener('change', renderRanking);

    // ---- controls ----
    $('range').addEventListener('click', (ev) => {
      const b = ev.target.closest('button'); if (!b) return;
      rangeHours = Number(b.dataset.h);
      $('csv-history').href = `/api/history.csv?hours=${rangeHours}`;
      for (const x of $('range').children) x.setAttribute('aria-pressed', String(x === b));
      try { localStorage.setItem('range', String(rangeHours)); } catch (_) {}
      refreshHistory();
    });
    $('theme').addEventListener('click', () => {
      const dark = document.documentElement.dataset.theme
        ? document.documentElement.dataset.theme === 'dark'
        : matchMedia('(prefers-color-scheme: dark)').matches;
      document.documentElement.dataset.theme = dark ? 'light' : 'dark';
      try { localStorage.setItem('theme', document.documentElement.dataset.theme); } catch (_) {}
    });
    try {
      const theme = localStorage.getItem('theme'); if (theme) document.documentElement.dataset.theme = theme;
      const saved = Number(localStorage.getItem('range'));
      const button = [...$('range').children].find((b) => Number(b.dataset.h) === saved);
      if (button) button.click();
    } catch (_) {}
    let resizeTimer;
    addEventListener('resize', () => { clearTimeout(resizeTimer); resizeTimer = setTimeout(() => { renderCharts(); renderLevels(); }, 150); });

    refreshState().then(() => { refreshHistory(); refreshHunts(); refreshDaily(); refreshRanking(); refreshLevels(); });
    setInterval(refreshState, 3000);
    setInterval(refreshHistory, 60000);
    setInterval(refreshHunts, 30000);
    setInterval(() => { refreshDaily(); refreshRanking(); refreshLevels(); }, 60000);
    </script>
    </body>
    </html>
    """#
}
