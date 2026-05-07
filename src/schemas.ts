import { z } from "zod";

export const captureDeskViewInput = z.object({}).strict();

export const captureOnStableInput = z
  .object({
    stability_duration_ms: z.number().min(500).max(30000).default(3000),
    timeout_ms: z.number().min(1000).max(1800000).default(300000),
    sensitivity: z.enum(["low", "medium", "high"]).default("medium"),
  })
  .strict();

export const captureOnGestureInput = z
  .object({
    gesture: z.enum(["thumbs_up", "peace", "ok_sign", "fist", "open_palm"]),
    timeout_ms: z.number().min(1000).max(1800000).default(300000),
    hold_duration_ms: z.number().min(100).max(5000).default(500),
  })
  .strict();

// JSON Schema mirrors used in the ListTools response.
export const captureDeskViewJsonSchema = {
  type: "object",
  properties: {},
  additionalProperties: false,
} as const;

export const captureOnStableJsonSchema = {
  type: "object",
  properties: {
    stability_duration_ms: {
      type: "number",
      default: 3000,
      minimum: 500,
      maximum: 30000,
      description:
        "How long the scene must remain still (motion below threshold) before capturing.",
    },
    timeout_ms: {
      type: "number",
      default: 300000,
      minimum: 1000,
      maximum: 1800000,
      description:
        "Maximum total wait time. If reached without stabilization, returns the last frame with a timeout note.",
    },
    sensitivity: {
      type: "string",
      enum: ["low", "medium", "high"],
      default: "medium",
      description:
        "How sensitive the motion detector is. Low is forgiving (5% pixel change tolerated), medium is balanced (2%), high is twitchy (0.5%).",
    },
  },
  additionalProperties: false,
} as const;

export const captureOnGestureJsonSchema = {
  type: "object",
  properties: {
    gesture: {
      type: "string",
      enum: ["thumbs_up", "peace", "ok_sign", "fist", "open_palm"],
      description: "Which hand gesture to wait for.",
    },
    timeout_ms: {
      type: "number",
      default: 300000,
      minimum: 1000,
      maximum: 1800000,
    },
    hold_duration_ms: {
      type: "number",
      default: 500,
      minimum: 100,
      maximum: 5000,
      description:
        "How long the gesture must be held continuously to count. Prevents false positives from brief flashes.",
    },
  },
  required: ["gesture"],
  additionalProperties: false,
} as const;
