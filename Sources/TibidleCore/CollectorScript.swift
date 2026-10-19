/// Read-only collector injected into the game page.
///
/// It observes only messages the game *receives* on its own WebSocket and forwards a
/// whitelisted subset of hunt fields to the app. It never sends anything, never touches
/// outgoing messages (where authentication travels) and drops every field not listed here,
/// including the session token present in `welcome`/`resume`.
public enum CollectorScript {
    public static let handlerName = "tibidleDashboard"

    public static let source = #"""
    (() => {
      'use strict';
      if (location.hostname !== 'play.tibidle.com' || window.__tibidleDashboard) return;
      window.__tibidleDashboard = true;

      const HANDLER = 'tibidleDashboard';
      const FRAME_INTERVAL_MS = 3000;
      const MAX_MESSAGE = 2000000;

      const ANALYZER = ['elapsedMs', 'sessionElapsedMs', 'xp', 'xpPerHour', 'kills', 'killsTotal', 'damageDealt',
                        'damageTaken', 'healingDone', 'lootGold', 'suppliesGold', 'drops'];
      const CHARACTER = ['name', 'vocation', 'level', 'hp', 'maxHp', 'mana', 'maxMana', 'xp', 'gold'];
      const MEMBER = ['name', 'vocation', 'level', 'hp', 'maxHp', 'mana', 'maxMana', 'suppliesGold'];
      const ACCOUNT = ['name', 'level', 'xp', 'gold', 'coins', 'mainVocation'];
      const SUMMARY = ['huntId', 'reason', 'elapsedSec', 'level', 'xp', 'xpPerHour', 'lootGold', 'suppliesGold',
                       'balance', 'kills', 'killsTotal', 'damageDealt', 'damageTaken', 'healingDone', 'drops',
                       'deaths', 'deathCause'];
      const OFFLINE = ['elapsedMs', 'xp', 'killsTotal', 'lootGold'];
      const TASK = ['id', 'title', 'kind', 'quantity', 'progresso', 'resgatado'];
      const REWARD = ['kind', 'name', 'amount', 'percent'];

      const isObject = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);
      const pick = (o, keys) => {
        if (!isObject(o)) return undefined;
        const out = {};
        for (const k of keys) if (o[k] !== undefined) out[k] = o[k];
        return out;
      };
      const pickList = (list, keys) => Array.isArray(list) ? list.slice(0, 4).map((o) => pick(o, keys)) : undefined;
      const num = (v) => typeof v === 'number' && isFinite(v) ? v : undefined;
      // Combat numbers only (skill levels, equipped spell names/cooldowns, weapon attack): no items or ids.
      const weaponAttack = (eq) => {
        const w = isObject(eq) ? eq.weapon : undefined;
        if (!isObject(w)) return undefined;
        return num(isObject(w.attrs) ? w.attrs.attack : undefined) ?? num(w.attack);
      };
      const member = (m) => {
        if (!isObject(m)) return undefined;
        const out = pick(m, MEMBER);
        const sk = isObject(m.skills) ? m.skills : {};
        out.skillLevels = {
          melee: num(isObject(sk.melee) ? sk.melee.value : undefined), distance: num(isObject(sk.distance) ? sk.distance.value : undefined),
          magic: num(isObject(sk.magic) ? sk.magic.value : undefined),
        };
        out.weaponAttack = weaponAttack(m.equipment);
        out.kit = Array.isArray(m.kit) ? m.kit.slice(0, 24).map((k) => pick(k, ['name', 'mana', 'cooldownMs'])) : [];
        return out;
      };
      const BATTLE = (c) => {
        if (!isObject(c)) return undefined;
        const out = {};
        for (const voc of Object.keys(c).slice(0, 6)) {
          const b = c[voc];
          if (!isObject(b)) continue;
          out[voc] = {
            skills: Array.isArray(b.skills) ? b.skills.slice(0, 12).map((x) => typeof x === 'string' ? x : null) : [],
            minCreatures: isObject(b.minCreatures) ? Object.fromEntries(Object.entries(b.minCreatures).filter(([, v]) => typeof v === 'number').slice(0, 16)) : {},
          };
        }
        return out;
      };
      const state = (s) => isObject(s) ? {
        character: pick(s.character, CHARACTER),
        party: Array.isArray(s.party) ? s.party.slice(0, 4).map(member) : undefined,
        balance: typeof s.balance === 'number' ? s.balance : undefined,
        cap: pick(s.cap, ['used', 'total']),
        tower: pick(s.tower, ['floor', 'cleared', 'mode']),
        keyBagUsed: s.keyBagUsed,
        keyBagMax: s.keyBagMax,
        keyClock: pick(s.keyClock, ['tierMs', 'everyMs']),
      } : undefined;

      const strings = (list) => Array.isArray(list) ? list.filter((v) => typeof v === 'string').slice(0, 8) : [];
      const task = (t) => isObject(t) ? Object.assign(pick(t, TASK), {
        targets: strings(t.targets),
        rewards: Array.isArray(t.rewards) ? t.rewards.slice(0, 6).map((r) => pick(r, REWARD)) : [],
      }) : null;
      const DAY = ['day', 'estado'];
      const WEEKLY = ['id', 'progresso', 'meta'];
      const streak = (q) => isObject(q) ? Object.assign(pick(q, ['diaAtual', 'terminaEm', 'fechados', 'custoRecuperar']), {
        dias: Array.isArray(q.dias) ? q.dias.slice(0, 7).map((d) => pick(d, DAY)) : [],
      }) : undefined;
      // Missions, streak and weekly goals only; the login calendar and every prize/item id are dropped.
      const eventos = (e) => isObject(e) ? {
        serverDay: e.serverDay,
        nextDailyResetAt: e.nextDailyResetAt,
        diarias: isObject(e.diarias) && Array.isArray(e.diarias.slots) ? { slots: e.diarias.slots.slice(0, 2).map(task) } : undefined,
        semanais: isObject(e.semanais) ? Object.assign(pick(e.semanais, ['concluidas', 'necessarias']), {
          tarefas: Array.isArray(e.semanais.tarefas) ? e.semanais.tarefas.slice(0, 8).map((t) => pick(t, WEEKLY)) : [],
        }) : undefined,
        sequencia: streak(e.sequencia),
        resgataveis: pick(e.resgataveis, ['login', 'diarias', 'sequencia', 'semanais', 'total']),
      } : undefined;
      // Invasion schedule only (when it opens, whether the player joined); no rewards or rankings.
      const invasao = (v) => isObject(v) ? Object.assign(pick(v, ['date', 'invasionNome', 'bossName', 'inscrito', 'encerrada', 'proximaIdx']), {
        janelas: Array.isArray(v.janelas) ? v.janelas.slice(0, 6).map((j) => pick(j, ['idx', 'startAtMs', 'estado', 'cancelada'])) : [],
      }) : undefined;
      const progress = (p) => isObject(p) ? {
        dia: isObject(p.dia) ? {
          serverDay: p.dia.serverDay,
          slots: Array.isArray(p.dia.slots) ? p.dia.slots.slice(0, 2).map((x) => pick(x, ['taskId', 'exibido'])) : [],
        } : undefined,
        semana: pick(p.semana, ['monstros']),
      } : undefined;

      const post = (type, data) => {
        try { window.webkit.messageHandlers[HANDLER].postMessage(JSON.stringify({ type, data: data || {} })); } catch (_) {}
      };

      const project = {
        welcome: (d) => ({ account: pick(d.account, ACCOUNT), roster: pickList(d.roster, CHARACTER), eventos: eventos(d.eventos),
                           invasao: invasao(isObject(d.meta) ? d.meta.invasao : undefined), battleConfigs: BATTLE(d.battleConfigs) }),
        invasion_update: (d) => ({ invasao: invasao(d.invasao) }),
        eventos_state: (d) => ({ eventos: eventos(d) }),
        eventos_result: (d) => ({ eventos: eventos(d.state) }),
        resume: (d) => ({ huntId: d.huntId, battleConfigs: BATTLE(d.battleConfigs), state: state(d.state), analyzer: pick(d.analyzer, ANALYZER),
                          offline: pick(d.offline, OFFLINE), training: d.training === true }),
        hunt_started: (d) => ({ huntId: d.huntId, state: state(d.state), training: d.training === true }),
        frame: (d) => ({ state: state(d.state), analyzer: pick(d.analyzer, ANALYZER), eventosProgresso: progress(d.eventosProgresso) }),
        ended: (d) => ({ summary: pick(d.summary, SUMMARY) }),
        session_takeover: () => ({}),
        session_replaced: () => ({}),
      };

      let lastFrame = 0;
      const handle = (raw) => {
        if (typeof raw !== 'string' || raw.length > MAX_MESSAGE) return;
        // The server writes {"type":"...", ...}; skip unrelated messages without parsing them.
        const head = /^\{"type":"([a-z_]+)"/.exec(raw);
        if (head && !project[head[1]]) return;
        if (head && head[1] === 'frame' && Date.now() - lastFrame < FRAME_INTERVAL_MS) return;
        let message;
        try { message = JSON.parse(raw); } catch (_) { return; }
        if (!isObject(message) || !project[message.type] || !isObject(message.data)) return;
        if (message.type === 'frame') {
          if (Date.now() - lastFrame < FRAME_INTERVAL_MS) return;
          lastFrame = Date.now();
        }
        post(message.type, project[message.type](message.data));
      };

      const Native = window.WebSocket;
      if (typeof Native !== 'function') return;
      const watch = (socket, url) => {
        try {
          if (!/(^|\.)tibidle\.com$/.test(new URL(url, location.href).hostname)) return;
          socket.addEventListener('message', (event) => { try { handle(event.data); } catch (_) {} });
          socket.addEventListener('close', () => post('_closed'));
        } catch (_) {}
      };
      const Wrapped = function WebSocket(url, protocols) {
        const socket = protocols === undefined ? new Native(url) : new Native(url, protocols);
        watch(socket, url);
        return socket;
      };
      Wrapped.prototype = Native.prototype;
      for (const key of ['CONNECTING', 'OPEN', 'CLOSING', 'CLOSED']) {
        Object.defineProperty(Wrapped, key, { value: Native[key] });
      }
      window.WebSocket = Wrapped;
    })();
    """#
}
