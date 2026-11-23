// One session grant, one explicitly configured API root. No environment or SDK credential lookup.
export const messages = Object.freeze({
  not_configured: "这个角色还没有绑定模型连接。请打开设置选择连接。",
  needs_key: "请为这条连接输入本次会话使用的 API Key。",
  invalid_connection: "连接的模型、地址或角色无效，请重新设置。",
  credentials_rejected: "服务商拒绝了 API Key，请检查或更换 Key。",
  permission_denied: "此 API Key 无权调用所选模型或端点，请检查服务商权限。",
  quota: "服务商显示余额或额度不足，请检查账户后验证连接。",
  rate_limited: "服务商限制了调用频率，请稍后验证连接。",
  tools_unsupported: "服务商明确拒绝此模型的函数工具，请检查模型与端点。",
  no_tool_action: "本回合正常结束，模型没有提交工具动作。连接保留。",
  tool_probe_inconclusive: "本次主动测试没有收到有效的测试工具回执，可稍后再测。",
  request_rejected: "服务商拒绝了本次请求，请查看这一回合的状态。",
  bad_endpoint: "端点拒绝了这项请求，请检查 API 根地址和模型 ID。",
  no_models: "该端点无法列出模型，可以手动填写模型 ID。",
  runtime_error: "无法加载 DeepSeek Harness 运行依赖，请检查游戏安装。",
  timeout: "模型回应超时，请稍后再试。",
  invalid_response: "服务返回的内容无法识别，请检查连接。",
  network: "暂时无法连接服务商，请检查网络与 API 根地址。"
});

export class ConnectionError extends Error {
  constructor(code, trace) { super(messages[code]); this.code = code; this.trace = trace; }
}

// A provider may reject a parameter or a schema while still supporting tools.
export function explicitlyRejectsTools(error) {
  const code = String(error?.code ?? error?.type ?? "").toLowerCase();
  if (code==="unsupported_parameter" && ["tools","functions"].includes(error?.param)) return true;
  if (["tools_unsupported","unsupported_tools","tools_not_supported","tool_calling_not_supported","function_calling_not_supported"].includes(code)) return true;
  const message = typeof error?.message==="string" ? error.message.slice(0,1200) : "";
  return /(?:does not support|doesn't support|cannot use|不支持)\s*(?:the use of |using |any )?(?:function call(?:s|ing)?|tool calling|tool use|tools\b(?![_ .-]*(?:choice|schema|parameter))|工具调用|函数调用|工具功能|工具(?!参数|选择|格式))/iu.test(message) ||
    /(?:\btools\b|tool calling|tool use|function calling|工具调用|函数调用)\s*(?:is |are |功能)?(?:not supported|unsupported|not available for (?:this|the) model|不受支持)/iu.test(message);
}

const fail = code => { throw new ConnectionError(code); };
const roles = new Set(["companion","priest","war_god","adventurer-lizhou","diagnostic"]);
const official = "https://api.deepseek.com";
const keyPattern = /^[A-Za-z0-9._~+\/=-]{8,2048}$/u;
const modelPattern = /^[A-Za-z0-9][A-Za-z0-9._:/-]{0,119}$/u;

export function apiRoot(value) {
  if (typeof value !== "string" || !/^https?:\/\//u.test(value) || value.length > 400 ||
      /[\x00-\x20\x7f?#\\%]/u.test(value) || /(?:^|\/)\.{1,2}(?:\/|$)/u.test(value)) fail("invalid_connection");
  let url;
  try { url = new URL(value); } catch { fail("invalid_connection"); }
  if (!url.hostname || url.username || url.password || url.pathname.includes("//") ||
      (url.protocol !== "https:" && !["localhost","127.0.0.1","[::1]"].includes(url.hostname))) fail("invalid_connection");
  return url.origin + url.pathname.replace(/\/+$/u,"");
}

export function validateGrant(input) {
  if (!input || typeof input !== "object" || !roles.has(input.role) ||
      !/^[a-f0-9]{24}$/u.test(input.id??"") || !Number.isSafeInteger(input.generation) || input.generation < 1 ||
      !["deepseek-official","compatible"].includes(input.provider) ||
      typeof input.model !== "string" || !modelPattern.test(input.model)) fail("invalid_connection");
  const baseURL = apiRoot(input.base_url);
  if (input.provider==="deepseek-official" && baseURL!==official) fail("invalid_connection");
  if (typeof input.key!=="string" || !keyPattern.test(input.key)) fail("needs_key");
  const {id,role,generation,provider,model,key}=input;
  const reasoning=input.reasoning??"off";
  if (!(provider==="deepseek-official"?["off","low","high","max"]:["off","low","medium","high"]).includes(reasoning)) fail("invalid_connection");
  return {id,role,generation,provider,model,key,reasoning,base_url:baseURL};
}

export async function readPlayerGrant(stdin) {
  let line="";
  stdin.setEncoding("utf8");
  for await (const text of stdin) {
    line+=text;
    if(line.length>8192)fail("invalid_connection");
    if(line.includes("\n"))break;
  }
  if(!line.includes("\n"))fail("needs_key");
  let data;
  try { data=JSON.parse(line.slice(0,line.indexOf("\n"))); } catch { fail("invalid_connection"); }
  return validateGrant(data);
}

export function publicGrant({id,role,generation,provider,model}) {
  return {id,role,generation,provider,model};
}

// Service-controlled metadata and tool output are never allowed to echo the bearer secret.
export function redactSecret(value,key) {
  if (typeof value==="string") return value.includes(key)?value.split(key).join("[已隐藏]"):value;
  if (Array.isArray(value)) return value.map(v=>redactSecret(v,key));
  if (value && typeof value==="object") return Object.fromEntries(Object.entries(value).map(([k,v])=>[redactSecret(k,key),redactSecret(v,key)]));
  return value;
}

async function readJson(response) {
  const reader=response.body?.getReader();
  if(!reader) fail("invalid_response");
  let text="",size=0;
  const decoder=new TextDecoder();
  try {
    for (;;) {
      const {done,value}=await reader.read();
      if(done) break;
      size+=value.byteLength;
      if(size>1_048_576) fail("invalid_response");
      text+=decoder.decode(value,{stream:true});
    }
    return JSON.parse(text+decoder.decode());
  } catch(error) {
    if(error instanceof ConnectionError || error.name==="TimeoutError" || error.name==="AbortError") throw error;
    fail("invalid_response");
  } finally { void reader.cancel().catch(()=>{}); }
}

async function request(grant, route, payload, signal) {
  const headers={authorization:"Bearer "+grant.key,accept:"application/json"};
  if(payload) headers["content-type"]="application/json";
  let response;
  try {
    response=await fetch(grant.base_url+route,{method:payload?"POST":"GET",headers,
      body:payload?JSON.stringify(payload):undefined,redirect:"manual",signal});
  } catch(error) {
    if(signal.aborted || error.name==="TimeoutError" || error.name==="AbortError")fail("timeout");
    fail("network");
  }
  if(response.status>=300&&response.status<400){void response.body?.cancel().catch(()=>{});fail("bad_endpoint");}
  if(!response.ok){
    let error={};
    try { error=(await readJson(response))?.error??{}; } catch {}
    const category=[error.code,error.type].map(v=>typeof v==="string"?v.toLowerCase():"");
    const trace = redactSecret({http_status:response.status,requested_alias:grant.model,
      wire_request_model:payload?.model ?? null,provider_request_id:(response.headers.get("x-request-id") ?? response.headers.get("request-id"))?.slice(0,160) ?? null},grant.key);
    const reject = code => {throw new ConnectionError(code,trace);};
    if(response.status===401)reject("credentials_rejected");
    if(response.status===402||category.some(v=>["insufficient_quota","insufficient_balance","billing_hard_limit_reached","quota_exceeded","payment_required"].includes(v)))reject("quota");
    if(response.status===403)reject("permission_denied");
    if(response.status===429)reject("rate_limited");
    if(payload?.tools && [400,422].includes(response.status) &&
      explicitlyRejectsTools(error)) {
      reject("tools_unsupported");
    }
    if(route==="/models"&&[400,404,405,501].includes(response.status))reject("no_models");
    if(response.status>=500)reject("network");
    if([400,422].includes(response.status))reject("request_rejected");
    reject("bad_endpoint");
  }
  return {data:await readJson(response), httpStatus:response.status, requestId:response.headers.get("x-request-id")??response.headers.get("request-id")};
}

export async function completion(grant,prompt,tools,maxTokens,signal) {
  if (grant.provider==="deepseek-official") {
    const {officialCompletion}=await import("./dsh_official.mjs");
    return officialCompletion(grant,prompt,tools,maxTokens,signal);
  }
  const payload={model:grant.model,messages:[{role:"user",content:prompt}],stream:false,max_tokens:maxTokens};
  if(grant.reasoning && grant.reasoning!=="off") payload.reasoning_effort=grant.reasoning;
  if(tools?.length){
    payload.tools=tools.map(({name,description,parameters})=>({type:"function",function:{name,description,parameters}}));
    payload.tool_choice=payload.reasoning_effort ? "auto" : "required";
  }
  const {data,requestId,httpStatus}=await request(grant,"/chat/completions",payload,signal);
  const choice=data?.choices?.[0], message=choice?.message;
  const tag=value=>typeof value==="string"?value.slice(0,160):null;
  if(!message || typeof message!=="object") fail("invalid_response");
  const trace={requested_alias:grant.model,wire_request_model:payload.model,response_model:tag(data.model),
    response_source:typeof data.model==="string"?"chat_completions.model":null,
    provider_request_id:tag(requestId),message_id:tag(data.id)};
  if(message.tool_calls!=null && !Array.isArray(message.tool_calls))fail("invalid_response");
  const calls=Array.isArray(message.tool_calls)?message.tool_calls.map(c=>({
    id:c?.id,name:c?.function?.name,arguments:c?.function?.arguments
  })):[];
  Object.assign(trace,{http_status:httpStatus,finish_reason:tag(choice.finish_reason),tool_calls:calls.length});
  if(tools?.length && !calls.length && choice.finish_reason==="stop") {
    throw new ConnectionError("no_tool_action",redactSecret(trace,grant.key));
  }
  if(tools?.length && (calls.length!==1 || choice.finish_reason!=="tool_calls" ||
      typeof calls[0].id!=="string"||!calls[0].id||calls[0].id.length>128||!tools.some(t=>t.name===calls[0].name))) {
    throw new Error("invalid-command");
  }
  if(!tools && choice.finish_reason!=="stop") throw new Error("invalid-command");
  return redactSecret({content:typeof message.content==="string"?message.content:"",calls,trace},grant.key);
}

export async function discoverModels(grant,signal) {
  const {data}=await request(grant,"/models",null,signal);
  if(!Array.isArray(data?.data))fail("no_models");
  return [...new Set(data.data.map(row=>row?.id).filter(id=>typeof id==="string"&&modelPattern.test(id)&&!id.includes(grant.key)))].slice(0,500);
}
