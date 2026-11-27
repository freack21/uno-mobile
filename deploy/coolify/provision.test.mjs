import assert from "node:assert/strict";
import { test } from "node:test";

import { provision, readConfig, repoSlug, normalizeDomain, ProvisionError } from "./provision.mjs";

const TOKEN = "test-token";

/**
 * In-memory Coolify v4 API that behaves like the real one where it matters:
 * GET /deploy is 405, and compose domains are rejected with a 422 mentioning
 * docker_compose_raw until the compose file is loaded (in the background after
 * `loadAfter` PATCH attempts, or by a deployment).
 */
function fakeCoolify({
  projects = [],
  apps = [],
  loadAfter = 1,
  backgroundLoads = true,
  deployStatus = ["queued", "in_progress", "finished"],
  token = TOKEN,
  respond,
} = {}) {
  const state = {
    projects: structuredClone(projects),
    apps: structuredClone(apps),
    calls: [],
    deploys: 0,
    domainPatches: 0,
    envs: {},
  };
  let n = 0;
  const id = (p) => `${p}-${++n}`;
  const deployments = {};

  const fetchImpl = async (url, init = {}) => {
    const u = new URL(url);
    const path = u.pathname.replace(/^\/api\/v1/, "");
    const method = init.method || "GET";
    const body = init.body ? JSON.parse(init.body) : undefined;
    state.calls.push({ method, path, query: u.search, body });
    const json = (status, data) =>
      new Response(JSON.stringify(data), { status, headers: { "Content-Type": "application/json" } });

    const custom = respond?.(method, path, body);
    if (custom) return custom;
    if (init.headers?.Authorization !== `Bearer ${token}`) return json(401, { message: "Unauthenticated." });

    if (method === "GET" && path === "/servers") return json(200, [{ uuid: "srv-1", name: "localhost" }]);
    if (method === "GET" && path === "/projects") return json(200, state.projects);
    if (method === "POST" && path === "/projects") {
      const p = { uuid: id("prj"), name: body.name };
      state.projects.push(p);
      return json(201, { uuid: p.uuid });
    }
    if (method === "GET" && path === "/applications") return json(200, state.apps);
    if (method === "POST" && path === "/applications/public") {
      const app = { uuid: id("app"), ...body, composeLoaded: false, status: "exited:unhealthy" };
      state.apps.push(app);
      return json(201, { uuid: app.uuid, domains: [] });
    }
    const appMatch = path.match(/^\/applications\/([^/]+)(\/envs\/bulk)?$/);
    if (appMatch) {
      const app = state.apps.find((a) => a.uuid === appMatch[1]);
      if (!app) return json(404, { message: "Application not found." });
      if (method === "PATCH" && appMatch[2]) {
        for (const e of body.data) state.envs[e.key] = e.value;
        return json(201, []);
      }
      if (method === "PATCH") {
        if (body.docker_compose_domains) {
          state.domainPatches++;
          if (!app.composeLoaded && backgroundLoads && state.domainPatches > loadAfter) app.composeLoaded = true;
          if (!app.composeLoaded) {
            return json(422, {
              message: "Validation failed.",
              errors: { docker_compose_domains: ["The docker_compose_raw is not loaded yet."] },
            });
          }
          app.docker_compose_domains = body.docker_compose_domains;
        }
        Object.assign(app, { git_branch: body.git_branch ?? app.git_branch });
        return json(200, { uuid: app.uuid });
      }
    }
    if (path === "/deploy") {
      if (method !== "POST") return json(405, { message: "Method Not Allowed" });
      const app = state.apps.find((a) => a.uuid === u.searchParams.get("uuid"));
      app.composeLoaded = true;
      state.deploys++;
      const d = id("dep");
      deployments[d] = [...deployStatus];
      return json(200, { deployments: [{ message: "queued", resource_uuid: app.uuid, deployment_uuid: d }] });
    }
    const dep = path.match(/^\/deployments\/(.+)$/);
    if (method === "GET" && dep) {
      const seq = deployments[dep[1]];
      const status = seq.length > 1 ? seq.shift() : seq[0];
      return json(200, { deployment_uuid: dep[1], status });
    }
    return json(404, { message: `No route ${method} ${path}` });
  };
  return { fetchImpl, state };
}

const cfg = (extra = {}) =>
  readConfig({ COOLIFY_TOKEN: TOKEN, APP_DOMAIN: "uno.refandi.my.id", POLL_MS: "1", COMPOSE_WAIT_MS: "50", ...extra });

// Virtual clock so retry windows don't slow the suite down.
function deps() {
  let t = 0;
  const logs = [];
  return {
    logs,
    opts: { log: (m) => logs.push(m), sleep: async (ms) => void (t += ms), now: () => t },
  };
}

test("first run creates project and app with compose settings, then deploys", async () => {
  const { fetchImpl, state } = fakeCoolify();
  const { opts, logs } = deps();
  const out = await provision(cfg(), { fetchImpl, ...opts });

  assert.equal(out.created, true);
  assert.equal(out.deployed, true);
  assert.equal(state.projects[0].name, "DIGISION-DEV");
  const create = state.calls.find((c) => c.path === "/applications/public").body;
  assert.equal(create.build_pack, "dockercompose");
  assert.equal(create.docker_compose_location, "/docker-compose.yml");
  assert.deepEqual(create.docker_compose_domains, [{ name: "web", domain: "https://uno.refandi.my.id:8080" }]);
  assert.equal(create.instant_deploy, false);
  assert.equal(create.git_repository, "https://github.com/freack21/uno-mobile");
  assert.equal(create.git_branch, "main");
  assert.equal(create.environment_name, "production");
  assert.equal(state.deploys, 1);
  assert.ok(state.calls.every((c) => c.path !== "/deploy" || c.method === "POST"));
  assert.match(out.webhook, /^https:\/\/coolify\.digision\.dev\/api\/v1\/deploy\?uuid=app-\d+&force=false$/);
  assert.ok(logs.some((l) => l.includes("Created project DIGISION-DEV")));
});

test("second run reuses project and app", async () => {
  const { fetchImpl, state } = fakeCoolify();
  await provision(cfg(), { fetchImpl, ...deps().opts });
  const { opts, logs } = deps();
  const out = await provision(cfg(), { fetchImpl, ...opts });

  assert.equal(out.created, false);
  assert.equal(state.apps.length, 1);
  assert.equal(state.projects.length, 1);
  assert.equal(state.deploys, 2);
  assert.ok(logs.some((l) => l.startsWith("Reusing application uno-mobile")));
});

test("existing project is chosen by exact name", async () => {
  const { fetchImpl, state } = fakeCoolify({
    projects: [
      { uuid: "prj-x", name: "digision-dev " },
      { uuid: "prj-real", name: "DIGISION-DEV" },
    ],
  });
  await provision(cfg(), { fetchImpl, ...deps().opts });
  assert.equal(state.projects.length, 2);
  assert.equal(state.calls.find((c) => c.path === "/applications/public").body.project_uuid, "prj-real");
});

test("same-name app from another repository is not reused", async () => {
  const { fetchImpl, state } = fakeCoolify({
    apps: [{ uuid: "other", name: "uno-mobile", git_repository: "someone/else", composeLoaded: true }],
  });
  const out = await provision(cfg(), { fetchImpl, ...deps().opts });
  assert.equal(out.created, true);
  assert.notEqual(out.uuid, "other");
});

test("existing app is matched across repository URL formats", async () => {
  const { fetchImpl } = fakeCoolify({
    apps: [{ uuid: "mine", name: "uno-mobile", git_repository: "git@github.com:Freack21/uno-mobile.git", composeLoaded: true }],
  });
  const out = await provision(cfg(), { fetchImpl, ...deps().opts });
  assert.equal(out.uuid, "mine");
});

test("DEPLOY=0 configures without deploying", async () => {
  const { fetchImpl, state } = fakeCoolify();
  const out = await provision(cfg({ DEPLOY: "0" }), { fetchImpl, ...deps().opts });
  assert.equal(out.deployed, false);
  assert.equal(state.deploys, 0);
});

test("image overrides are stored as env vars", async () => {
  const { fetchImpl, state } = fakeCoolify();
  await provision(cfg({ DEBIAN_IMAGE: "mirror.gcr.io/library/debian:bookworm-slim", NGINX_IMAGE: "mirror.gcr.io/library/nginx:stable-alpine" }), {
    fetchImpl,
    ...deps().opts,
  });
  assert.equal(state.envs.DEBIAN_IMAGE, "mirror.gcr.io/library/debian:bookworm-slim");
  assert.equal(state.envs.NGINX_IMAGE, "mirror.gcr.io/library/nginx:stable-alpine");
});

test("waits through compose-load 422s before attaching the domain", async () => {
  const { fetchImpl, state } = fakeCoolify({ loadAfter: 3 });
  await provision(cfg({ COMPOSE_WAIT_MS: "1000" }), { fetchImpl, ...deps().opts });
  assert.equal(state.domainPatches, 4);
  assert.equal(state.deploys, 1);
});

test("bootstrap deployment when the compose file never loads in the background", async () => {
  const { fetchImpl, state } = fakeCoolify({ backgroundLoads: false });
  const { opts, logs } = deps();
  await provision(cfg(), { fetchImpl, ...opts });

  assert.equal(state.deploys, 2);
  const seq = state.calls.filter((c) => c.path === "/deploy" || (c.method === "PATCH" && c.path.startsWith("/applications/")));
  const firstDeploy = seq.findIndex((c) => c.path === "/deploy");
  const domainAfter = seq.slice(firstDeploy).findIndex((c) => c.body?.docker_compose_domains);
  const secondDeploy = seq.slice(firstDeploy + 1).findIndex((c) => c.path === "/deploy");
  assert.ok(domainAfter > 0 && domainAfter < secondDeploy + 1, "domain patched between the two deploys");
  assert.ok(seq.slice(0, firstDeploy).some((c) => c.method === "PATCH" && !c.body.docker_compose_domains));
  assert.ok(logs.some((l) => l.includes("bootstrap deployment")));
});

test("DEPLOY=0 fails with instructions when the compose file never loads", async () => {
  const { fetchImpl, state } = fakeCoolify({ backgroundLoads: false });
  await assert.rejects(provision(cfg({ DEPLOY: "0" }), { fetchImpl, ...deps().opts }), /Reload Compose File/);
  assert.equal(state.deploys, 0);
});

test("clear error when compose is still not loaded after a deployment", async () => {
  const { fetchImpl } = fakeCoolify({
    backgroundLoads: false,
    respond: (method, path, body) =>
      method === "PATCH" && body?.docker_compose_domains
        ? new Response(
            JSON.stringify({ message: "Validation failed.", errors: { docker_compose_domains: ["docker_compose_raw missing"] } }),
            { status: 422 },
          )
        : undefined,
  });
  await assert.rejects(provision(cfg(), { fetchImpl, ...deps().opts }), /still has no docker-compose\.yml after a deployment/);
});

test("failed deployment points to the Deployments tab", async () => {
  const { fetchImpl } = fakeCoolify({ deployStatus: ["queued", "failed"] });
  await assert.rejects(provision(cfg(), { fetchImpl, ...deps().opts }), /failed\. Open the app in Coolify > Deployments/);
});

test("deployment timeout", async () => {
  const { fetchImpl } = fakeCoolify({ deployStatus: ["in_progress"] });
  await assert.rejects(provision(cfg({ DEPLOY_TIMEOUT_MS: "20" }), { fetchImpl, ...deps().opts }), /still "in_progress"/);
});

test("401 asks for a new token", async () => {
  const { fetchImpl } = fakeCoolify({ token: "other" });
  await assert.rejects(provision(cfg(), { fetchImpl, ...deps().opts }), (e) => e instanceof ProvisionError && e.status === 401 && /new token/.test(e.message));
});

test("403 explains API access and allowed IPs", async () => {
  const { fetchImpl } = fakeCoolify({
    respond: () => new Response(JSON.stringify({ message: "You are not allowed to access the API." }), { status: 403 }),
  });
  await assert.rejects(provision(cfg({ COOLIFY_SOURCE_HINT: "10.0.1.0/24" }), { fetchImpl, ...deps().opts }), (e) => {
    assert.equal(e.status, 403);
    assert.match(e.message, /Allowed IPs/);
    assert.match(e.message, /10\.0\.1\.0\/24/);
    return true;
  });
});

test("offline Coolify gives a readable error", async () => {
  const fetchImpl = async () => {
    throw new TypeError("fetch failed");
  };
  await assert.rejects(provision(cfg(), { fetchImpl, ...deps().opts }), /Cannot reach Coolify at https:\/\/coolify\.digision\.dev/);
});

test("other 422s show the field errors", async () => {
  const { fetchImpl } = fakeCoolify({
    respond: (method, path) =>
      method === "POST" && path === "/applications/public"
        ? new Response(JSON.stringify({ message: "Validation failed.", errors: { git_branch: ["The git branch field is required."] } }), {
            status: 422,
          })
        : undefined,
  });
  await assert.rejects(provision(cfg(), { fetchImpl, ...deps().opts }), (e) => {
    assert.equal(e.status, 422);
    assert.match(e.message, /Validation failed\. \{"git_branch"/);
    assert.deepEqual(e.data.errors.git_branch, ["The git branch field is required."]);
    return true;
  });
});

test("config validation and helpers", () => {
  assert.throws(() => readConfig({ APP_DOMAIN: "x.io" }), /COOLIFY_TOKEN/);
  assert.throws(() => readConfig({ COOLIFY_TOKEN: "t" }), /APP_DOMAIN/);
  assert.equal(normalizeDomain("https://Uno.Refandi.my.id/"), "uno.refandi.my.id");
  assert.throws(() => normalizeDomain("not a domain"), /Invalid domain/);
  assert.equal(repoSlug("https://github.com/Freack21/uno-mobile.git"), "freack21/uno-mobile");
  assert.equal(repoSlug("freack21/uno-mobile"), "freack21/uno-mobile");
  const c = readConfig({ COOLIFY_TOKEN: "t", APP_DOMAIN: "uno.refandi.my.id", GIT_BRANCH: "dev", PROJECT_NAME: "P" });
  assert.equal(c.branch, "dev");
  assert.equal(c.project, "P");
  assert.equal(c.deploy, true);
});
