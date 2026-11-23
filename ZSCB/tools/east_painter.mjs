// Shared data-only Harness transport, also usable by the original drawing fixtures.
// The running game grants exactly one selected connection over the child stdin.
import { readFile, rename, writeFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { completion, ConnectionError, discoverModels, publicGrant, readPlayerGrant, redactSecret } from "./byok_api.mjs";

async function legacyDrawing(observation, stream) {
  const pens = observation.task === "functional_pen";
  const strokeSchema = {
    type: "object",
    properties: {
      name: { type: "string", description: "简短中文作品名" },
      style: { type: "string", enum: observation.styles },
      strokes: { type: "array", description: "1至6笔，每笔是2至24个绝对世界坐标[x,y]，单位米，y向上",
        items: { type: "object", properties: { points: { type: "array", items: { type: "array", minItems: 2, maxItems: 2, items: { type: "number" } } } }, required: ["points"] } }
    },
    required: ["name", "style", "strokes"]
  };
  const stroke = strokeSchema.properties.strokes.items.properties;
  if (observation.pigments?.length) stroke.pigment = {type:"string", enum:observation.pigments};
  if (observation.brushes?.length) stroke.brush = {type:"string", enum:observation.brushes};
  const tools = pens ? observation.tools.map(({name, description}) => ({
    name, description, parameters: strokeSchema
  })) : undefined;
  const prompt = pens ? `你是《纸间》的画家。调用一次 ${observation.requested} 工具作画。你自己选择位置并创作实际点列。
观察 ground (可见范围的地表[x,y]样本，y向上)，player 与 occupied (已画作品的包围盒)，避开已有物件，所有点都位于 view_y 内。优先在与玩家相距2–5米的空地作画，避免越出可见范围。
景物画有远近峰线的远山，地形画从地表逐渐起坡的可行走缓坡及顶部小平台，落差不超过水平步长的一半，
造物画一块约1米宽的不规则实心石块，在地表上方一点起画，末点重复首点。留出角色站立和推动的空间。
只交付一次工具调用。观察：${JSON.stringify(observation)}` : `你是侧视黑墨纸面游戏《纸间》的山水画家。向东续画一小段连续可步行的地面。世界坐标以米计，y向上。
观察 tail 最后几笔、edge 及 previous_name，根据实际走势自己决定山形和一处小地标。呼应接笔处，又要和上一段有视觉上的差异。
只返回一个合法 JSON 对象，只含 name、points、strokes。revision 已由游戏观测绑定。name 是简短中文地名。
points 是世界坐标 [x,y] 点列。原样复制 edge 作为第一点，再画 4–7 个起伏或转折，终点 x 须在 ${(observation.edge[0] + 8).toFixed(2)} 到 ${(observation.edge[0] + 10).toFixed(2)} 之间。
相邻地形点水平步距 0.4–12 米，每步爬升或降落不超过水平步距的 0.5 倍，高程留在观测 limits 中。
strokes 是地标的 2–7 条黑色墨线，每条用 2–12 个 [世界x,离地高度] 点勾出剪影、轮廓或纹理。
装饰x必须在新段范围内，高度为 0–2.8 米，落笔处留白。请画一处叫得出名字、与地名吻合的景物，不用文字。数值最多保留两位小数，唯起点保留原精度。
边缘观测 JSON：${JSON.stringify(observation)}`;

  const { calls, content } = await stream(prompt, tools);
  const reply = {};
  if (pens) {
    if (calls.length !== 1 || calls[0].name !== observation.requested) throw new Error("invalid-command");
    const call = calls[0];
    const args = parseArguments(call);
    reply.tool_call_id = call.id;
    if (!Array.isArray(args.strokes)) throw new Error("invalid-command");
    const strokes = args.strokes.map((stroke) => stroke.points ?? stroke);
    reply.command = { tool: call.name, name: args.name, style: args.style, strokes };
    if (observation.pigments?.length) reply.command.pigments = args.strokes.map(s => s.pigment ?? observation.selected_pigment ?? "inherit");
    if (observation.brushes?.length) reply.command.brushes = args.strokes.map(s => s.brush ?? observation.selected_brush ?? "bold");
  } else {
    if (!content.trim()) throw new Error("invalid-command");
    const command = JSON.parse(content.trim().replace(/^\x60\x60\x60(?:json)?\s*|\s*\x60\x60\x60$/gi, ""));
    if (command === null || typeof command !== "object" || Array.isArray(command)) {
      throw new Error("invalid-command");
    }
    // The observed revision is the compare-and-swap token. Its value belongs to
    // this request even if a different painter finishes first.
    reply.command = {
      revision: observation.revision, name: command.name, points: command.points,
      strokes: command.strokes ?? []
    };
  }
  return reply;
}

export function parseArguments(call) {
  const args = typeof call.arguments === "string" ? JSON.parse(call.arguments || "{}") : call.arguments;
  if (!args || typeof args !== "object" || Array.isArray(args)) throw new Error("invalid-command");
  return args;
}

// The game keeps a 32 KiB IPC limit. Preserve unusually verbose tool evidence
// alongside the receipt while delivering the same compiled geometry to Godot.
export async function writeReply(replyPath, reply) {
  const limit = 32768;
  const full = JSON.stringify(reply);
  let wire = full;
  if (Buffer.byteLength(full) > limit) {
    const evidence = replyPath + ".evidence.json";
    await writeFile(evidence + ".tmp", full, { mode: 0o600 });
    await rename(evidence + ".tmp", evidence);
    const groups = new Map();
    for (const fix of reply.geometry_fixes ?? []) {
      const id = JSON.stringify([fix.target, fix.reason, fix.mode]);
      if (!groups.has(id)) groups.set(id, { target: fix.target, reason: fix.reason, mode: fix.mode, spans: [] });
      if (Number.isInteger(fix.span)) groups.get(id).spans.push(fix.span);
    }
    const { raw_tool_call, geometry_fixes, rejected_drafts, station_adjustments, priest_draft, ...envelope } = reply;
    if (rejected_drafts?.length) envelope.rejected_count = rejected_drafts.length;
    if (station_adjustments?.length) envelope.station_adjustments = station_adjustments.map(pick => ({
      reason: pick.reason, design_call_id: pick.design_call_id, tool_call: pick.tool_call, model_trace: pick.model_trace
    }));
    if (reply.command) envelope.command = { ...reply.command, geometry_fixes: [...groups.values()] };
    wire = JSON.stringify({ ...envelope, evidence_file: path.basename(evidence) });
    if (Buffer.byteLength(wire) > limit) {
      wire = JSON.stringify({ request_id: reply.request_id, connection:reply.connection, error_code:"invalid_response", error: "本次笔稿超过游戏回执大小，请精简笔画。",
        evidence_file: path.basename(evidence) });
    }
  }
  await writeFile(replyPath + ".tmp", wire, { mode: 0o600 });
  await rename(replyPath + ".tmp", replyPath);
}

// One settings snapshot and abort deadline cover every call in the role's turn,
// including retries, blueprint repairs and their receipts.
export async function runWorker(decide, role = "companion") {
  const [requestPath,replyPath,mode]=process.argv.slice(2);
  const {request_id,observation}=JSON.parse(await readFile(requestPath,"utf8"));
  const reply={request_id};
  let grant;
  try {
    if(mode!=="--player-connection") throw new ConnectionError("not_configured");
    grant=await readPlayerGrant(process.stdin);
    if(role==="priest" && observation.priest_protocol==="species-ink-v1" && (grant.provider!=="deepseek-official"||grant.model!=="deepseek-flash"))throw new ConnectionError("invalid_connection");
    if(grant.role!==role) throw new ConnectionError("invalid_connection");
    Object.assign(reply,{connection:publicGrant(grant),provider:grant.provider,model:grant.model});
    const building=["building_design","building_variant"].includes(observation?.invitation?.kind);
    const limit=role==="diagnostic"?15000:building||role==="priest"&&observation.priest_protocol==="species-ink-v1"?150000:45000;
    const signal=AbortSignal.timeout(limit);
    if(role==="diagnostic"&&observation.kind==="models"){
      reply.command={ok:true,models:await discoverModels(grant,signal)};
    }else{
      async function stream(prompt,tools,maxTokens=2000) {
        const effectiveTokens=grant.reasoning==="off" ? maxTokens : Math.max(4096,maxTokens);
        const result=await completion(grant,prompt,tools,effectiveTokens,signal);
        reply.model_trace=result.trace;
        return result;
      }
      if(role==="diagnostic"){
        const tool={name:"check_game_tools",description:"确认可用的函数调用。",
          parameters:{type:"object",properties:{ok:{type:"boolean"}},required:["ok"],additionalProperties:false}};
        const {calls:[call]}=await stream("这是一次玩家主动测试。请直接调用 check_game_tools 并返回 ok=true。",[tool],180);
        if(parseArguments(call).ok!==true)throw new ConnectionError("tool_probe_inconclusive");
        reply.command={ok:true,model:grant.model};
      }else{
        Object.assign(reply,await decide(observation,stream,reply));
      }
    }
    if(reply.command)Object.assign(reply.command,{provider:grant.provider,model:grant.model});
  }catch(error){
    if(error instanceof ConnectionError){
      const failure=role==="diagnostic" && error.code==="no_tool_action" ? new ConnectionError("tool_probe_inconclusive") : error;
      reply.error_code=failure.code;
      reply.error=failure.message;
      if(error.trace)reply.model_trace=error.trace;
    }else if(error.name==="AbortError"||error.name==="TimeoutError"){
      reply.error_code="timeout";
      reply.error="模型回应超时，请稍后重试。";
    }else if(role==="diagnostic"&&(error instanceof SyntaxError||error.message==="invalid-command")){
      const failed=new ConnectionError("tool_probe_inconclusive");
      reply.error_code=failed.code;
      reply.error=failed.message;
    }else{
      reply.error_code="invalid_response";
      reply.error=error.name==="PainterGeometryError"?error.message:"模型交回的动作无法识别，请稍后再试。";
    }
  }
  await writeReply(replyPath,grant?redactSecret(reply,grant.key):reply);
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  if(process.argv[5]==="--diagnostic")await runWorker(null,"diagnostic");
  else await runWorker(legacyDrawing);
}
