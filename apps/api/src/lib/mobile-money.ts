/**
 * Passerelles Mobile Money — Orange Money / Moov Money (Burkina).
 * Credentials via env ; sinon StubGateway pour le pilote / tests.
 */
export type MmProvider = "orange" | "moov" | "stub";

export type MmTransferRequest = {
  provider: MmProvider;
  phone: string;
  amountFcfa: number;
  reference: string;
  /** cash_in = dépôt vers wallet ; cash_out = retrait */
  direction: "cash_in" | "cash_out";
};

export type MmTransferResult = {
  provider: MmProvider;
  externalId: string;
  status: "pending" | "success" | "failed";
  message?: string;
};

export interface MobileMoneyGateway {
  transfer(req: MmTransferRequest): Promise<MmTransferResult>;
}

const FETCH_MS = 12_000;

async function fetchJson(
  url: string,
  init: RequestInit
): Promise<{ ok: boolean; status: number; body: unknown; text: string }> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), FETCH_MS);
  try {
    const res = await fetch(url, { ...init, signal: controller.signal });
    const text = await res.text().catch(() => "");
    let body: unknown = {};
    try {
      body = text ? JSON.parse(text) : {};
    } catch {
      body = { raw: text };
    }
    return { ok: res.ok, status: res.status, body, text };
  } finally {
    clearTimeout(timer);
  }
}

class StubMmGateway implements MobileMoneyGateway {
  async transfer(req: MmTransferRequest): Promise<MmTransferResult> {
    console.info(
      `[mm:stub] ${req.direction} ${req.amountFcfa} FCFA → ${req.phone} (${req.provider})`
    );
    return {
      provider: "stub",
      externalId: `stub-${Date.now()}`,
      status: "success",
      message: "Mode test — aucun débit réel",
    };
  }
}

/** OAuth client-credentials Orange (optionnel) puis Bearer sur /transfers. */
async function resolveOrangeBearer(apiKey: string): Promise<string> {
  const tokenUrl = process.env.ORANGE_MM_TOKEN_URL?.trim();
  const clientId = process.env.ORANGE_MM_CLIENT_ID?.trim();
  const clientSecret = process.env.ORANGE_MM_CLIENT_SECRET?.trim();
  if (!tokenUrl || !clientId || !clientSecret) return apiKey;

  const basic = Buffer.from(`${clientId}:${clientSecret}`).toString("base64");
  const { ok, body, text, status } = await fetchJson(tokenUrl, {
    method: "POST",
    headers: {
      Authorization: `Basic ${basic}`,
      "Content-Type": "application/x-www-form-urlencoded",
      Accept: "application/json",
    },
    body: "grant_type=client_credentials",
  });
  if (!ok) {
    throw new Error(`Orange token HTTP ${status}: ${text.slice(0, 180)}`);
  }
  const token = (body as { access_token?: string }).access_token;
  if (!token) throw new Error("Orange token: access_token manquant");
  return token;
}

class OrangeMmGateway implements MobileMoneyGateway {
  constructor(
    private readonly apiUrl: string,
    private readonly apiKey: string
  ) {}

  async transfer(req: MmTransferRequest): Promise<MmTransferResult> {
    try {
      const bearer = await resolveOrangeBearer(this.apiKey);
      const { ok, status, body, text } = await fetchJson(
        `${this.apiUrl.replace(/\/$/, "")}/transfers`,
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${bearer}`,
            "Content-Type": "application/json",
            Accept: "application/json",
          },
          body: JSON.stringify({
            msisdn: req.phone.replace(/\s/g, ""),
            amount: req.amountFcfa,
            currency: "XOF",
            reference: req.reference,
            type: req.direction,
            country: "BF",
          }),
        }
      );
      if (!ok) {
        return {
          provider: "orange",
          externalId: "",
          status: "failed",
          message: `Orange HTTP ${status}: ${text.slice(0, 200)}`,
        };
      }
      const b = body as {
        id?: string;
        transactionId?: string;
        status?: string;
        state?: string;
      };
      const st = (b.status ?? b.state ?? "").toUpperCase();
      return {
        provider: "orange",
        externalId: b.id ?? b.transactionId ?? req.reference,
        status:
          st === "SUCCESS" || st === "SUCCEEDED" || st === "COMPLETED"
            ? "success"
            : "pending",
      };
    } catch (err) {
      return {
        provider: "orange",
        externalId: "",
        status: "failed",
        message: err instanceof Error ? err.message : "Orange error",
      };
    }
  }
}

class MoovMmGateway implements MobileMoneyGateway {
  constructor(
    private readonly apiUrl: string,
    private readonly apiKey: string
  ) {}

  async transfer(req: MmTransferRequest): Promise<MmTransferResult> {
    try {
      const { ok, status, body, text } = await fetchJson(
        `${this.apiUrl.replace(/\/$/, "")}/v1/payments`,
        {
          method: "POST",
          headers: {
            "X-API-Key": this.apiKey,
            "Content-Type": "application/json",
            Accept: "application/json",
          },
          body: JSON.stringify({
            phone: req.phone.replace(/\s/g, ""),
            amount: req.amountFcfa,
            currency: "XOF",
            ref: req.reference,
            direction: req.direction,
            country: "BF",
          }),
        }
      );
      if (!ok) {
        return {
          provider: "moov",
          externalId: "",
          status: "failed",
          message: `Moov HTTP ${status}: ${text.slice(0, 200)}`,
        };
      }
      const b = body as {
        transactionId?: string;
        id?: string;
        state?: string;
        status?: string;
      };
      const st = (b.state ?? b.status ?? "").toUpperCase();
      return {
        provider: "moov",
        externalId: b.transactionId ?? b.id ?? req.reference,
        status:
          st === "COMPLETED" || st === "SUCCESS" || st === "SUCCEEDED"
            ? "success"
            : "pending",
      };
    } catch (err) {
      return {
        provider: "moov",
        externalId: "",
        status: "failed",
        message: err instanceof Error ? err.message : "Moov error",
      };
    }
  }
}

export function createMobileMoneyGateway(
  provider: MmProvider = "stub"
): MobileMoneyGateway {
  if (provider === "orange") {
    const url = process.env.ORANGE_MM_URL;
    const key = process.env.ORANGE_MM_API_KEY;
    if (url && key) return new OrangeMmGateway(url, key);
  }
  if (provider === "moov") {
    const url = process.env.MOOV_MM_URL;
    const key = process.env.MOOV_MM_API_KEY;
    if (url && key) return new MoovMmGateway(url, key);
  }
  return new StubMmGateway();
}

export function isMmConfigured(provider: MmProvider): boolean {
  if (provider === "orange") {
    return Boolean(process.env.ORANGE_MM_URL && process.env.ORANGE_MM_API_KEY);
  }
  if (provider === "moov") {
    return Boolean(process.env.MOOV_MM_URL && process.env.MOOV_MM_API_KEY);
  }
  return true;
}
