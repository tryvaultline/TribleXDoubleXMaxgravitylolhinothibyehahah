import { describe, expect, it } from "vitest";
import { BridgeEventSchema } from "../src/schemas.js";
import { redactSensitive } from "../src/redaction.js";

describe("bridge event schemas", () => {
  it("accepts safe task stage events", () => {
    const parsed = BridgeEventSchema.parse({
      type: "task.stage",
      taskId: "task-1",
      stage: "Running tests",
      detail: "npm test is running.",
      emittedAt: "2026-06-25T12:00:00.000Z"
    });

    if (parsed.type !== "task.stage") {
      throw new Error("Expected task.stage event");
    }
    expect(parsed.stage).toBe("Running tests");
  });

  it("rejects hidden reasoning as an arbitrary stage", () => {
    expect(() =>
      BridgeEventSchema.parse({
        type: "task.stage",
        taskId: "task-1",
        stage: "Internal chain of thought",
        detail: "private",
        emittedAt: "2026-06-25T12:00:00.000Z"
      })
    ).toThrow();
  });
});

describe("redaction", () => {
  it("redacts sensitive log fields recursively", () => {
    const redacted = redactSensitive({
      token: "secret-token",
      nested: {
        authorization: "Bearer secret",
        safe: "visible"
      }
    });

    expect(redacted).toEqual({
      token: "[REDACTED]",
      nested: {
        authorization: "[REDACTED]",
        safe: "visible"
      }
    });
  });
});
