// Idempotent Coolify v4 provisioner for Last Card (uno-mobile).
//
// Creates or reuses the app in the DIGISION-DEV project, attaches the domain
// to the compose service, deploys and waits for the result. Runs with plain
// Node 22 (no dependencies), normally inside a throwaway node:22-alpine
// container started by deploy/coolify/setup.sh.
//
// Required env: COOLIFY_TOKEN, APP_DOMAIN.
// Optional env: COOLIFY_URL, GIT_REPOSITORY, GIT_BRANCH, PROJECT_NAME,
//   APP_NAME, SERVER_UUID, DEBIAN_IMAGE, NGINX_IMAGE, DEPLOY=0,
//   COOLIFY_SOURCE_HINT, POLL_MS, DEPLOY_TIMEOUT_MS, COMPOSE_WAIT_MS.

export const COMPOSE_SERVICE = "web";
export const CONTAINER_PORT = 8080;
const DEFAULTS = {
  coolifyUrl: "https://coolify.digision.dev",
  repository: "https://github.com/freack21/uno-mobile",
  branch: "main",
  project: "DIGISION-DEV",
  environment: "production",
  appName: "uno-mobile",
  description: "Last Card - offline card game PWA (Flutter web)",
};
// Build-time image overrides passed to docker-compose.yml as build args.
const IMAGE_VARS = ["DEBIAN_IMAGE", "NGINX_IMAGE"];

export class ProvisionError extends Error {
  constructor(message, { status, data } = {}) {
    super(message);
    this.name = "ProvisionError";
    this.status = status;
    this.data = data;
  }
}

export function repoSlug(url) {
  return String(url ?? "")
    .trim()
    .replace(/^git@github\.com:/i, "")
    .replace(/^https?:\/\/(www\.)?github\.com\//i, "")
    .replace(/\.git$/i, "")
    .replace(/\/+$/, "")
    .toLowerCase();
}

export function normalizeDomain(input) {
  const host = String(input ?? "")
    .trim()
    .replace(/^https?:\/\//i, "")
    .replace(/[/:].*$/, "")
    .toLowerCase();
  if (!/^(?=.{1,253}$)([a-z0-9](-*[a-z0-9])*\.)+[a-z]{2,}$/.test(host)) {
    throw new ProvisionError(`Invalid domain "${input}". Use a hostname like uno.example.com.`);
  }
  return host;
}

export function readConfig(env = process.env) {
  if (!env.COOLIFY_TOKEN) throw new ProvisionError("COOLIFY_TOKEN is not set.");
  if (!env.APP_DOMAIN) throw new ProvisionError("APP_DOMAIN is not set.");
  const images = {};
  for (const key of IMAGE_VARS) if (env[key]) images[key] = env[key];
  return {
    coolifyUrl: (env.COOLIFY_URL || DEFAULTS.coolifyUrl).replace(/\/+$/, ""),
    token: env.COOLIFY_TOKEN,
    domain: normalizeDomain(env.APP_DOMAIN),
    repository: env.GIT_REPOSITORY || DEFAULTS.repository,
    branch: env.GIT_BRANCH || DEFAULTS.branch,
    project: env.PROJECT_NAME || DEFAULTS.project,
    appName: env.APP_NAME || DEFAULTS.appName,
    serverUuid: env.SERVER_UUID || "",
    deploy: env.DEPLOY !== "0",
    images,
    sourceHint: env.COOLIFY_SOURCE_HINT || "",
    pollMs: Number(env.POLL_MS) || 3000,
    deployTimeoutMs: Number(env.DEPLOY_TIMEOUT_MS) || 30 * 60 * 1000,
    composeWaitMs: Number(env.COMPOSE_WAIT_MS) || 30 * 1000,
  };
}

function formatErrors(data) {
  const parts = [];
  if (data?.message) parts.push(data.message);
  if (data?.errors) parts.push(JSON.stringify(data.errors));
  return parts.join(" ") || JSON.stringify(data ?? "");
}

/** Coolify rejects compose domains until the compose file has been loaded. */
export function isComposeNotLoaded(err) {
  return (
    err instanceof ProvisionError &&
    err.status === 422 &&
    JSON.stringify(err.data?.errors ?? "").includes("docker_compose_raw")
  );
}

export function createApi(cfg, fetchImpl = globalThis.fetch) {
  const base = `${cfg.coolifyUrl}/api/v1`;
  return async function api(method, path, body) {
    let res;
    try {
      res = await fetchImpl(base + path, {
        method,
        headers: {
          Authorization: `Bearer ${cfg.token}`,
          Accept: "application/json",
          ...(body ? { "Content-Type": "application/json" } : {}),
        },
        body: body ? JSON.stringify(body) : undefined,
      });
    } catch (e) {
      throw new ProvisionError(`Cannot reach Coolify at ${cfg.coolifyUrl} (${e.message}).`);
    }
    const text = await res.text();
    let data;
    try {
      data = text ? JSON.parse(text) : null;
    } catch {
      data = { message: text.slice(0, 300) };
    }
    if (res.ok) return data;
    if (res.status === 401) {
      throw new ProvisionError(
        "Coolify rejected the API token (401). Create a new token in Keys & Tokens and run again.",
        { status: 401, data },
      );
    }
    if (res.status === 403) {
      const hint = cfg.sourceHint ? ` Requests come from ${cfg.sourceHint}.` : "";
      throw new ProvisionError(
        `Coolify refused API access (403): ${formatErrors(data)}. Enable API access in Settings > Advanced, ` +
          `leave "Allowed IPs" empty or include the coolify Docker network,${hint} and use a token with the root permission.`,
        { status: 403, data },
      );
    }
    throw new ProvisionError(`Coolify ${method} ${path} failed (${res.status}): ${formatErrors(data)}`, {
      status: res.status,
      data,
    });
  };
}

const list = (data) => (Array.isArray(data) ? data : (data?.data ?? []));

export async function provision(
  cfg,
  { fetchImpl = globalThis.fetch, log = console.log, sleep = (ms) => new Promise((r) => setTimeout(r, ms)), now = Date.now } = {},
) {
  const api = createApi(cfg, fetchImpl);
  const composeDomains = [{ name: COMPOSE_SERVICE, domain: `https://${cfg.domain}:${CONTAINER_PORT}` }];
  const slug = repoSlug(cfg.repository);

  // 1. Server
  const servers = list(await api("GET", "/servers"));
  const server = cfg.serverUuid
    ? servers.find((s) => s.uuid === cfg.serverUuid)
    : servers.find((s) => s.name === "localhost");
  if (!server) {
    throw new ProvisionError(
      cfg.serverUuid ? `Server ${cfg.serverUuid} not found in Coolify.` : 'No Coolify server named "localhost". Set SERVER_UUID.',
    );
  }

  // 2. Application (matched by name and repository)
  let app = list(await api("GET", "/applications")).find(
    (a) => a.name === cfg.appName && repoSlug(a.git_repository) === slug,
  );
  let created = false;
  if (app) {
    log(`Reusing application ${app.name} (${app.uuid}).`);
  } else {
    const projects = list(await api("GET", "/projects"));
    let project = projects.find((p) => p.name === cfg.project);
    if (project) {
      log(`Using project ${cfg.project} (${project.uuid}).`);
    } else {
      project = await api("POST", "/projects", {
        name: cfg.project,
        description: "DIGISION development apps",
      });
      log(`Created project ${cfg.project} (${project.uuid}). If you expected it to exist, check for a near-duplicate name.`);
    }
    app = await api("POST", "/applications/public", {
      project_uuid: project.uuid,
      server_uuid: server.uuid,
      environment_name: DEFAULTS.environment,
      git_repository: cfg.repository,
      git_branch: cfg.branch,
      build_pack: "dockercompose",
      docker_compose_location: "/docker-compose.yml",
      docker_compose_domains: composeDomains,
      name: cfg.appName,
      description: DEFAULTS.description,
      instant_deploy: false,
    });
    created = true;
    log(`Created application ${cfg.appName} (${app.uuid}) in ${cfg.project}.`);
  }
  const uuid = app.uuid;

  // 3. Env vars this provisioner owns (only image overrides; no secrets).
  if (Object.keys(cfg.images).length) {
    await api("PATCH", `/applications/${uuid}/envs/bulk`, {
      data: Object.entries(cfg.images).map(([key, value]) => ({ key, value, is_preview: false })),
    });
    log(`Set image overrides: ${Object.keys(cfg.images).join(", ")}.`);
  }

  // 4. Compose settings + domain, handling the compose-load race (P14).
  const settings = { git_branch: cfg.branch, docker_compose_location: "/docker-compose.yml" };
  const patchDomains = async () => {
    const deadline = now() + cfg.composeWaitMs;
    for (;;) {
      try {
        await api("PATCH", `/applications/${uuid}`, { ...settings, docker_compose_domains: composeDomains });
        return true;
      } catch (e) {
        if (!isComposeNotLoaded(e)) throw e;
        if (now() >= deadline) return false;
        log("Coolify is still loading docker-compose.yml, retrying...");
        await sleep(cfg.pollMs);
      }
    }
  };

  let deployed = false;
  if (!(await patchDomains())) {
    await api("PATCH", `/applications/${uuid}`, settings);
    if (!cfg.deploy) {
      throw new ProvisionError(
        "Coolify has not loaded docker-compose.yml yet, so the domain could not be attached. " +
          "Run again without DEPLOY=0 (a bootstrap deployment loads the compose file), " +
          "or open the app in Coolify and click Reload Compose File.",
      );
    }
    log("Running a bootstrap deployment so Coolify loads docker-compose.yml...");
    await deployAndWait(api, uuid, cfg, { log, sleep, now });
    if (!(await patchDomains())) {
      throw new ProvisionError(
        "Coolify still has no docker-compose.yml after a deployment. Check the deployment log in " +
          "Coolify (Deployments tab) for repository or compose read errors.",
      );
    }
  }
  log(`Domain https://${cfg.domain} attached to service "${COMPOSE_SERVICE}" on port ${CONTAINER_PORT}.`);

  // 5. Deploy
  if (cfg.deploy) {
    await deployAndWait(api, uuid, cfg, { log, sleep, now });
    deployed = true;
  } else {
    log("DEPLOY=0: skipped deployment.");
  }

  const webhook = `https://coolify.digision.dev/api/v1/deploy?uuid=${uuid}&force=false`;
  log("");
  log(`Site:    https://${cfg.domain}`);
  log(`Health:  https://${cfg.domain}/healthz`);
  log(`Webhook: ${webhook}`);
  return { uuid, created, deployed, webhook };
}

export async function deployAndWait(api, uuid, cfg, { log, sleep, now }) {
  const res = await api("POST", `/deploy?uuid=${encodeURIComponent(uuid)}&force=false`);
  const deployment = res?.deployments?.[0]?.deployment_uuid;
  if (!deployment) throw new ProvisionError(`Coolify did not start a deployment: ${formatErrors(res)}`);
  log(`Deployment ${deployment} started (the Flutter build takes a few minutes).`);
  const deadline = now() + cfg.deployTimeoutMs;
  let last = "";
  for (;;) {
    const d = await api("GET", `/deployments/${deployment}`);
    const status = String(d?.status ?? "");
    if (status !== last) {
      log(`  status: ${status}`);
      last = status;
    }
    if (status === "finished") return deployment;
    if (status === "failed" || status.startsWith("cancelled")) {
      throw new ProvisionError(
        `Deployment ${deployment} ${status}. Open the app in Coolify > Deployments for the build log.`,
      );
    }
    if (now() >= deadline) {
      throw new ProvisionError(
        `Deployment ${deployment} still "${status}" after ${Math.round(cfg.deployTimeoutMs / 60000)} min. ` +
          "Check Coolify > Deployments; it may still finish.",
      );
    }
    await sleep(cfg.pollMs);
  }
}

const isMain = import.meta.url === `file://${process.argv[1]}`;
if (isMain) {
  try {
    await provision(readConfig());
  } catch (e) {
    console.error(`\nERROR: ${e.message}`);
    process.exit(1);
  }
}
