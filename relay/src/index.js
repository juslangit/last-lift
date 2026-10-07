// Last Lift relay. The game itself runs in the host player's browser and every other player
// connects straight to it over WebRTC. This worker only does what browsers can't do alone:
// hand out 4-digit room codes, find a Quickplay room, and pass the WebRTC offers, answers
// and ICE candidates between a joiner and the host while they set up that connection.
//
// One Durable Object ("global") holds every room. It uses WebSocket hibernation, so an idle
// lobby costs nothing; all state lives in each socket's attachment:
//   host: {role: "host", code, mode, name, ver, state, count, next}
//   peer: {role: "peer", code, id}

import { DurableObject } from "cloudflare:workers";

const MAX_PLAYERS = 12;
const QUICK_FULL = 8;
const STUN = [{ urls: ["stun:stun.cloudflare.com:3478", "stun:stun.l.google.com:19302"] }];

export default {
  async fetch(req, env) {
    const url = new URL(req.url);
    if (url.pathname === "/ws") {
      if (req.headers.get("Upgrade") !== "websocket") {
        return new Response("Expected a WebSocket", { status: 426 });
      }
      return env.LOBBY.get(env.LOBBY.idFromName("global")).fetch(req);
    }
    return new Response("Last Lift relay", { headers: { "content-type": "text/plain" } });
  },
};

export class Lobby extends DurableObject {
  async fetch(req) {
    const [client, server] = Object.values(new WebSocketPair());
    this.ctx.acceptWebSocket(server);
    server.serializeAttachment({ role: "none" });
    server.send(JSON.stringify({ t: "hello", ice: await this.iceServers() }));
    return new Response(null, { status: 101, webSocket: client });
  }

  // STUN always; Cloudflare TURN too when the worker has a TURN key (strict networks need it).
  async iceServers() {
    const env = this.env;
    if (!env.TURN_KEY_ID || !env.TURN_KEY_TOKEN) return STUN;
    if (this.turn && this.turn.until > Date.now()) return this.turn.servers;
    try {
      const r = await fetch(`https://rtc.live.cloudflare.com/v1/turn/keys/${env.TURN_KEY_ID}/credentials/generate-ice-servers`, {
        method: "POST",
        headers: { authorization: `Bearer ${env.TURN_KEY_TOKEN}`, "content-type": "application/json" },
        body: JSON.stringify({ ttl: 86400 }),
      });
      const j = await r.json();
      const servers = (j.iceServers || []).map((s) => ({
        urls: (Array.isArray(s.urls) ? s.urls : [s.urls]).filter((u) => !u.includes(":53")),
        username: s.username,
        credential: s.credential,
      }));
      this.turn = { servers: STUN.concat(servers), until: Date.now() + 12 * 3600 * 1000 };
      return this.turn.servers;
    } catch {
      return STUN;
    }
  }

  all() {
    return this.ctx.getWebSockets().map((ws) => ({ ws, a: ws.deserializeAttachment() || {} }));
  }

  hostOf(code) {
    return this.all().find((s) => s.a.role === "host" && s.a.code === code);
  }

  send(ws, msg) {
    try {
      ws.send(JSON.stringify(msg));
    } catch {}
  }

  newCode() {
    const used = new Set(this.all().filter((s) => s.a.role === "host").map((s) => s.a.code));
    for (let i = 0; i < 50; i++) {
      const c = String(1000 + Math.floor(Math.random() * 9000));
      if (!used.has(c)) return c;
    }
    return null;
  }

  join(ws, host) {
    if (host.a.count >= MAX_PLAYERS) {
      this.send(ws, { t: "error", why: "full" });
      return;
    }
    const id = host.a.next;
    host.a.next += 1;
    host.a.count += 1;
    host.ws.serializeAttachment(host.a);
    ws.serializeAttachment({ role: "peer", code: host.a.code, id });
    this.send(host.ws, { t: "peer", id });
    this.send(ws, { t: "joined", id, code: host.a.code, mode: host.a.mode, host: host.a.name });
  }

  async webSocketMessage(ws, raw) {
    let m;
    try {
      m = JSON.parse(raw);
    } catch {
      return;
    }
    const me = ws.deserializeAttachment() || {};
    switch (m.t) {
      case "host": {
        const code = this.newCode();
        if (!code) return this.send(ws, { t: "error", why: "busy" });
        ws.serializeAttachment({
          role: "host", code, mode: m.mode === "quick" ? "quick" : "code", name: String(m.name || "").slice(0, 16),
          ver: String(m.ver || ""), state: "lobby", count: 1, next: 2,
        });
        return this.send(ws, { t: "hosted", code });
      }
      case "join": {
        const host = this.hostOf(String(m.code || ""));
        if (!host || host.a.ver !== String(m.ver || "")) return this.send(ws, { t: "error", why: "no_room" });
        return this.join(ws, host);
      }
      case "quick": {
        // rooms still in their lobby first, then the fullest, so players gather together
        const rooms = this.all()
          .filter((s) => s.a.role === "host" && s.a.mode === "quick" && s.a.ver === String(m.ver || "") && s.a.count < QUICK_FULL)
          .sort((x, y) => (x.a.state === "lobby") !== (y.a.state === "lobby") ? (x.a.state === "lobby" ? -1 : 1) : y.a.count - x.a.count);
        if (rooms.length === 0) return this.send(ws, { t: "none" });
        return this.join(ws, rooms[0]);
      }
      case "signal": {
        if (me.role === "host") {
          const peer = this.all().find((s) => s.a.role === "peer" && s.a.code === me.code && s.a.id === m.to);
          if (peer) this.send(peer.ws, { t: "signal", from: 1, data: m.data });
        } else if (me.role === "peer") {
          const host = this.hostOf(me.code);
          if (host) this.send(host.ws, { t: "signal", from: me.id, data: m.data });
        }
        return;
      }
      case "state": {
        if (me.role !== "host") return;
        me.state = m.state === "playing" ? "playing" : "lobby";
        if (Number.isInteger(m.count)) me.count = Math.max(1, Math.min(MAX_PLAYERS, m.count));
        ws.serializeAttachment(me);
        return;
      }
      case "ping":
        return this.send(ws, { t: "pong" });
    }
  }

  async webSocketClose(ws) {
    this.gone(ws);
  }

  async webSocketError(ws) {
    this.gone(ws);
  }

  gone(ws) {
    const me = ws.deserializeAttachment() || {};
    if (me.role === "host") {
      for (const s of this.all()) {
        if (s.a.role === "peer" && s.a.code === me.code) this.send(s.ws, { t: "closed" });
      }
    } else if (me.role === "peer") {
      const host = this.hostOf(me.code);
      if (host) {
        host.a.count = Math.max(1, host.a.count - 1);
        host.ws.serializeAttachment(host.a);
        this.send(host.ws, { t: "gone", id: me.id });
      }
    }
    ws.serializeAttachment({ role: "none" });
  }
}
