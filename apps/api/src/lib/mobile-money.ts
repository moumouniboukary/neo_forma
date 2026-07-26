/**
 * Passerelles Mobile Money — Orange Money / Moov Money (Burkina).
 * Sans credentials : StubGateway (log + id fictif) pour piloter l'intégration.
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

/** Orange Money Burkina — placeholder REST (credentials ORANGE_MM_*). */
class OrangeMmGateway implements MobileMoneyGateway {
  constructor(
    private readonly apiUrl: string,
    private readonly apiKey: string
  ) {}

  async transfer(req: MmTransferRequest): Promise<MmTransferResult> {
    const res = await fetch(`${this.apiUrl}/transfers`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${this.apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        msisdn: req.phone,
        amount: req.amountFcfa,
        currency: "XOF",
        reference: req.reference,
        type: req.direction,
      }),
    });
    if (!res.ok) {
      const text = await res.text().catch(() => "");
      return {
        provider: "orange",
        externalId: "",
        status: "failed",
        message: `Orange HTTP ${res.status}: ${text}`,
      };
    }
    const body = (await res.json()) as { id?: string; status?: string };
    return {
      provider: "orange",
      externalId: body.id ?? req.reference,
      status: body.status === "SUCCESS" ? "success" : "pending",
    };
  }
}

/** Moov Money Burkina — placeholder REST (credentials MOOV_MM_*). */
class MoovMmGateway implements MobileMoneyGateway {
  constructor(
    private readonly apiUrl: string,
    private readonly apiKey: string
  ) {}

  async transfer(req: MmTransferRequest): Promise<MmTransferResult> {
    const res = await fetch(`${this.apiUrl}/v1/payments`, {
      method: "POST",
      headers: {
        "X-API-Key": this.apiKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        phone: req.phone,
        amount: req.amountFcfa,
        ref: req.reference,
        direction: req.direction,
      }),
    });
    if (!res.ok) {
      const text = await res.text().catch(() => "");
      return {
        provider: "moov",
        externalId: "",
        status: "failed",
        message: `Moov HTTP ${res.status}: ${text}`,
      };
    }
    const body = (await res.json()) as { transactionId?: string; state?: string };
    return {
      provider: "moov",
      externalId: body.transactionId ?? req.reference,
      status: body.state === "COMPLETED" ? "success" : "pending",
    };
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
