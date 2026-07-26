const QUEUE_KEY = "neoforma.offlineQueue";

export type QueuedMutation = {
  clientMutationId: string;
  kind: "create_operation";
  payload: Record<string, unknown>;
  createdAt: string;
};

function readQueue(): QueuedMutation[] {
  try {
    return JSON.parse(localStorage.getItem(QUEUE_KEY) ?? "[]") as QueuedMutation[];
  } catch {
    return [];
  }
}

function writeQueue(q: QueuedMutation[]) {
  localStorage.setItem(QUEUE_KEY, JSON.stringify(q));
}

export const offlineQueue = {
  enqueue(mutation: QueuedMutation) {
    const q = readQueue();
    q.push(mutation);
    writeQueue(q);
  },
  list() {
    return readQueue();
  },
  clearAccepted(ids: string[]) {
    writeQueue(readQueue().filter((m) => !ids.includes(m.clientMutationId)));
  },
  count() {
    return readQueue().length;
  },
};
