import { openai } from "@ai-sdk/openai";
import { anthropic } from "@ai-sdk/anthropic";

const provider = process.env.AI_PROVIDER || "openai";

export const model =
  provider === "anthropic"
    ? anthropic(process.env.AI_MODEL || "claude-sonnet-4-20250514")
    : openai(process.env.AI_MODEL || "gpt-4o");
