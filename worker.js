export default {
  async fetch(request, env) {
    try {
      const url = new URL(request.url);

      if (request.method === "OPTIONS") {
        return cors(new Response(null, { status: 204 }));
      }

      if (url.pathname === "/register") {
        return cors(await register(request, env));
      }

      if (url.pathname === "/load") {
        return cors(await load(request, env));
      }

      if (url.pathname === "/load-meta") {
        return cors(await loadMeta(request, env));
      }

      if (url.pathname === "/load-chunk") {
        return cors(await loadChunk(request, env));
      }

      if (url.pathname === "/health") {
        return cors(json({ ok: true, name: "cryonova-worker", version: "raw-github-debug-v1" }));
      }

      if (url.pathname === "/debug-github") {
        return cors(await debugGithub(env));
      }

      return cors(json({ ok: false, error: "not found" }, 404));
    } catch (error) {
      return cors(json({ ok: false, error: "server error" }, 500));
    }
  }
};

async function readInput(request) {
  if (request.method === "GET") {
    return Object.fromEntries(new URL(request.url).searchParams.entries());
  }

  const contentType = request.headers.get("content-type") || "";
  if (contentType.includes("application/json")) {
    return await request.json();
  }

  const text = await request.text();
  return Object.fromEntries(new URLSearchParams(text).entries());
}

function clean(value) {
  return String(value || "").trim();
}

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store"
    }
  });
}

function text(data, status = 200) {
  return new Response(data, {
    status,
    headers: {
      "content-type": "text/plain; charset=utf-8",
      "cache-control": "no-store"
    }
  });
}

function cors(response) {
  const headers = new Headers(response.headers);
  headers.set("access-control-allow-origin", "*");
  headers.set("access-control-allow-methods", "GET,POST,OPTIONS");
  headers.set("access-control-allow-headers", "content-type");
  return new Response(response.body, { status: response.status, headers });
}

async function sha256(value) {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function matchesSecret(input, storedPlain, storedSha256) {
  if (storedSha256) {
    return (await sha256(input)) === storedSha256;
  }
  return storedPlain === input;
}

async function getJson(kv, key) {
  const raw = await kv.get(key);
  if (!raw) return null;
  return JSON.parse(raw);
}

function isExpired(user) {
  if (!user.expires_at) return false;
  return Date.now() > Date.parse(user.expires_at);
}

async function register(request, env) {
  const input = await readInput(request);
  const username = clean(input.username);
  const password = clean(input.password);
  const license = clean(input.license || input.key);
  const hwid = clean(input.hwid);

  if (!username || !password || !license) {
    return json({ ok: false, error: "missing fields" }, 400);
  }

  const userKey = `user:${username.toLowerCase()}`;
  const existingUser = await getJson(env.CRYONOVA_KV, userKey);
  if (existingUser) {
    return json({ ok: false, error: "user already exists" }, 409);
  }

  const licenseKey = `license:${license}`;
  const licenseData = await getJson(env.CRYONOVA_KV, licenseKey);
  if (!licenseData || licenseData.active !== true) {
    return json({ ok: false, error: "invalid license" }, 403);
  }
  if (licenseData.used_by) {
    return json({ ok: false, error: "license already used" }, 403);
  }

  const user = {
    password_sha256: await sha256(password),
    active: true,
    hwid,
    license,
    expires_at: licenseData.expires_at || null,
    created_at: new Date().toISOString()
  };

  licenseData.used_by = username;
  licenseData.used_at = new Date().toISOString();

  await env.CRYONOVA_KV.put(userKey, JSON.stringify(user));
  await env.CRYONOVA_KV.put(licenseKey, JSON.stringify(licenseData));

  return json({ ok: true });
}

async function authorize(request, env) {
  const input = await readInput(request);
  const username = clean(input.username);
  const password = clean(input.password);
  const hwid = clean(input.hwid);

  if (!username || !password) {
    return { ok: false, status: 400, error: "missing login or password" };
  }

  const user = await getJson(env.CRYONOVA_KV, `user:${username.toLowerCase()}`);
  if (!user || user.active !== true) {
    return { ok: false, status: 403, error: "access denied" };
  }

  if (isExpired(user)) {
    return { ok: false, status: 403, error: "subscription expired" };
  }

  if (!(await matchesSecret(password, user.password, user.password_sha256))) {
    return { ok: false, status: 403, error: "wrong password" };
  }

  if (user.hwid && hwid && user.hwid !== hwid) {
    return { ok: false, status: 403, error: "hwid mismatch" };
  }

  if (!user.hwid && hwid) {
    user.hwid = hwid;
    await env.CRYONOVA_KV.put(`user:${username.toLowerCase()}`, JSON.stringify(user));
  }

  return { ok: true, username };
}

async function load(request, env) {
  const auth = await authorize(request, env);
  if (!auth.ok) {
    return json({ ok: false, error: auth.error }, auth.status);
  }

  const script = await fetchGithubScript(env);
  if (!script) {
    return json({ ok: false, error: "empty script" }, 502);
  }

  return text(script);
}

async function loadMeta(request, env) {
  const auth = await authorize(request, env);
  if (!auth.ok) {
    return json({ ok: false, error: auth.error }, auth.status);
  }

  const script = await fetchGithubScript(env);
  if (!script) {
    return json({ ok: false, error: "empty script" }, 502);
  }

  const chunkSize = Number(env.CHUNK_SIZE || 12000);
  return json({
    ok: true,
    size: script.length,
    chunk_size: chunkSize,
    chunks: Math.ceil(script.length / chunkSize)
  });
}

async function loadChunk(request, env) {
  const auth = await authorize(request, env);
  if (!auth.ok) {
    return json({ ok: false, error: auth.error }, auth.status);
  }

  const input = await readInput(request);
  const index = Number(input.index || 0);
  const script = await fetchGithubScript(env);
  if (!script) {
    return json({ ok: false, error: "empty script" }, 502);
  }

  const chunkSize = Number(env.CHUNK_SIZE || 12000);
  const start = index * chunkSize;
  const chunk = script.slice(start, start + chunkSize);

  return json({
    ok: true,
    index,
    size: script.length,
    data: chunk
  });
}

async function fetchGithubScript(env) {
  const githubUrl = env.GITHUB_API_URL || env.GITHUB_RAW_URL;
  if (!githubUrl) {
    return "";
  }

  const headers = {
    "user-agent": "cryonova-worker",
    "accept": env.GITHUB_API_URL
      ? "application/vnd.github.raw"
      : "text/plain"
  };

  if (env.GITHUB_TOKEN) {
    headers.authorization = `Bearer ${env.GITHUB_TOKEN}`;
  }

  const response = await fetch(githubUrl, { headers, cf: { cacheTtl: 0 } });
  if (!response.ok) {
    return "";
  }

  const script = await response.text();

  if (!script || script.trim() === "") {
    return "";
  }

  if (script.trim().startsWith("{") && script.includes('"message"')) {
    return "";
  }

  return script;
}

async function debugGithub(env) {
  const githubUrl = env.GITHUB_API_URL || env.GITHUB_RAW_URL;
  const result = {
    ok: false,
    version: "raw-github-debug-v1",
    has_github_url: !!githubUrl,
    has_github_token: !!env.GITHUB_TOKEN,
    github_url_kind: env.GITHUB_API_URL ? "api" : (env.GITHUB_RAW_URL ? "raw" : "missing")
  };

  if (!githubUrl) {
    result.error = "missing github url";
    return json(result, 500);
  }

  const headers = {
    "user-agent": "cryonova-worker",
    "accept": env.GITHUB_API_URL
      ? "application/vnd.github.raw"
      : "text/plain"
  };

  if (env.GITHUB_TOKEN) {
    headers.authorization = `Bearer ${env.GITHUB_TOKEN}`;
  }

  const response = await fetch(githubUrl, { headers, cf: { cacheTtl: 0 } });
  const body = await response.text();
  result.github_status = response.status;
  result.content_type = response.headers.get("content-type") || "";
  result.body_length = body.length;
  result.body_preview = body.slice(0, 80);
  result.ok = response.ok && body.length > 0;

  return json(result, result.ok ? 200 : 502);
}

function decodeGithubContent(data) {
  if (!data || !data.content) return "";
  const compact = String(data.content).replace(/\s/g, "");
  const binary = atob(compact);
  const bytes = Uint8Array.from(binary, (char) => char.charCodeAt(0));
  return new TextDecoder().decode(bytes);
}

async function readGithubApiScript(data, env) {
  const decoded = decodeGithubContent(data);
  if (decoded) return decoded;

  if (!data || !data.download_url) return "";

  const headers = {
    "user-agent": "cryonova-worker",
    "accept": "text/plain"
  };

  if (env.GITHUB_TOKEN) {
    headers.authorization = `Bearer ${env.GITHUB_TOKEN}`;
  }

  const response = await fetch(data.download_url, {
    headers,
    cf: { cacheTtl: 0 }
  });

  if (!response.ok) return "";
  return await response.text();
}
