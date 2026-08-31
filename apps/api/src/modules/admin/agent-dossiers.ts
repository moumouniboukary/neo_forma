import type { PrismaClient } from "@prisma/client";
import type { AgentScoreInput } from "@neoforma/shared";
import {
  calibrateAgentScorecard,
  type AgentScoreCalibration,
  type AgentLabeledSample,
} from "@neoforma/neoscore";

const AGENT_SOURCE = "agent_scorecard";

export class AgentDossierService {
  constructor(private readonly prisma: PrismaClient) {}

  async list(opts?: {
    outcome?: string;
    limit?: number;
  }): Promise<unknown[]> {
    return this.prisma.agentDossier.findMany({
      where: opts?.outcome ? { outcome: opts.outcome } : undefined,
      orderBy: { createdAt: "desc" },
      take: Math.min(500, opts?.limit ?? 100),
      select: {
        id: true,
        clientNom: true,
        clientTelephone: true,
        score: true,
        recommendation: true,
        statut: true,
        outcome: true,
        outcomeAt: true,
        engine: true,
        modelVersion: true,
        montantDemandeFcfa: true,
        createdAt: true,
      },
    });
  }

  async setOutcome(
    id: string,
    outcome: "rembourse_ok" | "defaut" | "en_cours",
    note?: string
  ) {
    const existing = await this.prisma.agentDossier.findUnique({
      where: { id },
    });
    if (!existing) {
      throw Object.assign(new Error("Dossier introuvable"), {
        code: "not_found",
        statusCode: 404,
      });
    }
    return this.prisma.agentDossier.update({
      where: { id },
      data: {
        outcome,
        outcomeAt: new Date(),
        outcomeNote: note?.trim() || null,
      },
    });
  }

  /** Échantillons labellisés rembourse_ok / defaut pour calibrage. */
  async exportLabeledSamples(limit = 5000): Promise<AgentLabeledSample[]> {
    const rows = await this.prisma.agentDossier.findMany({
      where: { outcome: { in: ["rembourse_ok", "defaut"] } },
      orderBy: { outcomeAt: "desc" },
      take: limit,
      select: { inputJson: true, outcome: true },
    });
    const out: AgentLabeledSample[] = [];
    for (const row of rows) {
      if (row.outcome !== "rembourse_ok" && row.outcome !== "defaut") continue;
      out.push({
        input: row.inputJson as AgentScoreInput,
        outcome: row.outcome,
      });
    }
    return out;
  }

  async getActiveCalibration(): Promise<AgentScoreCalibration | null> {
    const run = await this.prisma.mlModelRun.findFirst({
      where: { source: AGENT_SOURCE, active: true },
      orderBy: { trainedAt: "desc" },
    });
    if (!run?.payloadJson) return null;
    return run.payloadJson as unknown as AgentScoreCalibration;
  }

  async calibrateAndActivate(opts?: {
    notes?: string;
  }): Promise<{
    calibration: AgentScoreCalibration;
    run: { id: string; version: string };
    labeledUsed: number;
  }> {
    const samples = await this.exportLabeledSamples(5000);
    const calibration = calibrateAgentScorecard(samples, {
      notes: opts?.notes,
    });

    await this.prisma.mlModelRun.updateMany({
      where: { source: AGENT_SOURCE },
      data: { active: false },
    });
    const run = await this.prisma.mlModelRun.create({
      data: {
        version: calibration.version,
        nSamples: calibration.nSamples,
        nDefaults: calibration.nDefaults,
        auc: calibration.auc,
        source: AGENT_SOURCE,
        notes:
          opts?.notes ??
          `Calibrage scorecard DigiCoop — ${calibration.nSamples} labels`,
        payloadJson: calibration as object,
        active: true,
      },
    });

    return {
      calibration,
      run: { id: run.id, version: run.version },
      labeledUsed: samples.length,
    };
  }
}
