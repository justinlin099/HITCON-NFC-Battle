export function nowIso() {
  return new Date().toISOString();
}

export function newId(prefix: string) {
  return `${prefix}_${crypto.randomUUID()}`;
}

export function newFreezeId() {
  const compactTime = nowIso().replace(/[-:.TZ]/g, "");
  return `freeze_${compactTime}_${crypto.randomUUID()}`;
}

export function newNfcTagKey() {
  const bytes = new Uint8Array(6);
  crypto.getRandomValues(bytes);
  return [...bytes].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}
