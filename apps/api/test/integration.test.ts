import { describe, it, before, after } from "node:test";
import assert from "node:assert/strict";
import type { FastifyInstance } from "fastify";
import { buildApp } from "../src/app.js";

/** Téléphone Burkina valide unique : +226 + 8 chiffres (préfixe 7). */
let seq = 0;
function uniquePhone(): string {
  seq += 1;
  const tail = `${Date.now()}${seq}`.slice(-7); // 7 chiffres
  return `+2267${tail}`;
}

type Session = { accessToken: string; phone: string; pin: string };

async function otpToken(
  app: FastifyInstance,
  phone: string,
  purpose: "register" | "login" | "reset"
): Promise<string> {
  const req = await app.inject({
    method: "POST",
    url: "/auth/otp/request",
    payload: { phone, purpose },
  });
  const { devCode } = req.json() as { devCode?: string };
  assert.ok(devCode, "devCode attendu hors production");
  const verify = await app.inject({
    method: "POST",
    url: "/auth/otp/verify",
    payload: { phone, code: devCode, purpose },
  });
  const { otpToken } = verify.json() as { otpToken: string };
  return otpToken;
}

async function registerUser(app: FastifyInstance): Promise<Session> {
  const phone = uniquePhone();
  const pin = "2580";
  const token = await otpToken(app, phone, "register");
  const res = await app.inject({
    method: "POST",
    url: "/auth/register",
    payload: { phone, pin, otpToken: token, displayName: "Test", language: "fr" },
  });
  assert.equal(res.statusCode, 200);
  const { accessToken } = res.json() as { accessToken: string };
  return { accessToken, phone, pin };
}

function authHeaders(s: Session) {
  return { authorization: `Bearer ${s.accessToken}` };
}

async function completeOnboarding(app: FastifyInstance, s: Session): Promise<void> {
  const patch = await app.inject({
    method: "PATCH",
    url: "/me",
    headers: authHeaders(s),
    payload: {
      displayName: "Test Onboard",
      metier: "commerce",
      anciennete: "3_5",
      caJour: "15_30k",
      onboardingCompleted: true,
      language: "fr",
    },
  });
  assert.equal(patch.statusCode, 200, patch.body);
}

describe("Ledger", () => {
  let app: FastifyInstance;
  before(async () => {
    app = await buildApp();
  });
  after(async () => {
    await app.close();
  });

  it("crée une vente, la liste, et gère une créance + règlement", async () => {
    const s = await registerUser(app);

    const vente = await app.inject({
      method: "POST",
      url: "/operations",
      headers: authHeaders(s),
      payload: { type: "vente", amountFcfa: 3000, label: "Vente test" },
    });
    assert.equal(vente.statusCode, 201, vente.body);

    const creance = await app.inject({
      method: "POST",
      url: "/operations",
      headers: authHeaders(s),
      payload: { type: "creance", amountFcfa: 5000, clientName: "Awa" },
    });
    assert.equal(creance.statusCode, 201, creance.body);
    const creanceId = (creance.json() as { id: string }).id;

    const list = await app.inject({
      method: "GET",
      url: "/operations",
      headers: authHeaders(s),
    });
    assert.equal(list.statusCode, 200);
    assert.ok((list.json() as unknown[]).length >= 2);

    const settle = await app.inject({
      method: "POST",
      url: `/operations/${creanceId}/settle`,
      headers: authHeaders(s),
    });
    assert.equal(settle.statusCode, 200, settle.body);
    assert.equal((settle.json() as { statutCreance: string }).statutCreance, "reglee");
  });

  it("refuse une créance sans client (RM-O03)", async () => {
    const s = await registerUser(app);
    const res = await app.inject({
      method: "POST",
      url: "/operations",
      headers: authHeaders(s),
      payload: { type: "creance", amountFcfa: 1000 },
    });
    assert.equal(res.statusCode, 400);
  });

  it("CRUD clients", async () => {
    const s = await registerUser(app);
    const create = await app.inject({
      method: "POST",
      url: "/clients",
      headers: authHeaders(s),
      payload: { nom: "Client A", telephone: "+22670000000" },
    });
    assert.equal(create.statusCode, 201, create.body);
    const id = (create.json() as { id: string }).id;

    const patch = await app.inject({
      method: "PATCH",
      url: `/clients/${id}`,
      headers: authHeaders(s),
      payload: { note: "bon payeur" },
    });
    assert.equal(patch.statusCode, 200);

    const list = await app.inject({
      method: "GET",
      url: "/clients",
      headers: authHeaders(s),
    });
    assert.equal(list.statusCode, 200);
    assert.ok((list.json() as unknown[]).length >= 1);

    const del = await app.inject({
      method: "DELETE",
      url: `/clients/${id}`,
      headers: authHeaders(s),
    });
    assert.equal(del.statusCode, 204);
  });

  it("exige l'authentification", async () => {
    const res = await app.inject({ method: "GET", url: "/operations" });
    assert.equal(res.statusCode, 401);
  });
});

describe("Consent & Credit", () => {
  let app: FastifyInstance;
  before(async () => {
    app = await buildApp();
  });
  after(async () => {
    await app.close();
  });

  it("liste, accorde puis révoque un consentement", async () => {
    const s = await registerUser(app);

    const list = await app.inject({
      method: "GET",
      url: "/me/consents",
      headers: authHeaders(s),
    });
    assert.equal(list.statusCode, 200);

    const grant = await app.inject({
      method: "PUT",
      url: "/me/consents/partage_imf",
      headers: authHeaders(s),
      payload: { accorde: true, versionPolitique: "v1" },
    });
    assert.equal(grant.statusCode, 200, grant.body);
    assert.equal((grant.json() as { accorde: boolean }).accorde, true);

    const revoke = await app.inject({
      method: "POST",
      url: "/me/consents/partage_imf/revoke",
      headers: authHeaders(s),
    });
    assert.equal(revoke.statusCode, 200);
    assert.equal((revoke.json() as { accorde: boolean }).accorde, false);
  });

  it("offre de crédit disponible (structure)", async () => {
    const s = await registerUser(app);
    const offer = await app.inject({
      method: "GET",
      url: "/credit/offer",
      headers: authHeaders(s),
    });
    assert.equal(offer.statusCode, 200, offer.body);
    const body = offer.json() as { eligible: boolean; maxFcfa: number };
    assert.equal(typeof body.eligible, "boolean");
  });

  it("bloque une demande sans onboarding", async () => {
    const s = await registerUser(app);
    const res = await app.inject({
      method: "POST",
      url: "/credit/applications",
      headers: authHeaders(s),
      payload: { amountFcfa: 100000, purpose: "stock", repayment: "mensuel" },
    });
    assert.equal(res.statusCode, 403);
    assert.equal((res.json() as { error: string }).error, "onboarding_required");
  });

  it("bloque une demande sans consentement partage_imf", async () => {
    const s = await registerUser(app);
    await completeOnboarding(app, s);
    const res = await app.inject({
      method: "POST",
      url: "/credit/applications",
      headers: authHeaders(s),
      payload: { amountFcfa: 100000, purpose: "stock", repayment: "mensuel" },
    });
    assert.equal(res.statusCode, 403);
    assert.equal((res.json() as { error: string }).error, "consent_required");
  });
});

describe("Sync offline", () => {
  let app: FastifyInstance;
  before(async () => {
    app = await buildApp();
  });
  after(async () => {
    await app.close();
  });

  it("push idempotent + pull + queue", async () => {
    const s = await registerUser(app);
    const mutationId = crypto.randomUUID();
    const payload = {
      mutations: [
        {
          clientMutationId: mutationId,
          kind: "create_operation",
          payload: { type: "vente", amountFcfa: 1500, label: "Sync" },
          createdAt: new Date().toISOString(),
        },
      ],
    };

    const push1 = await app.inject({
      method: "POST",
      url: "/sync/push",
      headers: authHeaders(s),
      payload,
    });
    assert.equal(push1.statusCode, 200, push1.body);

    // Rejeu : même clientMutationId ne doit pas dupliquer.
    const push2 = await app.inject({
      method: "POST",
      url: "/sync/push",
      headers: authHeaders(s),
      payload,
    });
    assert.equal(push2.statusCode, 200);

    const pull = await app.inject({
      method: "GET",
      url: "/sync/pull?limit=50",
      headers: authHeaders(s),
    });
    assert.equal(pull.statusCode, 200);
    const pulled = pull.json() as {
      operations: unknown[];
      clients: unknown[];
      nextSince: string;
      hasMore: boolean;
    };
    assert.equal(pulled.operations.length, 1, "une seule opération malgré le rejeu");
    assert.ok(Array.isArray(pulled.clients));
    assert.ok(pulled.nextSince);
  });

  it("push create_client hors ligne", async () => {
    const s = await registerUser(app);
    const mutationId = crypto.randomUUID();
    const push = await app.inject({
      method: "POST",
      url: "/sync/push",
      headers: authHeaders(s),
      payload: {
        mutations: [
          {
            clientMutationId: mutationId,
            kind: "create_client",
            payload: { nom: "Client Sync", telephone: "+22670001122" },
            createdAt: new Date().toISOString(),
          },
        ],
      },
    });
    assert.equal(push.statusCode, 200, push.body);
    const body = push.json() as { accepted: string[] };
    assert.ok(body.accepted.includes(mutationId));

    const list = await app.inject({
      method: "GET",
      url: "/clients",
      headers: authHeaders(s),
    });
    assert.equal(list.statusCode, 200);
    const clients = list.json() as Array<{ nom: string }>;
    assert.ok(clients.some((c) => c.nom === "Client Sync"));
  });
});

describe("RGPD privacy", () => {
  let app: FastifyInstance;
  before(async () => {
    app = await buildApp();
  });
  after(async () => {
    await app.close();
  });

  it("exporte puis supprime le compte", async () => {
    const s = await registerUser(app);
    await app.inject({
      method: "POST",
      url: "/operations",
      headers: authHeaders(s),
      payload: { type: "vente", amountFcfa: 1000, label: "Export" },
    });

    const exp = await app.inject({
      method: "GET",
      url: "/me/export",
      headers: authHeaders(s),
    });
    assert.equal(exp.statusCode, 200, exp.body);
    const data = exp.json() as {
      profile: { phone: string };
      operations: unknown[];
    };
    assert.equal(data.profile.phone, s.phone);
    assert.ok(data.operations.length >= 1);

    const del = await app.inject({
      method: "DELETE",
      url: "/me",
      headers: authHeaders(s),
      payload: { pin: s.pin, confirm: true },
    });
    assert.equal(del.statusCode, 204, del.body);

    const me = await app.inject({
      method: "GET",
      url: "/me",
      headers: authHeaders(s),
    });
    assert.equal(me.statusCode, 401);
  });
});

describe("MFA — verrouillage PIN", () => {
  let app: FastifyInstance;
  before(async () => {
    app = await buildApp();
  });
  after(async () => {
    await app.close();
  });

  it("verrouille après 5 PIN erronés", async () => {
    const s = await registerUser(app);
    const token = await otpToken(app, s.phone, "login");

    let lockedSeen = false;
    for (let i = 0; i < 6; i += 1) {
      const res = await app.inject({
        method: "POST",
        url: "/auth/login",
        payload: { phone: s.phone, pin: "9017", otpToken: token },
      });
      // 401 tant que non verrouillé, 423/403 une fois verrouillé.
      if (res.statusCode === 423 || res.statusCode === 403) {
        lockedSeen = true;
        break;
      }
      assert.equal(res.statusCode, 401);
    }
    assert.ok(lockedSeen, "le compte doit finir verrouillé");
  });
});

describe("Kobo ingestion", () => {
  let app: FastifyInstance;
  const KEY = "test-kobo-key";
  before(async () => {
    process.env.KOBO_API_KEY = KEY;
    app = await buildApp();
  });
  after(async () => {
    delete process.env.KOBO_API_KEY;
    await app.close();
  });

  it("refuse sans clé", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/kobo/import",
      payload: [{ _uuid: "x" }],
    });
    assert.equal(res.statusCode, 401);
  });

  it("importe, dédoublonne et rattache au profil existant", async () => {
    const s = await registerUser(app);
    const submissionId = crypto.randomUUID();
    const submission = {
      _uuid: submissionId,
      telephone: s.phone,
      metier: "artisanat",
      anciennete: "6_10",
      ca_jour: "30_60k",
      tontine: "oui",
      tontine_cotis: 8000,
      mobile_money: "regulier",
    };

    const imp1 = await app.inject({
      method: "POST",
      url: "/kobo/import",
      headers: { "x-kobo-key": KEY },
      payload: [submission],
    });
    assert.equal(imp1.statusCode, 200, imp1.body);
    const r1 = imp1.json() as {
      imported: number;
      matchedProfiles: number;
      duplicates: number;
    };
    assert.equal(r1.imported, 1);
    assert.equal(r1.matchedProfiles, 1);

    // Rejeu : idempotent.
    const imp2 = await app.inject({
      method: "POST",
      url: "/kobo/import",
      headers: { "x-kobo-key": KEY },
      payload: [submission],
    });
    const r2 = imp2.json() as { imported: number; duplicates: number };
    assert.equal(r2.imported, 0);
    assert.equal(r2.duplicates, 1);

    // Le profil du travailleur a bien été enrichi.
    const me = await app.inject({
      method: "GET",
      url: "/me",
      headers: authHeaders(s),
    });
    const profile = me.json() as { metier?: string };
    assert.equal(profile.metier, "artisanat");
  });
});

describe("Sécurité", () => {
  let app: FastifyInstance;
  before(async () => {
    app = await buildApp();
  });
  after(async () => {
    await app.close();
  });

  it("404 structuré sur route inconnue", async () => {
    const res = await app.inject({ method: "GET", url: "/route-inexistante" });
    assert.equal(res.statusCode, 404);
    assert.equal((res.json() as { error: string }).error, "not_found");
  });

  it("en-têtes helmet présents", async () => {
    const res = await app.inject({ method: "GET", url: "/health" });
    assert.ok(res.headers["x-content-type-options"], "helmet doit poser des en-têtes");
  });
});
