const CONSUL_ADDR = "https://consul.service.home:8501";
const NOMAD_ADDR = "https://nomad.service.home:4646";
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
let checksData = [];
let isCatalogLoaded = false;
let isHealthLoaded = false;

function init() {
  watchCatalog();
  watchHealth();
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
        for (const name in catalog) {
          if (
            !name.endsWith("-sidecar-proxy") &&
            catalog[name].includes("traefik.enable=true")
          ) {
            newServicesData[name] = catalog[name];
          }
        }
        servicesData = newServicesData;
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

  if (e.key === "/" && !isSearchFocused) {
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
