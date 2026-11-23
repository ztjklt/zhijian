import {decideSpecies,presentDietReply} from "./priest_species.mjs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { parseArguments, runWorker } from "./east_painter.mjs";

const parts = ["body", "head", "ear", "tail", "leg", "mark"];
const pair = { type: "array", minItems: 2, maxItems: 2, items: { type: "number", minimum: 0, maximum: 10 } };
const outline = { type: "array", minItems: 4, maxItems: 12, items: pair };
const choices = values => ({ type: "string", enum: values });
const properties = {
  name: { type: "string", description: "二到六字的中文兽名" },
  coat: choices(["chestnut", "honey", "ash"]),
  gait: choices(["amble", "trot", "bound"]),
  pace: { type: "number", minimum: 0.75, maximum: 1.6, description: "米/秒" },
  feeding: choices(["gnaw", "strip"]),
  favorite: choices(["oak", "pine", "orchard_tree"]),
  ...Object.fromEntries(parts.map(key => [key, outline]))
};
const tool = { name: "draw_life", description: "逐笔画像，赋予这只四足小兽步态、感知取食偏好和啃咬动作。",
  parameters: { type: "object", properties, required: Object.keys(properties) } };

const cross = (a,b,c) => (b[0]-a[0])*(c[1]-a[1]) - (b[1]-a[1])*(c[0]-a[0]);

// Uncross a closed outline using the artist's own points. Each proper
// intersection removed this way strictly shortens its perimeter.
function untangle(points) {
  let changed = false;
  for (let pass = 0; pass < points.length**2; pass++) {
    let crossing = false;
    for (let i = 0; i < points.length && !crossing; i++) {
      for (let j = i+2; j < points.length; j++) {
        if (!i && j === points.length-1) continue;
        const a = points[i], b = points[i+1], c = points[j], d = points[(j+1)%points.length];
        if (cross(a,b,c)*cross(a,b,d) >= 0 || cross(c,d,a)*cross(c,d,b) >= 0) continue;
        points.splice(i+1, j-i, ...points.slice(i+1,j+1).reverse());
        crossing = changed = true;
        break;
      }
    }
    if (!crossing) break;
  }
  return changed;
}

export function readDesign(args, repairs = []) {
  const design = {};
  for (const [key, rule] of Object.entries(properties)) {
    const value = args[key];
    if (rule.enum && !rule.enum.includes(value)) throw new RangeError(key);
    if (key === "name" && (typeof value !== "string" || !value.trim() || value.trim().length > 12 || /[\r\n\t]/.test(value))) throw new RangeError(key);
    if (key === "pace" && (!Number.isFinite(value) || value < rule.minimum || value > rule.maximum)) throw new RangeError(key);
    if (parts.includes(key)) {
      if (!Array.isArray(value) || value.length < 4 || value.length > 12 ||
        !value.every(p => Array.isArray(p) && p.length === 2 && p.every(n => Number.isFinite(n) && n >= 0 && n <= 10))) throw new RangeError(key);
      const points = value.filter((p,i) => !i || p[0] !== value[i-1][0] || p[1] !== value[i-1][1]);
      if (key !== "mark" && points.length > 1 && points[0].every((n,i) => n === points.at(-1)[i])) points.pop();
      if (points.length < (key === "mark" ? 2 : 3)) throw new RangeError(key);
      if (key !== "mark" && untangle(points)) repairs.push({part:key, edit:"uncross", points:"retained"});
      const area = points.reduce((sum,[x,y],i) => { const [u,v] = points[(i+1)%points.length]; return sum+x*v-y*u; },0);
      const span = axis => Math.max(...points.map(p => p[axis])) - Math.min(...points.map(p => p[axis]));
      if (key !== "mark" && (Math.abs(area) < 0.0001 || Math.abs(area) < span(0)*span(1)*0.18)) throw new RangeError(key);
      design[key] = points;
    } else design[key] = typeof value === "string" ? value.trim() : value;
  }
  return design;
}

export async function decidePriest(observation, stream, reply) {
  if (observation.priest_protocol==="species-ink-v1") {
    const old=(observation.editable_works??[]).filter(w=>!w.design.schema);
    if (observation.task==="priest_chat" && /改|重绘|修稿/.test(observation.player_text) && old.some(w=>observation.player_text.includes(w.design.name))) return decideChat({...observation,editable_works:old,habitats:observation.habitats.map(h=>({...h,can_birth:false}))},stream,reply);
    return decideSpecies(observation,stream,reply);
  }
  if (observation.task === "priest_chat") return decideChat(observation, stream, reply);
  if (observation.task === "ecology") return decideEcology(observation, stream, reply);
  const prompt = `你是《纸间》的至高神，名字是牧师。你站在眼前这片山坡上，玩家等着看你亲手创造这里的第一只生命。只调用一次 draw_life。构思一只啃树皮的小兽，明确而独特的种属轮廓，近似有宽尾、圆耳、门齿的啮齿动物，侧身朝右。自行决定笔迹、墨色、步态、取食偏好。你实际画的轮廓会成为活动的小兽。根据观察中的真实树种和坡向构思。
body 躯干、head 头吻、ear 耳廓、tail 尾、leg 腿足都用各自 0 到 10 的局部纸格，x向右，y向上。每个闭合外轮廓单向顺序画4至12个点，不交叉，不重复首点，利用满格空间。体块连贯，腹鼓背弓，头顶向鼻尖下垂，耳根在下，尾根在右上而尾尖在左，腿上粗脚趾向右。leg 只画一条腿的一圈完整轮廓，不要在这一笔塞入两条腿。游戏会将它们接到骨架，翻出远侧耳与腿。mark 是躯干中上部一条开放的4到8点纹样，在同一局部纸格，用一笔短弧描出毛纹。gait 是缓步、对角小跑或弹跳。feeding 选择磨啃 gnaw 或扯皮 strip，favorite 选喜欢的树种。填好所有字段。现场 ${JSON.stringify(observation)}`;
  const attempts = [];
  reply.priest_attempts = attempts;
  let correction = "";
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const { calls, trace } = await stream(prompt + correction, [tool], 2200);
      const attemptReceipt = { tool_call_id: calls[0]?.id ?? null, requested_model: trace?.wire_request_model ?? null,
        response_model: trace?.response_model ?? null, response_source: trace?.response_source ?? null, accepted: false };
      attempts.push(attemptReceipt);
      if (calls.length !== 1 || calls[0]?.name !== tool.name || !calls[0].id) throw new Error("invalid-command");
      const [call] = calls;
      const args = parseArguments(call);
      reply.raw_tool_call = { id: call.id, name: call.name, arguments: args };
      const repairs = [];
      const design = readDesign(args, repairs);
      attemptReceipt.accepted = true;
      return { tool_call_id: call.id, repairs, command: { tool: tool.name, call_id: call.id, design } };
    } catch (error) {
      if (attempt || !(error instanceof RangeError || error instanceof SyntaxError || error.message === "invalid-command")) throw error;
      correction = `\n重新检查 ${error.message}。只调用一次工具，笔画每个坐标都要在纸格内，闭合部件保留足够面积。`;
    }
  }
}

const strokes = Object.fromEntries(parts.map(key => [key,{
    type:"string", pattern:"^[0-9]{4,12}$",description:key==="mark" ? "连续4至12个数字，逐点指定从左到右的背纹高度。" :
      "连续4至12个数字，每位是一个方向上从中心向外的笔长0至9，0为最短一笔。从朝右开始逆时针绕满一圈。"
  }]));

function expandStrokes(args) {
  const ink={...args};
  for (const key of parts) {
    if (!(key in ink)) continue;
    const digits=String(ink[key]??"").trim();
    if (!/^[0-9]{4,12}$/.test(digits)) throw new RangeError(key);
    ink[key]=Array.from(digits,(digit,index)=>{
      if (key==="mark") return [10*index/(digits.length-1),Number(digit)];
      const angle=2*Math.PI*index/digits.length;
      const radius=(Number(digit)+1)*0.47;
      return [5+radius*Math.cos(angle),5+radius*Math.sin(angle)].map(n=>Number(n.toFixed(3)));
    });
  }
  return ink;
}

const scales = {
  ear_scale: {type:"number",minimum:.65,maximum:1.5,description:"耳朵相对高度，1 是基础耳高"},
  tail_scale: {type:"number",minimum:.65,maximum:1.5,description:"尾巴相对长度，1 是基础尾长"}
};

function chatDesign(args, original) {
  const expanded = expandStrokes(args);
  const design = readDesign({...original, ...expanded});
  for (const key of Object.keys(scales)) {
    const value = expanded[key] ?? original?.[key];
    if (value === undefined) continue;
    if (!Number.isFinite(value) || value < .65 || value > 1.5) throw new RangeError(key);
    design[key] = value;
  }
  return design;
}

// A request for an unsupported body may only produce an explanation. An explicit
// change of brief in a later message is evaluated on its own terms.
function needsDifferentBody(text) {
  const intent = text.replace(/(?:不要|不用|不必|不会|不需要|不能|不想要|不想|不再)(?:会|能够|能)?(?:飞行|游泳|飞翔|飞鸟|飞|游|水生|翅膀)/g, "");
  return /飞鸟|鸟类|小鸟|鸟儿|凤凰|蝙蝠|翅膀|鹦鹉|燕子|麻雀|飞行|飞翔|会飞|能飞|水生|水栖|游泳|鱼类|金鱼|鲸鱼|海豚|章鱼|鲤鱼|一(?:条|尾)鱼|吃肉|食肉|捕猎|\b(?:bird|wings?|fly|flying|aquatic|fish|swim(?:ming)?|carnivore)\b/i.test(intent);
}

async function decideChat(observation, stream, reply) {
  const utterance = observation.player_text;
  if (typeof utterance !== "string" || !utterance.trim() || utterance.length > 1200) throw new RangeError("player_text");
  const habitats = observation.habitats.filter(site => site.can_birth);
  const existing = observation.editable_works ?? [];
  const shape = {...properties, ...strokes, ...scales};
  const line = {type:"string",description:"直接对玩家说的中文回复，最多220字"};
  const toolSpec = (name, description, fields, required) => ({name, description,
    parameters:{type:"object",properties:fields,required,additionalProperties:false}});
  const choicesForTurn = [toolSpec("reply_to_player","回答问题、澄清或说明能力并让玩家选择",{reply:line},["reply"])];
  const limited = needsDifferentBody(utterance);
  if (!limited && !observation.brush_busy) {
    if (habitats.length) choicesForTurn.push(toolSpec("draw_life","按玩家明确创作要求新画一只四足食皮兽",
      {reply:line,habitat_id:choices(habitats.map(site=>site.id)),...shape},["reply","habitat_id",...Object.keys(properties)]));
    if (existing.length) choicesForTurn.push(toolSpec("revise_life","只改玩家选中的现有小兽，保留未提到的笔和它的取食记录",
      {reply:line,work_id:choices(existing.map(w=>w.work_id)),changes:{type:"object",properties:shape,additionalProperties:false,minProperties:1}},["reply","work_id","changes"]));
  }
  const prompt = `你是《纸间》的牧师，正在同远处的玩家对话。最后一条玩家原话和本局事实见下方 JSON。只调用一次给出的工具。聊天、询问和模糊要求用 reply_to_player。玩家明确要求创作或同意上轮可行方案才落笔。目标不清时问玩家，勿把闲聊或询问当作下单。按原话照顾外形、毛色、步态、速度和取食偏好。你画得出陆地四足食皮兽：灰 ash、蜜金 honey、栗棕 chestnut；慢步 amble、小跑 trot、蹦跳 bound；只能啃或撕树皮，偏爱橡 oak、松 pine、果树 orchard_tree。鸟、飞行、水栖、吃肉等无法实现，无法满足的重要条件用纯回复向玩家说明，并问是否接受一个明确可行的方案。没有玩家同意不能代换。回复不要宣称已经完成。无地块时不可新画。改稿选明确的原兽 work_id，只写要改的字段。躯干 body、头 head、耳 ear、尾 tail、腿 leg 的画法为分别写4至12位0至9的数字，从右侧起逆时针等分一圈，每位指定径向轮廓。mark 是背纹逐点高度。长耳和长尾可用 ear_scale 与 tail_scale。\n${JSON.stringify(observation)}`;
  const {calls,trace} = await stream(prompt,choicesForTurn,2000);
  const call = calls[0];
  if (calls.length !== 1 || !call?.id || !choicesForTurn.some(t=>t.name===call.name)) throw new Error("invalid-command");
  const args = parseArguments(call);
  if (typeof args.reply !== "string" || !args.reply.trim() || args.reply.length>220) throw new RangeError("reply");
  reply.raw_tool_call = {id:call.id,name:call.name,arguments:args};
  const command = {tool:call.name,call_id:call.id,served_model:trace?.response_model??"",reply:args.reply.trim()};
  if (call.name === "reply_to_player" && limited)
    command.capability_note="本轮仅对话。当前生命笔支持陆地四足食皮兽，若要采用这一方案，请再告诉牧师。";
  if (call.name === "draw_life") {
    if (!habitats.some(h=>h.id===args.habitat_id)) throw new RangeError("habitat_id");
    command.habitat_id=args.habitat_id;
    command.design=chatDesign(args);
    if (observation.creatures.some(w=>w.name===command.design.name)) throw new RangeError("name");
  }
  if (call.name === "revise_life") {
    const work = existing.find(w=>w.work_id===args.work_id);
    if (!work || !args.changes || Array.isArray(args.changes) || typeof args.changes!=="object" ||
        !Object.keys(args.changes).length || Object.keys(args.changes).some(k=>!(k in shape))) throw new RangeError("changes");
    command.work_id=work.work_id;
    command.design=chatDesign(args.changes,work.design);
    if (Object.keys(args.changes).every(k=>JSON.stringify(command.design[k])===JSON.stringify(work.design[k]))) throw new RangeError("unchanged");
    if (observation.creatures.some(w=>w.work_id!==work.work_id && w.name===command.design.name)) throw new RangeError("name");
  }
  if (["reply_to_player","revise_life"].includes(call.name) && observation.creatures?.length) presentDietReply(command,observation);
  return {tool_call_id:call.id,command};
}

async function decideEcology(observation, stream, reply) {
  const sites = observation.habitats;
  if (!Array.isArray(sites) || !sites.length) throw new Error("no-habitat");
  const fertile = sites.filter(site => site.can_birth);
  const common = {
    habitat_id: choices(sites.map(site => site.id)),
    goal: {type:"string",description:"用一句简短中文写你当次的目标"},
    reason: {type:"string",description:"用一句简短中文说明本地观测依据"}
  };
  const action = (name, description, fields) => ({name,description,parameters:{
    type:"object",properties:fields,required:Object.keys(fields),additionalProperties:false}});
  const tools = [
    action("survey_habitat","走到该生境实地考察树木、食物和已有生物",common),
    action("wait_habitat","暂缓行动，让现有生物和树恢复平衡",common)
  ];
  const wounded = sites.flatMap(site => site.trees.filter(tree => tree.hp>0 && tree.lost_hp>0).map(tree => tree.id));
  if (wounded.length) tools.push(action("tend_habitat","走去照看一棵受伤的活树，暂时引开食皮兽",
    {...common,tree_id:choices([...new Set(wounded)])}));
  if (fertile.length) tools.push(action("draw_life","选择可容纳新个体的空地，设计一只四足食皮兽",
    {...common,habitat_id:choices(fertile.map(site=>site.id)),...properties,...strokes}));
  // Put currently relevant choices first without committing any of them. The model
  // can still select any feasible action, including waiting with an empty grove.
  const rank = wounded.length ? ["tend_habitat","wait_habitat","survey_habitat","draw_life"]
    : ["draw_life","survey_habitat","wait_habitat"];
  tools.sort((a,b)=>rank.indexOf(a.name)-rank.indexOf(b.name));
  const available = tools.filter(item => observation.mode === "commission" ? item.name === "draw_life" :
    item.name !== "survey_habitat" || !observation.survey_is_current);
  if (!available.length) throw new RangeError("no-birth-habitat");
  const prompt = `你是山野里的牧师，照看林地和生物。凭现场观测自己确定本轮目标，调用一个给出的工具。评价可食树的实际伤势、成熟果实、已有食皮兽的数量和偏好、原生动物以及可落脚空间。若局部食物充足且空缺食皮兽，可以设计新种；食物紧张、树受伤或已有足够的兽，考虑巡看、给受伤树暂时避食或等待。有清楚的实测数据时可以直接行动；完成过现场巡看后利用结果，避免重复勘察同一地块。若附近存在树况良好而没有食皮兽的空生境，可主动补一个适应该地的新物种。不同林地可作不同决定，勿为数量而造。果实只供村民和玩家食用，模型小兽只能啃食树皮；评估新兽食物时必须使用可食树树皮的生命和伤势，不能用果实的多少替代。对原生动物没有记录的食谱不要猜测。只返回工具调用。draw_life 分别给 body、head、ear、tail、leg 设计轮廓笔谱，每个字段只写4至12位数字字符串。从右侧起沿等角度方向逆时针一周，依次指定中心到外沿的长度0至9，接成有面积的侧面轮廓。例如“95843769”是一笔八角度的偏心外形；每个部件须按你选的宽尾、尖耳、圆头或短足另写。mark 各位数表示从左到右的背纹高度。已有邻居时另起名字，躯干轮廓也须有区别。goal、reason 填写简短中文。现场 ${JSON.stringify(observation)}`;
  reply.priest_attempts = [];
  let correction = "";
  for (let n=0; n<2; n++) {
    try {
      const {calls,trace} = await stream(prompt+correction,available,2400);
      const call = calls[0];
      const receipt = {tool_call_id:call?.id ?? null,tool:call?.name ?? null,
        requested_model:trace?.wire_request_model ?? null,response_model:trace?.response_model ?? null,accepted:false};
      reply.priest_attempts.push(receipt);
      if (calls.length!==1 || !call?.id || !available.some(tool=>tool.name===call.name)) throw new Error("invalid-command");
      const args=parseArguments(call);
      reply.raw_tool_call={id:call.id,name:call.name,arguments:args};
      const site=sites.find(item=>item.id===args.habitat_id);
      if (!site) throw new RangeError("habitat_id");
      for (const key of ["goal","reason"]) {
        if (typeof args[key]!=="string" || !args[key].trim() || args[key].length>180) throw new RangeError(key);
      }
      const command={tool:call.name,call_id:call.id,habitat_id:site.id,goal:args.goal.trim(),reason:args.reason.trim(),served_model:trace?.response_model??""};
      const repairs=[];
      if (call.name==="tend_habitat") {
        if (!site.trees.some(tree=>tree.id===args.tree_id && tree.hp>0 && tree.lost_hp>0)) throw new RangeError("tree_id");
        command.tree_id=args.tree_id;
      }
      if (call.name==="draw_life") {
        if (!site.can_birth) throw new RangeError("habitat_id");
        const ink = expandStrokes(args);
        command.design=readDesign(ink,repairs);
        if (observation.creatures?.some(animal=>animal.name===command.design.name)) throw new RangeError("name (请另取新兽名)");

      }
      reply.raw_tool_call={id:call.id,name:call.name,arguments:args};
      receipt.accepted=true;
      return {tool_call_id:call.id,repairs,command};
    } catch (error) {
      const rejected=reply.priest_attempts.at(-1);
      if (rejected && !rejected.accepted) rejected.validation=error.message;
      if (n || !(error instanceof RangeError || error instanceof SyntaxError || error.message==="invalid-command")) throw error;
      correction=`\n请修复 ${error.message}，只用观测里可行的生境、树编号和工具；请对照上面的坐标格式，六个部位各写一串4至12位的数字，只用0到9，每位是轮廓径长或背纹高度。你上一稿是 ${JSON.stringify(reply.raw_tool_call?.arguments??{}).slice(0,2500)}。`;
    }
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  await runWorker(decidePriest, "priest");
}
