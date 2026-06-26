const SENSITIVE_KEY_PATTERN = /(token|secret|password|authorization|certificate|private|signature|key)/i;
const SENSITIVE_TEXT_PATTERNS = [
  /\bBearer\s+[A-Za-z0-9._~+/=-]+/gi,
  /\b(csrf[_-]?token|device[_-]?secret|authorization|token|secret)=([A-Za-z0-9._~+/=-]+)/gi,
  /--csrf_token\s+[A-Za-z0-9._~+/=-]+/gi
];

export function redactSensitive(value: unknown): unknown {
  if (Array.isArray(value)) {
    return value.map((item) => redactSensitive(item));
  }

  if (typeof value === "string") {
    return redactSensitiveText(value);
  }

  if (value && typeof value === "object") {
    const output: Record<string, unknown> = {};
    for (const [key, nested] of Object.entries(value)) {
      output[key] = SENSITIVE_KEY_PATTERN.test(key) ? "[REDACTED]" : redactSensitive(nested);
    }
    return output;
  }

  return value;
}

export function redactSensitiveText(value: string): string {
  return SENSITIVE_TEXT_PATTERNS.reduce((text, pattern) => text.replace(pattern, (match) => {
    const separator = match.includes("=") ? match.split("=")[0] + "=" : match.split(/\s+/)[0] + " ";
    return `${separator}[REDACTED]`;
  }), value);
}
