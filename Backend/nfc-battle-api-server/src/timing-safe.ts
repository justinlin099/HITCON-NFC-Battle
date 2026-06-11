const textEncoder = new TextEncoder();

export function timingSafeEqual(left: Uint8Array, right: Uint8Array) {
  if (typeof crypto.subtle.timingSafeEqual !== "function") {
    return constantTimeEqual(left, right);
  }

  const lengthsMatch = left.byteLength === right.byteLength;
  return lengthsMatch
    ? crypto.subtle.timingSafeEqual(left, right)
    : !crypto.subtle.timingSafeEqual(left, left);
}

export function timingSafeStringEqual(left: string, right: string) {
  return timingSafeEqual(textEncoder.encode(left), textEncoder.encode(right));
}

function constantTimeEqual(left: Uint8Array, right: Uint8Array) {
  let diff = left.length ^ right.length;
  const length = Math.max(left.length, right.length);

  for (let index = 0; index < length; index += 1) {
    diff |= (left[index] ?? 0) ^ (right[index] ?? 0);
  }

  return diff === 0;
}
