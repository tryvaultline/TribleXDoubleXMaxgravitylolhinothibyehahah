const SENSITIVE_KEY_PATTERN = /(token|secret|password|authorization|certificate|private|signature|key)/i;

export function redactSensitive(value: unknown): unknown {
  if (Array.isArray(value)) {
    return value.map((item) => redactSensitive(item));
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
