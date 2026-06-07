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
