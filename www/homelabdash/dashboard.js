const CONSUL_ADDR = "https://consul.service.home:8501";
const NOMAD_ADDR = "https://nomad.service.home:4646";
const PROM_ADDR = "https://prometheus.service.home";
const DOMAIN = "service.home";

const allocJobCache = {};
const serviceAllocCache = {};

async function resolveAllocId(name) {
  if (name in serviceAllocCache) return serviceAllocCache[name];
  try {
    const res = await fetch(
      `${CONSUL_ADDR}/v1/catalog/service/${encodeURIComponent(name)}`,
    );
    const data = res.ok ? await res.json() : [];
    const allocId = extractAllocId(data[0]?.ServiceID);
    serviceAllocCache[name] = allocId;
    return allocId;
  } catch {
    serviceAllocCache[name] = null;
    return null;
  }
}

function extractAllocId(serviceId) {
  const m = serviceId?.match(
    /_nomad-task-([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})-/,
  );
  return m ? m[1] : null;
}

async function resolveNomadJob(allocId) {
  if (allocId in allocJobCache) return allocJobCache[allocId];
  try {
    const res = await fetch(`${NOMAD_ADDR}/v1/allocation/${allocId}`);
    const jobId = res.ok ? (await res.json()).JobID : null;
    allocJobCache[allocId] = jobId;
    return jobId;
  } catch {
    allocJobCache[allocId] = null;
    return null;
  }
}

let servicesData = {};
// Same Consul catalog as servicesData, but keeping the traefik.enable=true
// entries servicesData drops (sidecar-proxy services): Nomad Connect stamps
// those with the parent's tags too, and Traefik's consulCatalog provider
// (exposedByDefault: false, jobs/traefik.hcl) routes on that tag regardless
// of the name shape, so this is the actual eligibility set to reconcile ACME
// certs against — not the UI-filtered one.
let acmeEligibleServices = {};
let checksData = [];
let alertsData = [];
let isCatalogLoaded = false;
let isHealthLoaded = false;

function init() {
  watchCatalog();
  watchHealth();
  watchAlerts();
  watchInfra();
  initTabs();
}

function setActiveTab(tab) {
  document.querySelectorAll(".tab").forEach((b) => {
    const active = b.dataset.tab === tab;
    b.classList.toggle("active", active);
    b.setAttribute("aria-selected", active ? "true" : "false");
  });
  document
    .getElementById("tab-services")
    .classList.toggle("hidden", tab !== "services");
  document
    .getElementById("tab-infra")
    .classList.toggle("hidden", tab !== "infra");
  // The search box filters service cards, which only exist on the services
  // tab. visibility (not display) so hiding it doesn't change .header's row
  // height and shift everything else in the app bar — see .search-hidden.
  document
    .getElementById("search-container")
    .classList.toggle("search-hidden", tab !== "services");
  if (location.hash.slice(1) !== tab) {
    location.hash = tab;
  }
}

function initTabs() {
  document.querySelectorAll(".tab").forEach((btn) => {
    btn.addEventListener("click", () => setActiveTab(btn.dataset.tab));
  });

  window.addEventListener("hashchange", () => {
    const tab = location.hash.slice(1);
    if (tab === "infra" || tab === "services") setActiveTab(tab);
  });

  const initialTab = location.hash.slice(1);
  if (initialTab === "infra" || initialTab === "services") {
    setActiveTab(initialTab);
  }
}

// Prometheus's /api/v1/alerts has no blocking-query support (unlike Consul),
// so this polls on a timer instead of long-polling. Deliberately independent
// of isCatalogLoaded/isHealthLoaded: the banner should render as soon as it
// has data, and a Prometheus outage should never block the service tiles.
async function watchAlerts() {
  while (true) {
    try {
      const res = await fetch(`${PROM_ADDR}/api/v1/alerts`);
      if (res.ok) {
        const body = await res.json();
        alertsData = (body.data?.alerts || []).filter(
          (a) => a.state === "firing" || a.state === "pending",
        );
        renderAlerts();
      }
    } catch (err) {
      console.error("Alerts watch error:", err);
    }
    await new Promise((r) => setTimeout(r, 20000));
  }
}

function formatDuration(ms) {
  const s = Math.max(0, Math.floor(ms / 1000));
  const d = Math.floor(s / 86400);
  const h = Math.floor((s % 86400) / 3600);
  const m = Math.floor((s % 3600) / 60);
  if (d > 0) return `${d}d ${h}h`;
  if (h > 0) return `${h}h ${m}m`;
  if (m > 0) return `${m}m`;
  return `${s}s`;
}

function renderAlerts() {
  const container = document.getElementById("alerts");
  if (!container) return;

  // Firing alerts sort ahead of pending ones (pending is a quieter,
  // not-yet-actionable tier), then by severity, then by duration
  // descending (oldest activeAt first) as a stable tiebreaker: unlike
  // relying on whatever order the API returns, an alert's relative age
  // only moves in one direction, so same-tier rows don't reshuffle
  // between polls with nothing having actually changed.
  const stateRank = { firing: 0, pending: 1 };
  const severityRank = { critical: 0, warning: 1 };
  const activeAtMs = (a) =>
    a.activeAt ? new Date(a.activeAt).getTime() : Infinity;
  const sorted = [...alertsData].sort((a, b) => {
    const stateDiff = (stateRank[a.state] ?? 2) - (stateRank[b.state] ?? 2);
    if (stateDiff !== 0) return stateDiff;
    const severityDiff =
      (severityRank[a.labels?.severity] ?? 2) -
      (severityRank[b.labels?.severity] ?? 2);
    if (severityDiff !== 0) return severityDiff;
    return activeAtMs(a) - activeAtMs(b);
  });

  container.classList.toggle("hidden", sorted.length === 0);
  container.innerHTML = sorted
    .map((a) => {
      const isPending = a.state === "pending";
      const cls = isPending
        ? "pending"
        : a.labels?.severity === "warning"
          ? "warning"
          : "critical";
      const text = a.annotations?.summary || a.labels?.alertname || "Alert";
      // activeAt marks when the condition first became true and doesn't
      // reset on the pending->firing transition, so this is how long the
      // condition itself has been true, not just how long it's been firing.
      const duration = a.activeAt
        ? formatDuration(Date.now() - new Date(a.activeAt).getTime())
        : null;
      const suffix = [isPending ? "pending" : null, duration]
        .filter(Boolean)
        .join(" · ");
      return `<div class="alert-row ${cls}"><span class="alert-text">${text}</span>${suffix ? `<span class="alert-duration">${suffix}</span>` : ""}</div>`;
    })
    .join("");
}

// Cert types sourced from x509_cert_not_after (absolute unix timestamps,
// watched by x509-exporter) vs. the consul/nomad agent metrics, which are
// already seconds-remaining gauges. Both kinds get normalized to
// seconds-remaining in loadInfra().
// All four of these are issued by vault-agent with ttl=32d and renewed at
// the global lease_renewal_threshold = 0.5 (os/etc/vault-agent.d/agent.hcl.j2),
// i.e. vault-agent should renew each one while ~16d still remains. Less than
// that means a renewal that should already have happened hasn't.
const VAULT_AGENT_RENEWAL_THRESHOLD_SECONDS = 16 * 86400;

const CERT_TYPES = [
  {
    key: "consul",
    label: "Consul",
    query: "consul_agent_tls_cert_expiry",
    warnThresholdSeconds: VAULT_AGENT_RENEWAL_THRESHOLD_SECONDS,
  },
  {
    key: "nomad",
    label: "Nomad",
    query: "nomad_agent_tls_cert_expiration_seconds",
    warnThresholdSeconds: VAULT_AGENT_RENEWAL_THRESHOLD_SECONDS,
  },
  {
    key: "vaultServer",
    label: "Vault Server",
    filepath: "/certs/vault/server.crt",
    warnThresholdSeconds: VAULT_AGENT_RENEWAL_THRESHOLD_SECONDS,
  },
  {
    key: "vaultClient",
    label: "Vault Client",
    filepath: "/certs/vault/client.crt",
    warnThresholdSeconds: VAULT_AGENT_RENEWAL_THRESHOLD_SECONDS,
  },
];

// The CA cert for each PKI issuing mount, rendered to disk once by
// x509-exporter's own Vault template (see jobs/x509-exporter.hcl) and
// watched under the same /certs/trust dir on every Vault node, so every
// instance reports an identical not_after for a given mount.
const PKI_MOUNTS = [
  { key: "pki", label: "pki", filepath: "/certs/trust/pki.pem" },
  { key: "pki_int", label: "pki_int", filepath: "/certs/trust/pki_int.pem" },
  {
    key: "pki_int_internal",
    label: "pki_int_internal",
    filepath: "/certs/trust/pki_int_internal.pem",
  },
  {
    key: "pki_int_connect",
    label: "pki_int_connect",
    filepath: "/certs/trust/pki_int_connect.pem",
  },
];

// ACME leaf certs Traefik issues per-domain off pki_int (jobs/traefik.hcl's
// "vault" certificatesResolver). Unlike CERT_TYPES/PKI_MOUNTS this isn't a
// fixed list, so it's reconciled against acmeEligibleServices instead of
// alerting on whatever domains happen to still be in Traefik's ACME store —
// a decommissioned service's cert lingers there (and keeps renewing) long
// after nothing routes to it.
const ACME_ROUTER_RULE_RE = /^traefik\.http\.routers\.[^.]+\.rule=(.*)$/;
const HOST_RULE_DOMAIN_RE = /`([^`]+)`/g;

// Mirrors jobs/traefik.hcl's consulCatalog defaultRule
// (Host(`{{ .Name }}.service.home`)), with the same
// "traefik.http.routers.<name>.rule=Host(...)" override tag documented in
// CLAUDE.md for services that need a custom hostname.
function expectedAcmeHostnames() {
  const hosts = new Set();
  for (const [name, tags] of Object.entries(acmeEligibleServices)) {
    const ruleTag = tags.find((t) => ACME_ROUTER_RULE_RE.test(t));
    const rule = ruleTag?.match(ACME_ROUTER_RULE_RE)?.[1];
    if (rule) {
      for (const m of rule.matchAll(HOST_RULE_DOMAIN_RE)) hosts.add(m[1]);
    } else {
      hosts.add(`${name}.${DOMAIN}`);
    }
  }
  return hosts;
}

// Traefik keeps stale + freshly-renewed entries side by side during
// rotation, and each of the two replicas (jobs/traefik.hcl) requests its own
// copy independently, so a domain can have several series — keep the
// soonest-expiring one, same as the vault-agent leaf selection above.
function buildAcmeCertData(rows) {
  const now = Date.now() / 1000;
  const byDomain = new Map();
  for (const r of rows) {
    const seconds = Number(r.value[1]) - now;
    for (const domain of (r.metric.sans || "").split(",").filter(Boolean)) {
      if (!byDomain.has(domain) || seconds < byDomain.get(domain)) {
        byDomain.set(domain, seconds);
      }
    }
  }

  // Before the catalog's first load, acmeEligibleServices is still empty —
  // treat everything as live rather than flashing every domain as orphaned.
  const expected = isCatalogLoaded ? expectedAcmeHostnames() : null;
  const live = [];
  const orphaned = [];
  for (const [host, seconds] of byDomain) {
    const bucket = !expected || expected.has(host) ? live : orphaned;
    bucket.push({ host, seconds });
  }
  live.sort((a, b) => a.host.localeCompare(b.host));
  orphaned.sort((a, b) => a.host.localeCompare(b.host));
  return { live, orphaned };
}

let infraData = {
  uptime: [],
  certs: {},
  pki: {},
  acme: { live: [], orphaned: [] },
};

async function promQuery(query) {
  const res = await fetch(
    `${PROM_ADDR}/api/v1/query?query=${encodeURIComponent(query)}`,
  );
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  const body = await res.json();
  return body.data?.result || [];
}

// Prometheus has no blocking-query support, same constraint as watchAlerts,
// so this polls on a timer too.
async function watchInfra() {
  while (true) {
    try {
      await loadInfra();
      renderInfra();
    } catch (err) {
      console.error("Infra watch error:", err);
    }
    await new Promise((r) => setTimeout(r, 20000));
  }
}

async function loadInfra() {
  const [boot, x509, acmeCerts, ...certResults] = await Promise.all([
    promQuery("node_boot_time_seconds"),
    promQuery("x509_cert_not_after"),
    // job="traefik" only: the internal instance's pki_int-issued certs.
    // traefik-ingress's public certs (Let's Encrypt via Cloudflare DNS-01)
    // are a separate resolver with no relationship to the Consul catalog
    // reconciliation below.
    promQuery('traefik_tls_certs_not_after{job="traefik"}'),
    ...CERT_TYPES.filter((t) => t.query).map((t) => promQuery(t.query)),
  ]);
  const now = Date.now() / 1000;

  infraData.acme = buildAcmeCertData(acmeCerts);

  infraData.uptime = boot
    .map((r) => ({
      host: r.metric.instance,
      uptimeSeconds: now - Number(r.value[1]),
    }))
    .sort((a, b) => a.host.localeCompare(b.host));

  let queryResultIdx = 0;
  for (const type of CERT_TYPES) {
    let rows;
    if (type.query) {
      rows = certResults[queryResultIdx++].map((r) => ({
        host: r.metric.host,
        seconds: Number(r.value[1]),
      }));
    } else {
      // vault-agent renders these as leaf+CA bundles (.Cert followed by .CA,
      // see os/etc/vault-agent.d/vault-{server,client}.tpl), so x509-exporter
      // reports one series per cert in the file. Keep only the soonest
      // (the short-lived leaf) per host — the embedded CA duplicates what
      // the pki_int_internal mount already reports.
      const byHost = new Map();
      for (const r of x509) {
        if (r.metric.filepath !== type.filepath) continue;
        const host = r.metric.instance;
        const seconds = Number(r.value[1]) - now;
        if (!byHost.has(host) || seconds < byHost.get(host)) {
          byHost.set(host, seconds);
        }
      }
      rows = [...byHost.entries()].map(([host, seconds]) => ({
        host,
        seconds,
      }));
    }
    infraData.certs[type.key] = rows.sort((a, b) =>
      a.host.localeCompare(b.host),
    );
  }

  infraData.pki = {};
  for (const mount of PKI_MOUNTS) {
    const rows = x509.filter((r) => r.metric.filepath === mount.filepath);
    infraData.pki[mount.key] = rows.length
      ? Math.min(...rows.map((r) => Number(r.value[1]) - now))
      : null;
  }
}

// Default mirrors the 14d threshold used by the CertExpiringSoon/
// *CertExpiringSoon Prometheus alerts (jobs/monitoring.hcl); cert types
// renewed by vault-agent pass VAULT_AGENT_RENEWAL_THRESHOLD_SECONDS instead,
// so "warning" lines up with a renewal that should already have fired.
// Below 3d is always critical regardless of type — no automatic renewal
// leaves that much margin.
function classifyExpiry(seconds, warnThresholdSeconds = 14 * 86400) {
  if (seconds === null || seconds === undefined || Number.isNaN(seconds))
    return "unknown";
  if (seconds < 3 * 86400) return "critical";
  if (seconds < warnThresholdSeconds) return "warning";
  return "passing";
}

function formatExpiry(seconds) {
  if (seconds === null || seconds === undefined || Number.isNaN(seconds))
    return "no data";
  if (seconds <= 0) return `expired ${formatDuration(-seconds * 1000)} ago`;
  const days = seconds / 86400;
  if (days >= 365) return `${(days / 365).toFixed(1)}y (${Math.round(days)}d)`;
  if (days >= 1) return `${Math.round(days)}d`;
  return formatDuration(seconds * 1000);
}

function expiryChip(seconds, warnThresholdSeconds) {
  const cls = classifyExpiry(seconds, warnThresholdSeconds);
  return `<span class="expiry-chip ${cls}"><span class="dot"></span>${formatExpiry(seconds)}</span>`;
}

function renderInfra() {
  renderUptime();
  renderCertTypes();
  renderPkiMounts();
  renderAcmeCerts();
}

function renderUptime() {
  const container = document.getElementById("uptime-list");
  if (!infraData.uptime.length) {
    container.innerHTML = `<p class="infra-loading">No uptime data</p>`;
    return;
  }
  container.innerHTML = infraData.uptime
    .map(
      (row) => `
        <div class="info-card uptime-row">
          <span class="host">${row.host}</span>
          <span class="uptime-value">${formatDuration(row.uptimeSeconds * 1000)}</span>
        </div>
      `,
    )
    .join("");
}

function renderCertTypes() {
  const container = document.getElementById("cert-types");
  container.innerHTML = CERT_TYPES.map((type) => {
    // rows is sorted by hostname (for the breakout below), so the earliest
    // (soonest-expiring) entry for the rollup chip has to be found by value
    // rather than assumed to be rows[0].
    const rows = infraData.certs[type.key] || [];
    const earliest = rows.reduce(
      (min, r) => (min === null || r.seconds < min.seconds ? r : min),
      null,
    );
    const breakout = certBreakoutRows(rows, type.warnThresholdSeconds);
    return `
      <details class="info-card cert-type-card">
        <summary>
          <span class="cert-type-name">${type.label}</span>
          <span class="cert-type-summary-right">
            ${expiryChip(earliest?.seconds, type.warnThresholdSeconds)}
            <svg class="chevron" width="20" height="20" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
              <path d="M7.41 8.59L12 13.17l4.59-4.58L18 10l-6 6-6-6z" />
            </svg>
          </span>
        </summary>
        <div class="cert-breakout">${breakout || `<p class="infra-loading">No hosts reporting</p>`}</div>
      </details>
    `;
  }).join("");
}

function renderPkiMounts() {
  const container = document.getElementById("pki-mounts");
  container.innerHTML = PKI_MOUNTS.map(
    (mount) => `
      <div class="info-card pki-row">
        <span class="mount-name">${mount.label}</span>
        ${expiryChip(infraData.pki[mount.key])}
      </div>
    `,
  ).join("");
}

function certBreakoutRows(rows, warnThresholdSeconds) {
  return rows
    .map(
      (row) => `
        <div class="cert-breakout-row">
          <span class="host">${row.host}</span>
          ${expiryChip(row.seconds, warnThresholdSeconds)}
        </div>
      `,
    )
    .join("");
}

function renderAcmeCerts() {
  const container = document.getElementById("acme-certs");
  if (!container) return;
  const { live, orphaned } = infraData.acme;

  const earliest = live.reduce(
    (min, r) => (min === null || r.seconds < min.seconds ? r : min),
    null,
  );

  let html = `
    <details class="info-card cert-type-card">
      <summary>
        <span class="cert-type-name">Traefik (${live.length})</span>
        <span class="cert-type-summary-right">
          ${expiryChip(earliest?.seconds)}
          <svg class="chevron" width="20" height="20" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
            <path d="M7.41 8.59L12 13.17l4.59-4.58L18 10l-6 6-6-6z" />
          </svg>
        </span>
      </summary>
      <div class="cert-breakout">${certBreakoutRows(live) || `<p class="infra-loading">No certs reporting</p>`}</div>
    </details>
  `;

  // No rollup chip here on purpose: these aren't backed by a live Consul
  // service (jobs/*.hcl has nothing registering them), so there's nothing
  // actionable about their expiry — they're surfaced for cleanup awareness,
  // not urgency. Omitted entirely when there's nothing orphaned.
  if (orphaned.length) {
    html += `
      <details class="info-card cert-type-card orphaned">
        <summary>
          <span class="cert-type-name">Orphaned (${orphaned.length})</span>
          <span class="cert-type-summary-right">
            <svg class="chevron" width="20" height="20" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
              <path d="M7.41 8.59L12 13.17l4.59-4.58L18 10l-6 6-6-6z" />
            </svg>
          </span>
        </summary>
        <div class="cert-breakout">${certBreakoutRows(orphaned)}</div>
      </details>
    `;
  }

  container.innerHTML = html;
}

async function watchCatalog() {
  let index = 0;
  while (true) {
    try {
      const res = await fetch(
        `${CONSUL_ADDR}/v1/catalog/services?index=${index}&wait=5m`,
      );
      if (res.ok) {
        const newIndex = res.headers.get("x-consul-index");
        if (newIndex) {
          index = newIndex;
        } else {
          await new Promise((r) => setTimeout(r, 2500)); // Fallback delay if CORS hides header
        }
        const catalog = await res.json();

        const newServicesData = {};
        const newAcmeEligibleServices = {};
        for (const name in catalog) {
          if (!catalog[name].includes("traefik.enable=true")) continue;
          newAcmeEligibleServices[name] = catalog[name];
          if (!name.endsWith("-sidecar-proxy")) {
            newServicesData[name] = catalog[name];
          }
        }
        servicesData = newServicesData;
        acmeEligibleServices = newAcmeEligibleServices;
        isCatalogLoaded = true;
        checkAndRender();
      } else {
        throw new Error(`HTTP ${res.status}`);
      }
    } catch (err) {
      if (err.message.includes("400")) index = 0;
      console.error("Catalog watch error:", err);
      document.getElementById("loader").innerHTML =
        `Connection Failed: ${err.message}`;
      document.getElementById("loader").classList.remove("hidden");
      await new Promise((r) => setTimeout(r, 5000));
    }
  }
}

async function watchHealth() {
  let index = 0;
  while (true) {
    try {
      const res = await fetch(
        `${CONSUL_ADDR}/v1/health/state/any?index=${index}&wait=5m`,
      );
      if (res.ok) {
        const newIndex = res.headers.get("x-consul-index");
        if (newIndex) {
          index = newIndex;
        } else {
          await new Promise((r) => setTimeout(r, 2500)); // Fallback delay if CORS hides header
        }
        checksData = await res.json();
        isHealthLoaded = true;
        checkAndRender();
      } else {
        throw new Error(`HTTP ${res.status}`);
      }
    } catch (err) {
      if (err.message.includes("400")) index = 0;
      console.error("Health watch error:", err);
      document.getElementById("loader").innerHTML =
        `Connection Failed: ${err.message}`;
      document.getElementById("loader").classList.remove("hidden");
      await new Promise((r) => setTimeout(r, 5000));
    }
  }
}

function checkAndRender() {
  if (isCatalogLoaded && isHealthLoaded) {
    const loader = document.getElementById("loader");
    if (loader) {
      loader.classList.add("hidden");
    }
    render();
  }
}

function getTagValWithDefault(tags, key, defawlt) {
  const tag = tags?.find((tag) => tag.startsWith(key + "="));
  return tag ? tag.split("=")[1] : defawlt;
}

function render() {
  const container = document.getElementById("dashboard");
  const processedCards = new Set();

  for (const [name, tags] of Object.entries(servicesData)) {
    if (tags.includes("homelabdash.hide")) continue;

    const slug = getTagValWithDefault(tags, "homelabdash.slug", name);
    const extraUri = getTagValWithDefault(tags, "homelabdash.uri", "");

    const serviceChecks = checksData.filter((c) => c.ServiceName === name);

    let status = "passing";
    if (serviceChecks.length > 0) {
      const hasCritical = serviceChecks.some((c) => c.Status === "critical");
      const hasWarning = serviceChecks.some((c) => c.Status === "warning");
      if (hasCritical) {
        status = "critical";
      } else if (
        hasWarning ||
        !serviceChecks.every((c) => c.Status === "passing")
      ) {
        status = "warning";
      }
    }

    const url = `https://${slug}.${DOMAIN}${extraUri}`;

    let card = container.querySelector(`a.card[data-service-name="${name}"]`);

    if (!card) {
      card = document.createElement("a");
      card.setAttribute("data-service-name", name);
      card.target = "_blank";
      container.appendChild(card);

      card.innerHTML = `
                <div class="status-indicator"></div>
                <span class="nomad-link hidden" title="Nomad job"></span>
                <span class="service-name"></span>
                <span class="service-url"></span>
                <div class="status-text">
                    <div class="dot"></div>
                    <span class="status-label"></span>
                </div>
            `;
    }

    const isHidden = card.classList.contains("hidden");

    card.className = `card ${status}`;
    if (isHidden) card.classList.add("hidden");

    card.href = url;
    card.setAttribute("data-name", slug);

    card.querySelector(".service-name").textContent = slug;
    card.querySelector(".service-url").textContent = url;

    let statusText = "HEALTHY";
    if (status === "warning") statusText = "DEGRADED";
    if (status === "critical") statusText = "CRITICAL";
    card.querySelector(".status-label").textContent = statusText;

    const nomadLink = card.querySelector(".nomad-link");
    const applyJobId = (jobId) => {
      if (!jobId) return;
      nomadLink.dataset.href = `${NOMAD_ADDR}/ui/jobs/${jobId}@default`;
      nomadLink.classList.remove("hidden");
    };
    const applyAllocId = (allocId) => {
      if (!allocId) return;
      if (allocId in allocJobCache) {
        applyJobId(allocJobCache[allocId]);
      } else {
        resolveNomadJob(allocId).then(applyJobId);
      }
    };

    if (name in serviceAllocCache) {
      applyAllocId(serviceAllocCache[name]);
    } else {
      resolveAllocId(name).then(applyAllocId);
    }

    processedCards.add(name);
  }

  const allCards = container.querySelectorAll(".card");
  allCards.forEach((card) => {
    const name = card.getAttribute("data-service-name");
    if (!processedCards.has(name)) {
      card.remove();
    }
  });

  filter();
}

function filter() {
  const query = document.getElementById("search").value.toLowerCase();
  document.querySelectorAll(".card").forEach((card) => {
    const match = card.getAttribute("data-name").toLowerCase().includes(query);
    card.classList.toggle("hidden", !match);
  });

  const clearBtn = document.getElementById("clear-search");
  if (clearBtn) {
    clearBtn.classList.toggle("hidden", query.length === 0);
  }
}

function clearSearch() {
  const searchInput = document.getElementById("search");
  searchInput.value = "";
  filter();
  searchInput.focus();
}

document.addEventListener("keydown", (e) => {
  const searchInput = document.getElementById("search");
  const isSearchFocused = document.activeElement === searchInput;
  const isServicesTabActive = !document
    .getElementById("tab-services")
    .classList.contains("hidden");

  if (e.key === "/" && !isSearchFocused && isServicesTabActive) {
    e.preventDefault();
    searchInput.focus();
    return;
  }

  if (e.key === "Escape" && isSearchFocused) {
    searchInput.blur();
    return;
  }

  if (e.key === "Enter" && isSearchFocused) {
    const visibleCards = Array.from(
      document.querySelectorAll(".card:not(.hidden)"),
    );
    if (visibleCards.length === 1) {
      e.preventDefault();
      window.open(visibleCards[0].href, "_blank");
    }
    return;
  }

  if (e.ctrlKey || e.metaKey || e.altKey) return;

  if (!isSearchFocused && ["h", "j", "k", "l"].includes(e.key)) {
    const visibleCards = Array.from(
      document.querySelectorAll(".card:not(.hidden)"),
    );
    if (visibleCards.length === 0) return;

    let currentIndex = visibleCards.indexOf(document.activeElement);
    e.preventDefault(); // Prevent scroll on j/k/Enter space

    if (currentIndex === -1) {
      currentIndex = 0;
    } else {
      let cols = 1;
      if (visibleCards.length > 1) {
        for (let i = 1; i < visibleCards.length; i++) {
          if (visibleCards[i].offsetTop === visibleCards[0].offsetTop) cols++;
          else break;
        }
      }

      if (e.key === "h") currentIndex--;
      else if (e.key === "l") currentIndex++;
      else if (e.key === "k") currentIndex -= cols;
      else if (e.key === "j") currentIndex += cols;

      if (currentIndex < 0) currentIndex = 0;
      if (currentIndex >= visibleCards.length)
        currentIndex = visibleCards.length - 1;
    }

    visibleCards[currentIndex].focus();
  }
});

document.getElementById("dashboard").addEventListener("click", (e) => {
  const link = e.target.closest(".nomad-link");
  if (link?.dataset.href) {
    e.preventDefault();
    e.stopPropagation();
    window.open(link.dataset.href, "_blank");
  }
});

init();
