/**
 * Client HTTP vers le service ML NeoScore (solvabilité).
 * Activé uniquement si SCORING_ML_URL est défini.
 */
import type { NeoScoreResult, ScoreFeatures } from "@neoforma/shared";
import { config } from "../config.js";

export type MlScoreResponse = {
  score: number;
  segment: string;
  eligible: boolean;
  threshold: number;
  criteria: {
    regularite: number;
    volume: number;
    dettes: number;
    croissance: number;
  };
  engine: "ml";
  modelVersion?: string | null;
  pDefault?: number;
  computedAt: string;
};

export type MlTrainSample = {
  features: ScoreFeatures;
  outcome?: string | null;
  default?: number | null;
};

function baseUrl(): string | null {
  const u = config.scoringMlUrl?.trim();
  return u ? u.replace(/\/$/, "") : null;
}

export function isMlScoringEnabled(): boolean {
  return Boolean(baseUrl());
}

export async function mlHealth(): Promise<{
  ok: boolean;
  modelReady?: boolean;
  modelVersion?: string;
}> {
  const base = baseUrl();
  if (!base) return { ok: false };
  try {
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), config.scoringMlTimeoutMs);
    const res = await fetch(`${base}/health`, { signal: ctrl.signal });
    clearTimeout(t);
    if (!res.ok) return { ok: false };
    const body = (await res.json()) as {
      modelReady?: boolean;
      modelVersion?: string;
    };
    return {
      ok: true,
      modelReady: body.modelReady,
      modelVersion: body.modelVersion,
    };
  } catch {
    return { ok: false };
  }
}

export async function mlScore(
  features: ScoreFeatures
): Promise<MlScoreResponse | null> {
  const base = baseUrl();
  if (!base) return null;
  try {
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), config.scoringMlTimeoutMs);
    const res = await fetch(`${base}/score`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ features }),
      signal: ctrl.signal,
    });
    clearTimeout(t);
    if (!res.ok) return null;
    const body = (await res.json()) as MlScoreResponse;
    if (
      typeof body.score !== "number" ||
      !body.criteria ||
      typeof body.eligible !== "boolean"
    ) {
      return null;
    }
    return body;
  } catch {
    return null;
  }
}

export async function mlTrain(opts: {
  samples: MlTrainSample[];
  nSynthetic?: number;
}): Promise<Record<string, unknown> | null> {
  const base = baseUrl();
  if (!base) return null;
  try {
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), Math.max(config.scoringMlTimeoutMs, 60_000));
    const res = await fetch(`${base}/train`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        samples: opts.samples,
        nSynthetic: opts.nSynthetic ?? 200,
      }),
      signal: ctrl.signal,
    });
    clearTimeout(t);
    if (!res.ok) return null;
    return (await res.json()) as Record<string, unknown>;
  } catch {
    return null;
  }
}

/** Fusionne réponse ML + historique côté API. */
export function mlToNeoScoreResult(
  ml: MlScoreResponse,
  history: Array<{ month: string; score: number }>
): NeoScoreResult & { engine: "ml"; modelVersion?: string | null } {
  const segment = (["A", "B", "C", "D"].includes(ml.segment)
    ? ml.segment
    : "B") as NeoScoreResult["segment"];
  return {
    score: Math.round(Math.max(0, Math.min(100, ml.score))),
    segment,
    eligible: ml.eligible,
    threshold: 50,
    criteria: {
      regularite: ml.criteria.regularite,
      volume: ml.criteria.volume,
      dettes: ml.criteria.dettes,
      croissance: ml.criteria.croissance,
    },
    history,
    computedAt: ml.computedAt || new Date().toISOString(),
    engine: "ml",
    modelVersion: ml.modelVersion ?? null,
  };
}
