/**
 * Passerelle SMS — Twilio (recommandé) ou gateway HTTP générique.
 * Sans config : console + devCode renvoyé par l'API.
 */
export type SmsMessage = {
  to: string;
  body: string;
};

export interface SmsGateway {
  send(message: SmsMessage): Promise<void>;
}

class ConsoleSmsGateway implements SmsGateway {
  async send(message: SmsMessage): Promise<void> {
    console.info(`[sms:dev] → ${message.to}: ${message.body}`);
  }
}

/** Twilio REST API — https://www.twilio.com/docs/sms/api/message-resource */
class TwilioSmsGateway implements SmsGateway {
  constructor(
    private readonly accountSid: string,
    private readonly authToken: string,
    private readonly from: string
  ) {}

  async send(message: SmsMessage): Promise<void> {
    const url = `https://api.twilio.com/2010-04-01/Accounts/${this.accountSid}/Messages.json`;
    const auth = Buffer.from(`${this.accountSid}:${this.authToken}`).toString(
      "base64"
    );
    const body = new URLSearchParams({
      To: message.to,
      From: this.from,
      Body: message.body,
    });

    const res = await fetch(url, {
      method: "POST",
      headers: {
        Authorization: `Basic ${auth}`,
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body,
    });

    if (!res.ok) {
      const text = await res.text().catch(() => "");
      throw new Error(`Twilio SMS HTTP ${res.status}: ${text}`);
    }
  }
}

class HttpSmsGateway implements SmsGateway {
  constructor(
    private readonly url: string,
    private readonly apiKey: string
  ) {}

  async send(message: SmsMessage): Promise<void> {
    const res = await fetch(this.url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${this.apiKey}`,
      },
      body: JSON.stringify({
        to: message.to,
        message: message.body,
      }),
    });
    if (!res.ok) {
      const text = await res.text().catch(() => "");
      throw new Error(`SMS gateway HTTP ${res.status}: ${text}`);
    }
  }
}

export function createSmsGateway(): SmsGateway {
  const twilioSid = process.env.TWILIO_ACCOUNT_SID;
  const twilioToken = process.env.TWILIO_AUTH_TOKEN;
  const twilioFrom = process.env.TWILIO_FROM;

  if (twilioSid && twilioToken && twilioFrom) {
    console.info("[sms] Twilio activé");
    return new TwilioSmsGateway(twilioSid, twilioToken, twilioFrom);
  }

  const url = process.env.SMS_GATEWAY_URL;
  const key = process.env.SMS_API_KEY;
  if (url && key) {
    console.info("[sms] Gateway HTTP générique activé");
    return new HttpSmsGateway(url, key);
  }

  console.info("[sms] Mode dev (console) — pas de SMS réel");
  return new ConsoleSmsGateway();
}

export function isSmsConfigured(): boolean {
  const twilio =
    process.env.TWILIO_ACCOUNT_SID &&
    process.env.TWILIO_AUTH_TOKEN &&
    process.env.TWILIO_FROM;
  const http = process.env.SMS_GATEWAY_URL && process.env.SMS_API_KEY;
  return Boolean(twilio || http);
}

export const smsGateway = createSmsGateway();
