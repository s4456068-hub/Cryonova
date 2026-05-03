// ════════════════════════════════════════════════════════════════════
//  Cryonova — Cloudflare Worker
//  Endpoints: /register, /load
//  Storage  : KV namespace `CRYONOVA_KV` bound in wrangler.toml
//  Secret   : env.SCRIPT_PAYLOAD  → encrypted/plain Lua to deliver
//             env.ADMIN_TOKEN     → optional, for /admin endpoints
// ════════════════════════════════════════════════════════════════════

const json = (obj, status = 200) =>
    new Response(JSON.stringify(obj), {
        status,
        headers: {
            'content-type': 'application/json; charset=utf-8',
            'access-control-allow-origin': '*',
        },
    });

const text = (body, status = 200) =>
    new Response(body, {
        status,
        headers: {
            'content-type': 'text/plain; charset=utf-8',
            'access-control-allow-origin': '*',
        },
    });

// ── helpers ─────────────────────────────────────────────────────────

async function parseBody(request) {
    const url = new URL(request.url);
    if (request.method === 'GET') {
        return Object.fromEntries(url.searchParams.entries());
    }
    const ct = request.headers.get('content-type') || '';
    if (ct.includes('application/json')) {
        try { return await request.json(); } catch { return {}; }
    }
    if (ct.includes('application/x-www-form-urlencoded')) {
        const raw = await request.text();
        return Object.fromEntries(new URLSearchParams(raw));
    }
    return Object.fromEntries(url.searchParams.entries());
}

async function sha256Hex(input) {
    const data = new TextEncoder().encode(input);
    const buf = await crypto.subtle.digest('SHA-256', data);
    return [...new Uint8Array(buf)]
        .map(b => b.toString(16).padStart(2, '0'))
        .join('');
}

function timingSafeEqual(a, b) {
    if (typeof a !== 'string' || typeof b !== 'string' || a.length !== b.length) {
        return false;
    }
    let r = 0;
    for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i);
    return r === 0;
}

function userKey(username) {
    return 'user:' + username.toLowerCase();
}

function licenseKey(license) {
    return 'license:' + license;
}

// ── /register ───────────────────────────────────────────────────────
// Body: username, password, license, hwid (steam64), fingerprint
//  - License must exist in KV under  license:<key>  with { used: false }
//  - Once consumed it is bound to this user + hwid + fingerprint
async function handleRegister(req, env) {
    const body = await parseBody(req);
    const username    = (body.username    || '').trim();
    const password    = (body.password    || '').trim();
    const license     = (body.license     || '').trim();
    const hwid        = (body.hwid        || '').trim();
    const fingerprint = (body.fingerprint || '').trim();

    if (!username || !password || !license || !hwid) {
        return json({ ok: false, error: 'missing fields' }, 400);
    }
    if (username.length > 32 || password.length > 64) {
        return json({ ok: false, error: 'fields too long' }, 400);
    }

    const existingUser = await env.CRYONOVA_KV.get(userKey(username), 'json');
    if (existingUser) {
        return json({ ok: false, error: 'user already exists' }, 409);
    }

    const lic = await env.CRYONOVA_KV.get(licenseKey(license), 'json');
    if (!lic) {
        return json({ ok: false, error: 'invalid license' }, 403);
    }
    if (lic.used) {
        return json({ ok: false, error: 'license already used' }, 403);
    }

    const password_hash = await sha256Hex(password + ':' + username.toLowerCase());

    const userRecord = {
        username,
        password_hash,
        license,
        hwid,                    // steam64
        fingerprint,             // machine fingerprint
        created_at: Date.now(),
        last_seen:  Date.now(),
        banned: false,
    };

    await env.CRYONOVA_KV.put(userKey(username), JSON.stringify(userRecord));
    await env.CRYONOVA_KV.put(licenseKey(license), JSON.stringify({
        ...lic,
        used: true,
        bound_to: username.toLowerCase(),
        bound_at: Date.now(),
    }));

    return json({ ok: true });
}

// Chunk size: gamesense/http silently drops responses > ~64 KB.
// 32 KB is well under that ceiling and keeps round-trip count low.
const CHUNK_SIZE = 32 * 1024;

async function authenticate(env, body) {
    const username    = (body.username    || '').trim();
    const password    = (body.password    || '').trim();
    const hwid        = (body.hwid        || '').trim();
    const fingerprint = (body.fingerprint || '').trim();

    if (!username || !password || !hwid) {
        return { error: 'missing fields', status: 400 };
    }
    const user = await env.CRYONOVA_KV.get(userKey(username), 'json');
    if (!user) return { error: 'unknown user', status: 403 };
    if (user.banned) return { error: 'banned', status: 403 };

    const password_hash = await sha256Hex(password + ':' + username.toLowerCase());
    if (!timingSafeEqual(password_hash, user.password_hash)) {
        return { error: 'wrong password', status: 403 };
    }
    if (!timingSafeEqual(user.hwid, hwid)) {
        return { error: 'hwid mismatch (steam64)', status: 403 };
    }
    if (user.fingerprint && fingerprint &&
        !timingSafeEqual(user.fingerprint, fingerprint)) {
        return { error: 'hwid mismatch (machine)', status: 403 };
    }

    user.last_seen = Date.now();
    await env.CRYONOVA_KV.put(userKey(username), JSON.stringify(user));
    return { user };
}

async function getPayload(env) {
    let payload = env.SCRIPT_PAYLOAD;
    if (!payload) payload = await env.CRYONOVA_KV.get('payload:current');
    return payload || null;
}

// ── /load ───────────────────────────────────────────────────────────
// Authenticates, returns chunked-session metadata:
//   { ok:true, session:'xyz', total:8, chunk_size:32768, bytes:240062 }
// The loader then calls /chunk?session=xyz&i=N for each i.
async function handleLoad(req, env) {
    const body = await parseBody(req);
    const auth = await authenticate(env, body);
    if (auth.error) return json({ ok: false, error: auth.error }, auth.status);

    const payload = await getPayload(env);
    if (!payload) return json({ ok: false, error: 'no payload configured' }, 500);

    const session = crypto.randomUUID().replace(/-/g, '');
    const total = Math.ceil(payload.length / CHUNK_SIZE);

    // Stash payload under session id so /chunk on a different worker
    // instance can still find it. Auto-expires in 5 min.
    await env.CRYONOVA_KV.put('session:' + session, payload, {
        expirationTtl: 300,
    });

    return json({
        ok: true,
        session,
        total,
        chunk_size: CHUNK_SIZE,
        bytes: payload.length,
    });
}

// ── /chunk ──────────────────────────────────────────────────────────
async function handleChunk(req, env) {
    const body = await parseBody(req);
    const session = (body.session || '').trim();
    const i = parseInt(body.i || '0', 10);

    if (!session || isNaN(i) || i < 0) {
        return json({ ok: false, error: 'bad chunk request' }, 400);
    }

    const payload = await env.CRYONOVA_KV.get('session:' + session);
    if (!payload) return json({ ok: false, error: 'session expired' }, 404);

    const start = i * CHUNK_SIZE;
    if (start >= payload.length) {
        return json({ ok: false, error: 'chunk out of range' }, 416);
    }
    const slice = payload.slice(start, start + CHUNK_SIZE);

    return new Response(slice, {
        status: 200,
        headers: {
            'content-type': 'text/plain; charset=utf-8',
            'access-control-allow-origin': '*',
            'cache-control': 'no-store',
        },
    });
}

// ── /admin/issue-license ────────────────────────────────────────────
// Mint a new license key. Auth: header `x-admin-token` == env.ADMIN_TOKEN.
async function handleIssueLicense(req, env) {
    if (!env.ADMIN_TOKEN ||
        req.headers.get('x-admin-token') !== env.ADMIN_TOKEN) {
        return json({ ok: false, error: 'forbidden' }, 403);
    }
    const body = await parseBody(req);
    const key = body.key || crypto.randomUUID().replace(/-/g, '').toUpperCase();
    await env.CRYONOVA_KV.put(licenseKey(key), JSON.stringify({
        used: false,
        created_at: Date.now(),
        note: body.note || '',
    }));
    return json({ ok: true, license: key });
}

// ── /admin/reset-hwid ───────────────────────────────────────────────
// Clear the hwid binding for a user (for legitimate hardware changes).
async function handleResetHwid(req, env) {
    if (!env.ADMIN_TOKEN ||
        req.headers.get('x-admin-token') !== env.ADMIN_TOKEN) {
        return json({ ok: false, error: 'forbidden' }, 403);
    }
    const body = await parseBody(req);
    const username = (body.username || '').trim();
    if (!username) return json({ ok: false, error: 'missing username' }, 400);

    const user = await env.CRYONOVA_KV.get(userKey(username), 'json');
    if (!user) return json({ ok: false, error: 'unknown user' }, 404);

    user.hwid = '';
    user.fingerprint = '';
    await env.CRYONOVA_KV.put(userKey(username), JSON.stringify(user));
    return json({ ok: true });
}

// ── router ──────────────────────────────────────────────────────────
export default {
    async fetch(request, env, ctx) {
        const url = new URL(request.url);

        if (request.method === 'OPTIONS') {
            return new Response(null, {
                headers: {
                    'access-control-allow-origin':  '*',
                    'access-control-allow-methods': 'GET, POST, OPTIONS',
                    'access-control-allow-headers': 'content-type, x-admin-token',
                },
            });
        }

        try {
            switch (url.pathname) {
                case '/':                    return text('cryonova');
                case '/register':            return handleRegister(request, env);
                case '/load':                return handleLoad(request, env);
                case '/chunk':               return handleChunk(request, env);
                case '/admin/issue-license': return handleIssueLicense(request, env);
                case '/admin/reset-hwid':    return handleResetHwid(request, env);
                default:                     return json({ ok: false, error: 'not found' }, 404);
            }
        } catch (err) {
            return json({ ok: false, error: 'server: ' + (err.message || err) }, 500);
        }
    },
};
