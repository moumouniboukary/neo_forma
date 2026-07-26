import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { buildApp } from "../src/app.js";

describe("NeoForma API smoke", () => {
  it("GET /health", async () => {
    const app = await buildApp();
    const res = await app.inject({ method: "GET", url: "/health" });
    assert.equal(res.statusCode, 200);
    const body = res.json() as { status: string; service: string };
    assert.equal(body.status, "ok");
    assert.equal(body.service, "neoforma-api");
    await app.close();
  });

  it("GET /ready vérifie Postgres", async () => {
    const app = await buildApp();
    const res = await app.inject({ method: "GET", url: "/ready" });
    assert.ok([200, 503].includes(res.statusCode));
    const body = res.json() as {
      status: string;
      checks: { postgres: string; redis: string };
    };
    assert.ok(body.checks.postgres === "ok" || body.checks.postgres === "down");
    assert.ok(["ok", "skip", "down"].includes(body.checks.redis));
    await app.close();
  });

  it("GET /metrics expose Prometheus", async () => {
    const app = await buildApp();
    await app.inject({ method: "GET", url: "/health" });
    const res = await app.inject({ method: "GET", url: "/metrics" });
    assert.equal(res.statusCode, 200);
    assert.match(res.body, /neoforma_up/);
    assert.match(res.body, /neoforma_http_requests_total/);
    await app.close();
  });

  it("OpenAPI docs disponibles", async () => {
    const app = await buildApp();
    const res = await app.inject({ method: "GET", url: "/docs/json" });
    assert.equal(res.statusCode, 200);
    const body = res.json() as { info?: { title?: string } };
    assert.match(body.info?.title ?? "", /NeoForma/i);
    await app.close();
  });

  it("OTP register → verify → register → me", async () => {
    const app = await buildApp();
    const phone = `+22670${String(Date.now()).slice(-6)}`;

    const otpReq = await app.inject({
      method: "POST",
      url: "/auth/otp/request",
      payload: { phone, purpose: "register" },
    });
    assert.equal(otpReq.statusCode, 200);
    const { devCode } = otpReq.json() as { devCode?: string };
    assert.ok(devCode, "devCode attendu hors production");

    const otpVerify = await app.inject({
      method: "POST",
      url: "/auth/otp/verify",
      payload: { phone, code: devCode, purpose: "register" },
    });
    assert.equal(otpVerify.statusCode, 200);
    const { otpToken } = otpVerify.json() as { otpToken: string };

    const register = await app.inject({
      method: "POST",
      url: "/auth/register",
      payload: {
        phone,
        pin: "2580",
        otpToken,
        displayName: "Test NeoForma",
        language: "fr",
      },
    });
    assert.equal(register.statusCode, 200);
    const tokens = register.json() as {
      accessToken: string;
      user: { onboardingCompleted: boolean; displayName?: string };
    };
    assert.ok(tokens.accessToken);
    assert.equal(tokens.user.onboardingCompleted, false);
    assert.equal(tokens.user.displayName, "Test NeoForma");

    const me = await app.inject({
      method: "GET",
      url: "/me",
      headers: { authorization: `Bearer ${tokens.accessToken}` },
    });
    assert.equal(me.statusCode, 200);
    await app.close();
  });
});
