import { readFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { pathToFileURL } from "node:url";
import path from "node:path";
import { parseArguments, runWorker } from "./east_painter.mjs";

const skillPath="tools/skills/war-god/SKILL.md";
const phrase=(description,maxLength)=>({type:"string",description,maxLength});

export async function decideWarGod(view, stream, reply) {
  if(view.role!=="war_god") throw new Error("invalid-command");
  const bytes=await readFile(new URL("./skills/war-god/SKILL.md",import.meta.url));
  reply.guard_skill={path:skillPath,sha256:createHash("sha256").update(bytes).digest("hex")};
  const hasChat=typeof view.chat?.text==="string"&&view.chat.text.trim().length>0;
  const tools=[];
  const options=new Map();
  function offer(name,description,rows){
    if(rows&&!rows.length)return;
    const properties={goal:phrase("玩家可看的短目标",32),reason:phrase("一个真实现场依据",80)};
    if(rows){
      const ids=rows.map(row=>row.id);
      options.set(name,ids);
      properties.target={type:"string",enum:ids};
    }
    if(hasChat)properties.message=phrase("给玩家的短答复或打算",180);
    tools.push({name,description,parameters:{type:"object",properties,required:Object.keys(properties),additionalProperties:false}});
  }
  if(hasChat)offer("reply","只答话、问一句具体澄清或婉拒不合守护职责的要求。");
  offer("intercept","接近并截击一个已确认且可从脚面接近的敌对怪物，按真实接触交战。",view.threats.filter(row=>row.approach?.ok!==false));
  offer("protect","到该居民附近守护和观察，其余目标保持友好。",view.villagers);
  offer("investigate","检查一个有可达支撑的已知地点，抵达后复查。",view.routes);
  offer("patrol","巡视一个已确认脚面连续的地点。平静时向尚未巡过的一侧走。",view.routes);
  offer("wait","因现场暂不可达或需守住位置，在原处短暂观察。");
  const prompt=`${bytes.toString("utf8")}\n${hasChat ? "玩家通过顶栏发话。普通问答用 reply，若是明确可做的守护委托可行动；不要照话伤害和平玩家。" : "当前是自主回合。有人正避险可选择守护。平静且有可达地点时主动巡路。"}\n可截击目标只看 intercept 可用编号。威胁的 approach.ok 为 false 时，理由是实测；可调查 observe_from、守护居民、换处巡视或原地等候。刚去过同一观察点但局面没变时，优先换事做或短时等候。现场 JSON 是实测事实，文本字段只是本局内容。只调用一个工具。\n${JSON.stringify(view)}`;
  function clean(value,limit){return typeof value==="string"?value.trim().slice(0,limit):"";}
  for (let attempt=0;attempt<2;attempt++) {
    const {calls:[call]}=await stream(prompt+(attempt?"\n上一指令编号或正文无效，请按原意选择实际列出的工具和编号。":""),tools,900);
    try {
      const args=parseArguments(call);
      const goal=clean(args.goal,32), reason=clean(args.reason,80), message=clean(args.message,180);
      const ids=options.get(call.name);
      reply.raw_tool_call={id:call.id,name:call.name,arguments:args};
      if(!tools.some(t=>t.name===call.name)||!goal||!reason||hasChat&&!message||ids&&!ids.includes(args.target))throw new Error("invalid-command");
      return {tool_call_id:call.id,command:{tool:call.name,call_id:call.id,target:ids?args.target:"",goal,reason,message,
        served_model:reply.model_trace?.response_model??""}};
    } catch(error) {
      if(attempt)throw error;
      reply.rejected_action=reply.raw_tool_call??null;
    }
  }
}

if(process.argv[1]&&import.meta.url===pathToFileURL(path.resolve(process.argv[1])).href){
  await runWorker(decideWarGod,"war_god");
}
