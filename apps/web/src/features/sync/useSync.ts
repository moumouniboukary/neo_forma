import { useCallback, useEffect, useState } from "react";
import { api } from "@/shared/lib/api";
import { offlineQueue } from "@/shared/lib/offlineQueue";

const PULL_SINCE_KEY = "neoforma.sync.since";

type SyncPushResult = {
  accepted: string[];
  rejected: Array<{ clientMutationId: string; reason: string }>;
  serverTime: string;
};

type SyncPullResult = {
  operations: unknown[];
  serverTime: string;
};

export function useSync() {
  const [pending, setPending] = useState(offlineQueue.count());
  const [lastError, setLastError] = useState<string | null>(null);

  const refresh = useCallback(() => setPending(offlineQueue.count()), []);

  const pull = useCallback(async () => {
    if (!navigator.onLine) return;
    const since = localStorage.getItem(PULL_SINCE_KEY) ?? new Date(0).toISOString();
    try {
      const res = await api.get<SyncPullResult>(
        `/sync/pull?since=${encodeURIComponent(since)}`
      );
      localStorage.setItem(PULL_SINCE_KEY, res.serverTime);
    } catch {
      /* pull best-effort */
    }
  }, []);

  const flush = useCallback(async () => {
    const mutations = offlineQueue.list();
    if (!navigator.onLine) {
      refresh();
      return;
    }
    try {
      if (mutations.length) {
        const res = await api.post<SyncPushResult>("/sync/push", { mutations });
        offlineQueue.clearAccepted(res.accepted);
        if (res.rejected.length) {
          offlineQueue.clearAccepted(
            res.rejected.map((r) => r.clientMutationId)
          );
          setLastError(res.rejected[0]?.reason ?? "Sync partielle");
        } else {
          setLastError(null);
        }
      }
      await pull();
    } catch {
      // keep queue
    } finally {
      refresh();
    }
  }, [pull, refresh]);

  useEffect(() => {
    void flush();
    const onOnline = () => void flush();
    window.addEventListener("online", onOnline);
    return () => window.removeEventListener("online", onOnline);
  }, [flush]);

  return { pending, flush, pull, refresh, lastError };
}
