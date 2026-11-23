import { randomUUID } from "node:crypto";
import { ConnectionError, explicitlyRejectsTools, redactSecret } from "./byok_api.mjs";

const api = "https://api.deepseek.com/anthropic";

function transportTrace(response, trace) {
  if (!response.body) return response;
  const decoder = new TextDecoder();
  const maxBytes = response.ok ? 1_048_576 : 65_536;
  let pending = "";
  let size = 0;
  let started = !response.ok;
  const body = response.body.pipeThrough(new TransformStream({
    transform(chunk, controller) {
      size += chunk.byteLength;
      if (size > maxBytes) throw new ConnectionError("invalid_response");
      if (!started) {
        pending += decoder.decode(chunk, { stream: true });
        const lines = pending.split("\n");
        pending = lines.pop();
        for (const line of lines) {
          if (!line.startsWith("data:")) continue;
          let event;
          try { event = JSON.parse(line.slice(5)); } catch { continue; }
          if (event?.type !== "message_start") continue;
          trace.response_model = tag(event.message?.model);
          trace.message_id = tag(event.message?.id);
          trace.response_source = trace.response_model ? "message_start.message.model" : null;
          started = true;
          pending = "";
          break;
        }
      }
      controller.enqueue(chunk);
    }
  }));
  return new Response(body, {status:response.status, statusText:response.statusText, headers:response.headers});
}

const tag = value => typeof value === "string" ? value.slice(0, 160) : null;

function providerDetail(error) {
  const raw = error.cause?.message;
  if (typeof raw==="string" && raw.length<=65536) {
    try {
      const detail=JSON.parse(raw)?.error;
      if(detail && typeof detail==="object") return detail;
    } catch { /* Some gateways send an unstructured error. */ }
  }
  return error;
}

function publicFailure(error, signal, tools) {
  const status = error.failure?.status;
  if (error instanceof ConnectionError) return error;
  if (error.cause instanceof ConnectionError) return error.cause;
  if (signal.aborted || ["TIMEOUT", "ABORTED"].includes(error.code)) return new ConnectionError("timeout");
  if (status === 401 || error.code === "MISSING_CREDENTIAL") return new ConnectionError("credentials_rejected");
  if (status === 403) return new ConnectionError("permission_denied");
  if (status === 402 || error.code === "QUOTA") return new ConnectionError("quota");
  if (status === 429 || error.code === "RATE_LIMIT") return new ConnectionError("rate_limited");
  if (tools?.length && ([400,422].includes(status) || error.code === "INVALID_REQUEST") && explicitlyRejectsTools(providerDetail(error))) {
    return new ConnectionError("tools_unsupported");
  }
  if ([400,422].includes(status) || error.code === "INVALID_REQUEST") return new ConnectionError("request_rejected");
  if (["TRANSPORT", "SERVER"].includes(error.code)) return new ConnectionError("network");
  return new ConnectionError(status ? "bad_endpoint" : "invalid_response");
}

export async function officialCompletion(grant, prompt, tools, maxTokens, signal) {
  let sdk;
  try { sdk = await import("@deepseek-ai/dsh-llm-deepseek"); }
  catch { throw new ConnectionError("runtime_error"); }

  const { DeepSeekAdapter, resolveAdapterOptions } = sdk;
  const reasoningEffort = grant.reasoning??"off";
  const settings = resolveAdapterOptions({baseURL:api, thinking:reasoningEffort==="off"?"disabled":"enabled", reasoningEffort});
  const anonymousId = randomUUID();
  const adapter = new DeepSeekAdapter({
    options: () => settings,
    resolveAuth: async () => ({headers:{"x-api-key":grant.key}}),
    resolveUserId: () => anonymousId,
    prepareExtensions: async () => ({fields:{}, accept:async () => {}}),
    // This game sends text and public tool definitions only, so it needs no file cache.
    resolveFiles: () => Object.freeze({})
  });
  const trace = {requested_alias:grant.model, wire_request_model:null, response_model:null,
    response_source:null, provider_request_id:null, message_id:null};
  const fetch = globalThis.fetch;
  let content = "";
  const calls = [];
  let reason;

  // This worker serializes turns and starts only one adapter stream at a time.
  globalThis.fetch = async (url, request) => {
    if (String(url) !== `${api}/v1/messages` || request.redirect !== "error") throw new ConnectionError("bad_endpoint");
    trace.wire_request_model = tag(JSON.parse(request.body).model);
    const response = await fetch(url, request);
    trace.http_status = response.status;
    trace.provider_request_id = tag(response.headers.get("request-id") ?? response.headers.get("x-request-id"));
    return transportTrace(response, trace);
  };
  try {
    for await (const chunk of adapter.stream({provider:grant.provider, model:grant.model, tools, maxTokens, reasoningEffort,
      signal, messages:[{role:"user", content:[{type:"text", text:prompt}]}]})) {
      if (chunk.type === "text-delta") content += chunk.text;
      if (chunk.type === "block-end" && chunk.block.type === "tool-call") calls.push(chunk.block);
      if (chunk.type === "finish") reason = chunk.reason.kind;
    }
  } catch (error) {
    const failure = publicFailure(error, signal, tools);
    failure.trace = redactSecret(trace,grant.key);
    throw failure;
  } finally {
    globalThis.fetch = fetch;
  }
  trace.finish_reason = reason;
  trace.tool_calls = calls.length;
  if (tools?.length && !calls.length && reason === "stop") throw new ConnectionError("no_tool_action",redactSecret(trace,grant.key));
  if (tools?.length ? (reason !== "tool-calls" || calls.length !== 1 || !tools.some(t => t.name === calls[0].name)) : reason !== "stop") {
    throw new Error("invalid-command");
  }
  return redactSecret({content, calls, trace}, grant.key);
}
