/**
 * Métriques Prometheus in-process (sans dépendance lourde).
 * Exposées sur GET /metrics — scrapables par Prometheus / Grafana Cloud / Render.
 */
type LabelMap = Record<string, string>;

function labelsKey(labels: LabelMap): string {
  return Object.keys(labels)
    .sort()
    .map((k) => `${k}=${labels[k]}`)
    .join(",");
}

class Counter {
  private readonly values = new Map<string, number>();

  constructor(
    readonly name: string,
    readonly help: string
  ) {}

  inc(labels: LabelMap = {}, by = 1): void {
    const key = labelsKey(labels);
    this.values.set(key, (this.values.get(key) ?? 0) + by);
  }

  render(): string {
    const lines = [`# HELP ${this.name} ${this.help}`, `# TYPE ${this.name} counter`];
    for (const [key, value] of this.values) {
      const lbl = key
        ? `{${key
            .split(",")
            .map((pair) => {
              const [k, v] = pair.split("=");
              return `${k}="${v.replace(/"/g, '\\"')}"`;
            })
            .join(",")}}`
        : "";
      lines.push(`${this.name}${lbl} ${value}`);
    }
    if (this.values.size === 0) lines.push(`${this.name} 0`);
    return lines.join("\n");
  }
}

class Histogram {
  private readonly buckets: number[];
  private readonly counts = new Map<string, number[]>();
  private readonly sums = new Map<string, number>();

  constructor(
    readonly name: string,
    readonly help: string,
    buckets = [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10]
  ) {
    this.buckets = buckets;
  }

  observe(seconds: number, labels: LabelMap = {}): void {
    const key = labelsKey(labels);
    let counts = this.counts.get(key);
    if (!counts) {
      counts = this.buckets.map(() => 0);
      this.counts.set(key, counts);
    }
    for (let i = 0; i < this.buckets.length; i++) {
      if (seconds <= this.buckets[i]) {
        counts[i] += 1;
        break;
      }
    }
    this.sums.set(key, (this.sums.get(key) ?? 0) + seconds);
  }

  render(): string {
    const lines = [
      `# HELP ${this.name} ${this.help}`,
      `# TYPE ${this.name} histogram`,
    ];
    for (const [key, counts] of this.counts) {
      const baseLabels = key
        ? key
            .split(",")
            .map((pair) => {
              const [k, v] = pair.split("=");
              return `${k}="${v.replace(/"/g, '\\"')}"`;
            })
            .join(",")
        : "";
      let cumulative = 0;
      for (let i = 0; i < this.buckets.length; i++) {
        cumulative += counts[i];
        const le = this.buckets[i];
        const lbl = baseLabels
          ? `{${baseLabels},le="${le}"}`
          : `{le="${le}"}`;
        lines.push(`${this.name}_bucket${lbl} ${cumulative}`);
      }
      const infLbl = baseLabels
        ? `{${baseLabels},le="+Inf"}`
        : `{le="+Inf"}`;
      const total = counts.reduce((a, b) => a + b, 0);
      lines.push(`${this.name}_bucket${infLbl} ${total}`);
      const sumLbl = baseLabels ? `{${baseLabels}}` : "";
      lines.push(`${this.name}_sum${sumLbl} ${this.sums.get(key) ?? 0}`);
      lines.push(`${this.name}_count${sumLbl} ${total}`);
    }
    return lines.join("\n");
  }
}

const httpRequests = new Counter(
  "neoforma_http_requests_total",
  "Total des requêtes HTTP"
);
const httpErrors = new Counter(
  "neoforma_http_errors_total",
  "Réponses HTTP 5xx"
);
const httpDuration = new Histogram(
  "neoforma_http_request_duration_seconds",
  "Durée des requêtes HTTP"
);
const startedAt = Date.now();

export function recordHttpRequest(opts: {
  method: string;
  route: string;
  statusCode: number;
  durationMs: number;
}): void {
  const route = sanitizeRoute(opts.route);
  const labels = {
    method: opts.method,
    route,
    status: String(opts.statusCode),
  };
  httpRequests.inc(labels);
  httpDuration.observe(opts.durationMs / 1000, {
    method: opts.method,
    route,
  });
  if (opts.statusCode >= 500) {
    httpErrors.inc({ method: opts.method, route });
  }
}

function sanitizeRoute(url: string): string {
  const path = url.split("?")[0] || "/";
  // Remplace les UUID pour limiter la cardinalité.
  return path.replace(
    /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gi,
    ":id"
  );
}

export function renderPrometheus(): string {
  const uptime = (Date.now() - startedAt) / 1000;
  return [
    "# HELP neoforma_up API NeoForma en vie",
    "# TYPE neoforma_up gauge",
    "neoforma_up 1",
    "# HELP neoforma_process_uptime_seconds Uptime du process",
    "# TYPE neoforma_process_uptime_seconds gauge",
    `neoforma_process_uptime_seconds ${uptime.toFixed(3)}`,
    httpRequests.render(),
    httpErrors.render(),
    httpDuration.render(),
    "",
  ].join("\n");
}
