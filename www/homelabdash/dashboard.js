const CONSUL_ADDR = 'https://consul.service.home:8501';
const DOMAIN = 'service.home';

async function init() {
    try {
        const catRes = await fetch(`${CONSUL_ADDR}/v1/catalog/services`);
        const catalog = await catRes.json();

        const services = Object.keys(catalog).filter(
            name => !name.endsWith('-sidecar-proxy') && catalog[name].includes('traefik.enable=true')
        );

        const healthRequests = services.map(name =>
            fetch(`${CONSUL_ADDR}/v1/health/service/${name}`).then(r => r.json())
        );

        const allHealthData = await Promise.all(healthRequests);
        document.getElementById('loader').classList.add('hidden');
        render(allHealthData);
    } catch (err) {
        document.getElementById('loader').innerHTML = `Connection Failed: ${err.message}`;
    }
}

function getTagValWithDefault(tags, key, defawlt) {
    const tag = tags?.find(tag => tag.startsWith(key + '='));
    return tag ? tag.split('=')[1] : defawlt;
}

function render(data) {
    const container = document.getElementById('dashboard');
    container.innerHTML = '';

    data.forEach(instances => {
        if (instances.length === 0) return;

        const s = instances[0].Service;

        if (s.Tags.includes('homelabdash.hide')) return;

        const slug = getTagValWithDefault(s.Tags, 'homelabdash.slug', s.Service);
        const extraUri = getTagValWithDefault(s.Tags, 'homelabdash.uri', '');

        const status = instances.every(inst =>
            inst.Checks.every(c => c.Status === 'passing')
        ) ? 'passing' : 'warning';

        const url = `https://${slug}.${DOMAIN}${extraUri}`;

        const card = document.createElement('a');
        card.className = `card ${status}`;
        card.href = url;
        card.target = "_blank";
        card.setAttribute('data-name', slug);

        card.innerHTML = `
            <div class="status-indicator"></div>
            <span class="service-name">${slug}</span>
            <span class="service-url">${url}</span>
            <div class="status-text">
                <div class="dot"></div>
                ${status === 'passing' ? 'HEALTHY' : 'DEGRADED'}
            </div>
        `;
        container.appendChild(card);
    });
}

function filter() {
    const query = document.getElementById('search').value.toLowerCase();
    document.querySelectorAll('.card').forEach(card => {
        const match = card.getAttribute('data-name').toLowerCase().includes(query);
        card.classList.toggle('hidden', !match);
    });
}

init();
