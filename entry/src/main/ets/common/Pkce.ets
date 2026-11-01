import { util } from '@kit.ArkTS';

/**
 * PKCE 工具：SHA-256 与 base64url 全部用纯 TS 实现。
 * 随机源用 util.generateRandomUUID（RFC 4122 v4，系统随机源），
 * 避免 cryptoFramework 在部分设备上 syscap 不可用。
 */

const K: number[] = [
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
];

function rotr(x: number, n: number): number {
  return ((x >>> n) | (x << (32 - n))) >>> 0;
}

/** 标准 SHA-256，返回 32 字节摘要 */
export function sha256(input: Uint8Array): Uint8Array {
  const h: number[] = [
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
  ];

  const bitLen: number = input.length * 8;
  const paddedLen: number = (((input.length + 8) >> 6) + 1) * 64;
  const buf: Uint8Array = new Uint8Array(paddedLen);
  buf.set(input, 0);
  buf[input.length] = 0x80;
  // 末尾 8 字节为原始比特长度（大端 64 位）；本项目长度远小于 2^32，高 4 字节恒 0
  buf[paddedLen - 4] = (bitLen >>> 24) & 0xff;
  buf[paddedLen - 3] = (bitLen >>> 16) & 0xff;
  buf[paddedLen - 2] = (bitLen >>> 8) & 0xff;
  buf[paddedLen - 1] = bitLen & 0xff;

  const w: number[] = new Array<number>(64).fill(0);

  for (let offset = 0; offset < paddedLen; offset += 64) {
    for (let i = 0; i < 16; i++) {
      const p: number = offset + i * 4;
      w[i] = ((buf[p] << 24) | (buf[p + 1] << 16) | (buf[p + 2] << 8) | buf[p + 3]) >>> 0;
    }
    for (let i = 16; i < 64; i++) {
      const s0: number = (rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >>> 3)) >>> 0;
      const s1: number = (rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >>> 10)) >>> 0;
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) >>> 0;
    }

    let a: number = h[0];
    let b: number = h[1];
    let c: number = h[2];
    let d: number = h[3];
    let e: number = h[4];
    let f: number = h[5];
    let g: number = h[6];
    let hh: number = h[7];

    for (let i = 0; i < 64; i++) {
      const s1: number = (rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)) >>> 0;
      const ch: number = ((e & f) ^ ((~e >>> 0) & g)) >>> 0;
      const t1: number = (hh + s1 + ch + K[i] + w[i]) >>> 0;
      const s0: number = (rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)) >>> 0;
      const maj: number = ((a & b) ^ (a & c) ^ (b & c)) >>> 0;
      const t2: number = (s0 + maj) >>> 0;

      hh = g;
      g = f;
      f = e;
      e = (d + t1) >>> 0;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) >>> 0;
    }

    h[0] = (h[0] + a) >>> 0;
    h[1] = (h[1] + b) >>> 0;
    h[2] = (h[2] + c) >>> 0;
    h[3] = (h[3] + d) >>> 0;
    h[4] = (h[4] + e) >>> 0;
    h[5] = (h[5] + f) >>> 0;
    h[6] = (h[6] + g) >>> 0;
    h[7] = (h[7] + hh) >>> 0;
  }

  const out: Uint8Array = new Uint8Array(32);
  for (let i = 0; i < 8; i++) {
    out[i * 4] = (h[i] >>> 24) & 0xff;
    out[i * 4 + 1] = (h[i] >>> 16) & 0xff;
    out[i * 4 + 2] = (h[i] >>> 8) & 0xff;
    out[i * 4 + 3] = h[i] & 0xff;
  }
  return out;
}

const B64_ALPHABET: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';

/** base64url 编码（无 padding），PKCE 要求 */
export function base64Url(bytes: Uint8Array): string {
  let out: string = '';
  let i: number = 0;
  while (i + 2 < bytes.length) {
    const n: number = (bytes[i] << 16) | (bytes[i + 1] << 8) | bytes[i + 2];
    out += B64_ALPHABET[(n >>> 18) & 0x3f];
    out += B64_ALPHABET[(n >>> 12) & 0x3f];
    out += B64_ALPHABET[(n >>> 6) & 0x3f];
    out += B64_ALPHABET[n & 0x3f];
    i += 3;
  }
  const rest: number = bytes.length - i;
  if (rest === 1) {
    const n: number = bytes[i] << 16;
    out += B64_ALPHABET[(n >>> 18) & 0x3f];
    out += B64_ALPHABET[(n >>> 12) & 0x3f];
  } else if (rest === 2) {
    const n: number = (bytes[i] << 16) | (bytes[i + 1] << 8);
    out += B64_ALPHABET[(n >>> 18) & 0x3f];
    out += B64_ALPHABET[(n >>> 12) & 0x3f];
    out += B64_ALPHABET[(n >>> 6) & 0x3f];
  }
  return out;
}

/**
 * code_verifier：两段 UUID v4 拼接去连字符 = 64 个十六进制字符。
 * RFC 7636 允许 43~128 字符的 [A-Za-z0-9-._~]，十六进制合法；
 * 随机熵约 234 位，满足 PKCE 强度要求。
 */
export function newCodeVerifier(): string {
  const a: string = util.generateRandomUUID(false).replaceAll('-', '');
  const b: string = util.generateRandomUUID(false).replaceAll('-', '');
  return a + b;
}

/** code_challenge = base64url(sha256(verifier))，METHOD 固定 S256 */
export function challengeOf(verifier: string): string {
  const bytes: Uint8Array = new Uint8Array(verifier.length);
  for (let i = 0; i < verifier.length; i++) {
    bytes[i] = verifier.charCodeAt(i) & 0xff;
  }
  return base64Url(sha256(bytes));
}
