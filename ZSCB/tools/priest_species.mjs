import {isDeepStrictEqual} from "node:util";
import {readFile} from "node:fs/promises";
import {createHash} from "node:crypto";
import {parseArguments} from "./east_painter.mjs";

import {contourTouchesItself, edgeBendsSchema, sampleContour} from "./priest_contour.mjs";
import {checkMarks,markList,markRefs} from "./priest_part_marks.mjs";
import {fruitPose} from "./priest_fruit_pose.mjs";
import {resolveStudy,studyIDs,studyPath,studyHash,wetBankStudy,waderIDs,waderStudy} from "./priest_form_studies.mjs";
import {reviewPose} from "./priest_pose_review.mjs";

const artPath="tools/skills/priest-life/SKILL.md";
const dutyPath="tools/skills/priest-ecology/SKILL.md";
const schema="species-ink-v1";
const actions=["ground_walk","sense_food","graze_bark","graze_grass","eat_ground_fruit","avoid_people","flee","hunt_livestock","threaten_people","guard_food","fly"];
const motions=["fixed","stride","sway","jaw","flap"];
const text={type:"string"};
const number=(min,max)=>({type:"number",minimum:min,maximum:max});
const choices=values=>({type:"string",enum:values});
const pair={type:"array",minItems:2,maxItems:2,items:number(-2.5,2.5)};
const object=(properties,required=Object.keys(properties))=>({type:"object",properties,required,additionalProperties:false});
const inkDetail=object({marks:markList,mark_refs:markRefs},[]);
const part=object({edge_bends:edgeBendsSchema,marks:markList,mark_refs:markRefs,study:choices(studyIDs),study_scale:{type:"array",minItems:2,maxItems:2,items:number(.2,2.5)},id:text,parent:text,joint:pair,motion:choices(motions),phase:number(0,1),rate:number(.5,3),amplitude:number(0,1.1),pigment:text,depth:choices(["far","body","near"]),wash:number(0,1),outline:{type:"array",minItems:3,maxItems:12,items:pair}},["id","parent","joint","motion","phase","pigment"]);
// A contour or gait revision inherits the rest of the original part, including its ink.
const poseFields=["outline","edge_bends","phase","rate","amplitude"];
const poseEdit=object(Object.fromEntries(poseFields.map(key=>[key,part.properties[key]])),[]);
const fruitBite=object({part_id:text,vertex:{type:"integer",minimum:0,maximum:11},pivot_id:text,dip:number(-1.4,1.4)},["part_id"]);
const sheet=object({fruit_bite:fruitBite,name:text,edible:{type:"boolean"},pace:number(.5,3.5),flight_height:number(.8,3),sight:number(3,18),favorite:choices(["oak","pine","orchard_tree"]),actions:{type:"array",items:choices(actions)},parts:{type:"array",minItems:3,maxItems:16,items:part}},["name","edible","pace","sight","actions","parts"]);
const fn=(name,description,properties={},required=Object.keys(properties))=>({name,description,parameters:object(properties,required)});
const validNumber=(x,a,b)=>Number.isFinite(x)&&x>=a&&x<=b;
const validPair=p=>Array.isArray(p)&&p.length===2&&p.every(x=>validNumber(x,-2.5,2.5));
function outlineOK(points, maxPoints=12, minimumEdge=.005) {
  if (!Array.isArray(points)||points.length<3||points.length>maxPoints||!points.every(validPair))return false;
  const cross=(p,q,r)=>(q[0]-p[0])*(r[1]-p[1])-(q[1]-p[1])*(r[0]-p[0]);
  let area=0;
  for(let i=0;i<points.length;i++){
    const a=points[i],b=points[(i+1)%points.length];
    if(Math.hypot(a[0]-b[0],a[1]-b[1])<minimumEdge)return false;
    area+=a[0]*b[1]-a[1]*b[0];
    for(let j=i+2;j<points.length;j++){
      if(!i&&j===points.length-1)continue;
      const c=points[j],d=points[(j+1)%points.length];
      if(cross(a,b,c)*cross(a,b,d)<0&&cross(c,d,a)*cross(c,d,b)<0)return false;
    }
  }
  return Math.abs(area)>.0004;
}
export function readSpecies(raw) {
  if(!raw||typeof raw.name!=="string"||!raw.name.trim()||raw.name.length>24)throw Error("物种名限1–24字");
  if(typeof raw.edible!=="boolean"||!validNumber(raw.pace,.5,3.5)||!validNumber(raw.sight,3,18)||raw.favorite!==undefined&&!sheet.properties.favorite.enum.includes(raw.favorite))throw Error("速度、感知范围、可食性或树种无效");
  const a=raw.actions;
  if(!Array.isArray(a)||!a.every(v=>actions.includes(v))||new Set(a).size!==a.length||!a.length||a.some(v=>["graze_grass","graze_bark","hunt_livestock","eat_ground_fruit"].includes(v))&&!a.includes("sense_food")||a.some(v=>["flee","avoid_people","hunt_livestock"].includes(v))&&!a.includes("ground_walk"))throw Error("采食和捕食需sense_food，主动追猎或逃跑需ground_walk；可组合或独立惊扰居民");
  if(raw.flight_height!==undefined&&!validNumber(raw.flight_height,.8,3))throw Error("飞行高度0.8–3米");
  if(!Array.isArray(raw.parts)||raw.parts.length<3||raw.parts.length>16)throw Error("需3–16个可见部件");
  raw={...raw,parts:raw.parts.map(resolveStudy)};
  const pivots=new Map(),xs=[0],ys=[0];
  for(const p of raw.parts){
    if(!p||typeof p.id!=="string"||!/^[a-zA-Z_][a-zA-Z_0-9]{0,31}$/.test(p.id)||pivots.has(p.id)||(pivots.size?!pivots.has(p.parent):p.parent!==""))throw Error("根须最先、parent 为空；其余父在子前，id 用唯一英文标识");
    if((p.depth!==undefined&&!["far","body","near"].includes(p.depth))||(p.wash!==undefined&&!validNumber(p.wash,0,1)))throw Error("层次填 far/body/near，淡彩 wash 为 0–1");
    if(!validNumber(p.rate??1,.5,3)||!validNumber(p.amplitude??.4,0,1.1)||!validPair(p.joint)||!motions.includes(p.motion)||!validNumber(p.phase,0,1)||!/^#[\da-f]{6}$/i.test(p.pigment)||!outlineOK(p.outline))throw Error("部件 "+p.id+" 的枢轴、动作、颜色或轮廓有误；轮廓须非自交且不重复首点");
    const contour=sampleContour(p);
    if(p.edge_bends?.length && (!outlineOK(contour,192,.000001) || contourTouchesItself(contour)))
      throw Error("部件 "+p.id+" 的弯边回折或相交，请收回控制点，保留嘴角和脚端。");
    checkMarks(p,contour);
    const [px,py]=pivots.get(p.parent)??[0,0];const at=[px+p.joint[0],py+p.joint[1]];pivots.set(p.id,at);
    for(const [x,y] of contour){xs.push(at[0]+x);ys.push(at[1]+y);}
  }
  if(a.includes("eat_ground_fruit")) {
    raw.fruit_bite=fruitPose(raw,pivots,Math.min(...ys.slice(1))).settings;
  } else if(raw.fruit_bite!==undefined)throw Error("拾果口缘必须与食性 eat_ground_fruit 同时指定。");
  if(a.includes("fly")&&raw.parts.filter(p=>p.motion==="flap"&&(p.amplitude??.65)>=.15).length<2)throw Error("需要至少两件在飞行中真实拍动的翼");
  if(a.includes("ground_walk")&&!raw.parts.some(p=>["stride","sway"].includes(p.motion)&&(p.amplitude??.4)>.02)||!validNumber(Math.max(...xs)-Math.min(...xs),.25,4.5)||!validNumber(Math.max(...ys)-Math.min(...ys),.2,3))throw Error("生命需要能活动的部件，整兽宽0.25–4.5米、高0.2–3米");
  const result=Object.fromEntries(Object.keys(sheet.properties).map(k=>[k,raw[k]]));
  return {schema,...result,name:raw.name.trim()};
}
function mouthMeasurement(design) {
  if(!design.fruit_bite)return {};
  const pivots=new Map();
  let floor=Infinity;
  for(const part of design.parts) {
    const [parentX,parentY]=pivots.get(part.parent)??[0,0];
    const pivot=[parentX+part.joint[0],parentY+part.joint[1]];
    pivots.set(part.id,pivot);
    floor=Math.min(floor,...sampleContour(part).map(([,y])=>pivot[1]+y));
  }
  const {settings,height}=fruitPose(design,pivots,floor);
  return {pose:settings,mouth_height:height,unit:"m"};
}
const brief={goal:text,reason:text,reply:text};
function limitedBody(s) {
  return /在水里游|游泳|水栖|水生|潜水|\b(?:swimming|aquatic)\b/i.test(s.replace(/(?:不要|不能|不会|不必|不用)(?:飞行|游泳|飞翔|飞)/g,""));
}
function requestedInkChange(words) {
  if(!/眼睛|眼纹|眼神|眼缘|嘴缝|口缘|吻缘|扇骨|尾辐|颊斑|细笔|[补添描勾]一笔/.test(words))return false;
  return words.split(/[，。！？；、\n]/).some(clause=>
    !/可不可以|是否|为什么|如果|假如|会怎样|会如何|能不能|不要|先别|只问|不用|别动|请解释|怎么|[吗么]/.test(clause) &&
    /(?:请(?:你)?|给它|帮它|帮我|麻烦(?:你)?|你来|把它)[^。]{0,18}(?:补|添|描|加|画清|勾|画上)|^只在[^，。！？]{1,20}(?:补|添|描|勾)(?:上|一|几|点)|^(?:再|先|只)?(?:补一|添一|描一|加一|补点|描清)/.test(clause));
}
function needsFruitFood(request) {
  const words=request.replace(/(?:不要|不必|不用|不能|不会|拒绝|不想|不肯|不)(?:去|会)?(?:找|捡|吃|采食|接受|投喂|喂)[^，。；;、]{0,8}果/g,"");
  return /(?:找|捡|啄|采食|取食|吃|投喂|喂食|喂它|喂给|接受|接过|以)[^，。；;]{0,12}(?:落果|朱果|浆果|果实|水果|果子|地上的果|放的果)|(?:落果|果实|水果|浆果)(?:为食|喂食)|(?:eat|forage for|feed on|accept|feed (?:it|the animal))[^.,;]{0,18}(?:fruit|berries)/i.test(words);
}
// Project dietary claims onto the selected animal's executable actions. The provider
// receipt keeps the original words, including statements the game cannot confirm.
const foodKinds = [
  ["graze_grass", "牧草", /(?:吃|食|啃|嚼|割|喂|低头)[^。；，、]{0,9}草|草食|牧草|地表草|graz(?:e|es|ing)|grass/i],
  ["graze_bark", "树皮", /树皮|啃树|bark/i],
  ["hunt_livestock", "可食牲畜", /捕食|猎食|吃肉|猎(?:杀|取)?牲畜|hunt(?:s|ing)? livestock|eat(?:s|ing)? meat/i],
  ["eat_ground_fruit", "地面朱果", /落果|浆果|朱果|水果|果实|果子|(?:捡|拾|吃|接|摘|采|喂)(?:食)?果|fruit|berries/i],
];
const asksDiet = /吃什么|能吃|吃不吃|会吃|以什么为食|什么喂|可以喂|食性|怎么喂|能不能吃|what (?:can|does|will).*eat|can .*eat/i;
const foodTopic = /饱食|食性|取食|觅食|喂|吃什么|食物|饮食|diet|feed|forage|eat/i;
function actionsOf(animal) {
  return Array.isArray(animal.feeding) ? animal.feeding : ["gnaw","strip"].includes(animal.feeding) ? ["graze_bark"] : [];
}
function dietSubjects(o, words) {
  const known=(o.creatures??[]).filter(a=>typeof a.work_id==="string" && a.work_id);
  const named=known.filter(a=>words.includes(a.work_id) || a.name && words.includes(a.name));
  if(named.length || /每只|各自|分别|所有|哪些/.test(words))return named.length ? named : known;
  const focus=known.find(a=>a.work_id===o.focus_id);
  return focus ? [focus] : known.length===1 ? known : [];
}
function projectDiet(command, subjects, request) {
  if(!subjects.length)return command;
  const mentionsDiet=asksDiet.test(request) || foodTopic.test(request+" "+command.reply) || foodKinds.some(([, , pattern])=>pattern.test(request+" "+command.reply));
  if(!["revise_species","revise_life"].includes(command.tool) && !mentionsDiet)return command;
  command.diet_work_ids=subjects.map(a=>a.work_id);
  // Keep complete sentences of the provider's response. A statement about a
  // food outside the relevant repertoire is answered from the live record.
  const wrongFullClaim = sentence => subjects.some(a=>Number.isFinite(a.satiety) &&
    (!Number.isFinite(a.ground_fruit_full_at) || a.satiety<a.ground_fruit_full_at)) && /(?:它|这只|当前|现在|已经|早已)[^，。；]{0,6}(?:是饱的|已经饱了|吃饱了|饱着|很饱)/.test(sentence);
  const keep = value => (value.match(/[^。！？!?；;\n]+[。！？!?；;\n]*/g)??[]).filter(sentence=>
    !wrongFullClaim(sentence) && !/(?:从|在|爬上)[^。；，]{0,5}树(?:上|枝|梢)[^。；，]{0,5}(?:摘|吃|取)|(?:直接|自己)(?:从)?[^。；，]{0,4}(?:背包|包里)(?:取|拿|吃)/.test(sentence) && !foodKinds.some(([action,,pattern])=>pattern.test(sentence) && subjects.some(a=>!action || !actionsOf(a).includes(action)))
  ).join("").trim();
  // A direct diet question can get a bare “yes” even with no food name.
  // Its visible answer is built from the subject in the live world.
  command.diet_question=command.tool==="reply_to_player" && asksDiet.test(request);
  if(!command.diet_question){
    const originalReply=command.reply;
    command.reply=keep(command.reply);
    if(wrongFullClaim(originalReply) && subjects.length===1)command.reply+="现场记录的饱食为 "+subjects[0].satiety+(Number.isFinite(subjects[0].ground_fruit_full_at)?"，低于拾果饱食线 "+subjects[0].ground_fruit_full_at:"")+"。";
  }
  if(command.tool==="revise_species"){
    command.reason=keep(command.reason) || "按原图与委托修改指定笔稿。";
    command.goal=keep(command.goal) || "完成玩家指定的改绘。";
  }
  return command;
}
export function presentDietReply(command, observation) {
  const subjects=command.work_id ? observation.creatures.filter(a=>a.work_id===command.work_id) : dietSubjects(observation,observation.player_text);
  return projectDiet(command,subjects,observation.player_text);
}
function words(s){return typeof s==="string"&&s.trim()&&s.length<=220;}
const summarize=site=>({id:site.id,page:site.page,land:site.space&&site.water_depth===0,food:site.healthy_food_trees,grass:site.grass_units,ground_fruit:site.fruit_units??0,damage:site.tree_damage,livestock:site.livestock,predators:site.predators});
function viable(site,design){
  const a=design.actions;
  const foods=a.filter(v=>["hunt_livestock","graze_bark","graze_grass","eat_ground_fruit"].includes(v));
  return (!design.edible||site.livestock<3)&&(!a.includes("hunt_livestock")||site.predators<1)&&(!foods.length||
    foods.some(v=>v==="eat_ground_fruit"?site.fruit_units>0:v==="hunt_livestock"?site.livestock>0:v==="graze_grass"?site.grass_units>0:site.healthy_food_trees>0));
}
export function recallPriest(o, query="") {
  const tokens=query.trim().toLowerCase().split(/\s+/).filter(Boolean);
  const books=(o.blueprints??[]).map(({blueprint_id,name,goal,reason,origin_work_id})=>({blueprint_id,name,goal,reason,origin_work_id}));
  const byID=new Map(books.map(book=>[book.blueprint_id,book]));
  const animals=new Map((o.creatures??[]).map(animal=>[animal.work_id,animal]));
  const matches=row=>{
    const related=animals.get(row.work_id);
    const book=byID.get(row.blueprint_id??related?.blueprint_id);
    const fields=[...Object.values(row),related?.name,related?.blueprint_id,book?.name];
    const corpus=fields.filter(v=>typeof v==="string").join(" ").toLowerCase();
    return tokens.every(token=>corpus.includes(token));
  };
  return {identity:o.identity,commitments:(o.commitments??[]).filter(matches),library:books.filter(matches),events:(o.memory??[]).filter(matches)};
}
export async function decideSpecies(o,stream,reply){
  const skills=await Promise.all([artPath,dutyPath].map(async path=>{
    const body=await readFile(new URL("./"+path.slice(6),import.meta.url),"utf8");
    return {path,body,sha256:createHash("sha256").update(body).digest("hex")};
  }));
  reply.priest_skills=skills.map(({path,sha256})=>({path,sha256}));
  const journal=reply.priest_steps=[];
  const chat=o.task==="priest_chat";
  const limited=chat && limitedBody(o.player_text);
  const saved=o.blueprints??[], context={role:"priest",world_reports:o.world_reports,scope:o.scope,focus_id:o.focus_id,mode:o.mode,player_text:o.player_text,history:o.messages?.slice(-4),
    travel:o.travel,reachable_alternatives:o.last_route_alternatives,known_places:o.navigation_sites,goal:o.prior_goal,population:o.population,last_result:o.last_result,habitats:o.habitats.map(summarize),creatures:o.creatures.map(c=>({id:c.work_id,name:c.name,state:c.phase,satiety:c.satiety,fruit_full_at:c.ground_fruit_full_at,fruit_target:c.ground_fruit_target??"",blueprint:c.blueprint_id,actions:c.feeding,diet_reply:o.diet_facts?.[c.work_id],foods:foodKinds.filter(([id])=>id&&actionsOf(c).includes(id)).map(([,name])=>name)})),
    editable:(o.editable_works??[]).map(w=>({work_id:w.work_id,blueprint_id:w.blueprint_id,name:w.design.name})),books:saved.map(b=>({id:b.blueprint_id,name:b.name})),open_reviews:(o.commitments??[]).filter(n=>n.status==="open").map(n=>[n.note_id,n.topic,n.review_when]),memory:o.memory?.slice(-3),brush_busy:o.brush_busy,cap:o.live_limit};
  const editable=(o.editable_works??[]).filter(w=>w.design.schema===schema);
  // A named contour may describe the feeding action it must still perform.
  const contourRequest=chat && /(?:只改|只把|只调整|只重画|只重绘)[^，。；！？]{0,40}(?:外形|轮廓|掌缘|趾端|翼尖|翼的外段|口缘|吻形|翼相)/.test(o.player_text);
  const dietEdit=chat && !contourRequest && !/新画|新造|新种|新设计|另一只/.test(o.player_text) && /(?:改|增加|学会|教会|教它|添上|赋予|加上|学着|调整|补上|使它|让它)/.test(o.player_text) && (needsFruitFood(o.player_text)||/拾果|捡果|食果|吃落果/.test(o.player_text));
  const inkTouchUp=chat && !/新画一只|再造|新物种|另外一只/.test(o.player_text) && requestedInkChange(o.player_text);
  const singlePart=chat && (!dietEdit || inkTouchUp) && !o.brush_busy && !limited && o.creatures.length>0 && (inkTouchUp ||
    /只(?:把|改|重画|重绘)|单(?:个|一|件)部件|保留同一只|只调整|only (?:change|redraw|repaint)|redraw (?:just|only)/i.test(o.player_text));
  const motionEdit=singlePart && /翼|拍翅|喙|吻|颊|趾|足|关节|俯身|低头|抬脚|折叠|步态|收掌|剪影|轮廓|wing|gait|silhouette/i.test(o.player_text);
  if(motionEdit) {
    const path="tools/skills/priest-life/references/motion.md";
    const body=await readFile(new URL("./"+path.slice(6),import.meta.url),"utf8");
    const sha256=createHash("sha256").update(body).digest("hex");
    skills.push({path,body,sha256});
    reply.priest_skills.push({path,sha256});
  }
  if(singlePart || dietEdit) {
    const named=o.creatures.filter(c=>o.player_text.includes(c.work_id)||o.player_text.includes(c.name));
    context.focus_id=o.focus_id;
    const originals=named.length?editable.filter(w=>named.some(c=>c.work_id===w.work_id)):editable;
    context.original_parts=originals.map(w=>({work_id:w.work_id,blueprint_id:w.blueprint_id,name:w.design.name,
      phase:o.creatures.find(c=>c.work_id===w.work_id)?.phase,at_brush:w.at_brush,actions:w.design.actions,parts:w.design.parts,...(motionEdit?{fruit_bite:w.design.fruit_bite??null,pose_review:reviewPose(w.design)}:{})}));
  }
  const hungry=(o.creatures??[]).filter(a=>Array.isArray(a.feeding)&&a.feeding.includes("graze_grass")&&a.satiety<65&&!["dead","drawing","fly","land","takeoff"].includes(a.phase));
  const pastureIDs=[...new Set((o.local_life?.pastures??[]).filter(p=>p.portions>0).map(p=>p.id))];
  context.forage={carried:o.carried_grass??0,hungry:hungry.map(a=>({id:a.work_id,name:a.name,satiety:a.satiety,blocked_by:a.blocked_by})),pastures:pastureIDs};
  const husbandry=o.pasture_care ?? {};
  const transplantTargets=(husbandry.animals??[]).filter(a=>a.sites.length);
  const donorIDs=(husbandry.sources??[]).map(p=>p.id);
  const rootIDs=husbandry.roots_in_hand??[];
  if(husbandry.animals?.length)context.pasture_care=husbandry;
  const held=o.pending_placement;
  const canResolve=Boolean(held?.id) && !o.brush_busy && !limited && (chat || (o.mode==="autonomous" && held.autonomous));
  if(held?.id) context.pending_placement={
    id:held.id, source_call:held.source_call, name:held.design.name, actions:held.design.actions, edible:held.design.edible,
    goal:held.goal, problem:held.problem, options:held.options, autonomous:held.autonomous
  };
  const ground=o.habitats.filter(h=>h.space&&h.water_depth===0);
  let pendingPose=null;
  const thoughts=[], updates=[];let draft=null;let acceptedDrafts=0;let editedWork=null;let editedPart="";
  const prompt=skills.map(s=>s.body).join("\n")+ "\n你是牧师，本轮自己选择工具；查询或审稿的真实结果将提供给下一步。想借眼缘、嘴缝或扇骨的真实笔线，可先 read_art_reference(wet-bank) 看原笔号与实际点列，再用 detail.mark_refs 或 detail.marks 补在真实轮廓内。creatures 的 actions 与 foods 是每个个体现行图纸的真实能力；回答某只现有个体吃什么时可逐字回复 diet_reply；客户端会复核最新个体。foods 为空就没有可执行取食动作，sense_food 只表示感知。不得根据名字、过往对话、是否可食或生态愿望推断饮食；只有 eat_ground_fruit 才能拾食地面上的落果和人放下的朱果。已有活体只改拾果食性，使用 adapt_fruit_diet，选原轮廓嘴缘的顶点与上级枢轴。新种在 draft_species 的 fruit_bite 定义同样的低头姿势和食性。现场确认收笔前只说已提交改稿。可查现场后自主等待或护养。能根据用途新创物种：先 draft_species 完整拆件，拿到草稿回执，再 ink_species 选生境落笔。reuse 时用已有 blueprint_id。改已出生的拆件种用 revise_species 并选择明确个体；新稿留入图纸簿。真实飞行须两件 flap 和 fly，纯装饰翼不能飞；水下游泳或爬墙尚无此能力，需要说明并询问替代。原创新图用 fruit_bite 只填 part_id 指定真实的嘴，即委托引擎在该嘴部和它的父链试量可接触果心的顶点及低头姿势，仍使用你的原画。若给定姿势不合但有实测备选，调用 accept_fruit_pose 保住整张原稿。可调用 read_art_reference(topic=wet-bank) 取湿岸实形，draft_species 的部件有 study 时可不填 outline。布局、体形、远近肢、颜色、joint、fruit_bite 和步相由你决定，也可自画任一件。每个部件内可自画 marks 细线 thin 或薄洗 wash，坐标是该部件原轮廓包围框的 0..1（左下为原点，x朝头，y向上），也可从取形页挑 mark_refs。只动纹样时用 redraw_part 的 detail，提交本件完整 marks 或 mark_refs，旧轮廓和关节会原样保留；眼纹、嘴缝和尾辐仍随原件一起动。avoid_people 是独立的真实近人退避动作，需要 ground_walk。可调用 read_art_reference 再审稿，remember_priest 留下以后要复查的承诺，recall_priest 可按词、图纸编号或作品查，review_priest 用实际变化结案或继续观察。单步只调用一项工具。";
  for(let n=0;n<10;n++){
    let tools=[fn("inspect_ecology","查真实饥劳、食物、活体、食痕和各处地块"),fn("recall_priest","按主题、物种、作品或编号查询长期手记与造种理由，不需要手记时继续当前委托；空查询列全部",{query:text}),fn("remember_priest","记下一项以后要复查的意图；无关联编号填空字符串",{topic:text,intent:text,review_when:text,blueprint_id:text,work_id:text}),fn("review_priest","按实际观察更新一条承诺，open 继续复查，resolved 结案",{note_id:text,outcome:{type:"string",maxLength:1000,description:"据实际结果写明判断，最多1000字"},status:choices(["open","resolved"])}),fn("read_art_reference","查笔法或侧视取形。wader 页有下弯喙、折翼和近远步足，part_id 可单取一件，含局部米制弯边与像素来源。",{topic:choices(["motion","form-and-ink","wet-bank","wader"]),part_id:choices(waderIDs)},["topic"]),fn("read_blueprint","读一份原物种的拆件和习性",{blueprint_id:text})];
    if(chat)tools.push(fn("reply_to_player","纯回复、询问或说明能力；不动世界",{reply:text}));
    else tools.push(fn("wait_habitat","留在原地等生态变化",{habitat_id:text,...brief}),fn("survey_habitat","到一个可达地块实地巡看",{habitat_id:text,...brief}),fn("tend_habitat","照看受损的活树以暂时免受啃食",{habitat_id:text,tree_id:text,...brief}));
    if(o.navigation_sites?.length&&!o.brush_busy) tools.push(fn("travel_to_place","牧师亲自步行、跳跃或下行去已生成地标或玩家指定的实际坐标。选目录编号，或 place_id 填空并给脚点 x、y；途中继续观察。",{place_id:text,x:number(-1000000,1000000),y:number(-1000000,1000000),...brief}));
    if(hungry.length && (pastureIDs.length || o.carried_grass) && !o.brush_busy && !held?.id)tools.push(fn("feed_livestock","牧师亲自走到真草场割下一份，再到指定饥饿草食个体跟前递交。有草在手时直接去喂。",{work_id:choices(hungry.map(a=>a.work_id)),pasture_id:choices(o.carried_grass?[""]:pastureIDs),...brief}));
    if(transplantTargets.length && (donorIDs.length||rootIDs.length) && !o.brush_busy && !held?.id) {
      tools.push(fn("transplant_pasture","牧师亲身从有产量的草场分一簇真根（扣一席容量）或用手中已有的根，再步行栽到该只兽能取食的实土。新根需要时间长草，本次不直接加饱食。source_id 和 root_id 二选一，另一项填空串。",{work_id:choices(transplantTargets.map(a=>a.work_id)),
        source_id:choices(["",...donorIDs]),root_id:choices(["",...rootIDs]),site_id:choices([...new Set(transplantTargets.flatMap(a=>a.sites.map(s=>s.id)))]),...brief}));
    }
    if(canResolve){
      if(held.options.length)tools.push(fn("choose_creation_site","按实际地形、食物和种群选择其中一处，以此前被挡的完整原稿造生一个个体。",{
        option_id:choices(held.options.map(site=>site.id)),...brief
      }));
      tools.push(fn("set_aside_creation","明确放弃这次被挡的笔稿，让场地休养；等待或巡看则仍可保留待选。",brief));
    }
    if(!limited&&!o.brush_busy&&(chat||!held?.id)){
      tools.push(fn("draft_species","设计或改绘原创物种图纸，返回形体与行为审稿；还未出生",{design:sheet,reason:text}));
      if(draft || chat&&o.editable_works?.some(w=>w.design.schema===schema))tools.push(fn("redraw_part","只改一件；work_id 填可改的活体编号，或 draft 表示本轮草图。用 pose 只改 outline、edge_bends、phase、rate 或 amplitude，原枢轴与内笔照旧；detail 只换内笔；replacement 完整交一件。",{work_id:text,part_id:text,replacement:part,detail:inkDetail,pose:poseEdit},["work_id","part_id"]));
      if(dietEdit && !draft && editable.length) tools.push(fn("adapt_fruit_diet","玩家要求给同一只增加地果食性时，保留全部原件和原行动，选口缘顶点及可让它低头的父链关节。",{work_id:choices(editable.map(w=>w.work_id)),fruit_bite:fruitBite,...brief}));
      if(draft||saved.length)tools.push(fn("ink_species","从图纸在真实场地绘制一个新个体",{blueprint_id:text,habitat_id:text,...brief}));
      if(draft)tools.push(fn("file_species","收存本轮新物种原图，暂不造生",brief));
      if(chat&&draft&&o.editable_works?.some(w=>w.design.schema===schema))tools.push(fn("revise_species","用新稿改绘指定的同一只拆件生命，保留身份和进度",{work_id:text,...brief}));
    }
    if(pendingPose)tools.unshift(fn("accept_fruit_pose","批准同一张暂存原稿中的实测低头姿势，保留全部原手笔、立姿与步态。随后可直接落笔。",{}));
    const read=journal.map(s=>s.tool);
    tools=tools.filter(t=>t.name!=="recall_priest"||read.filter(x=>x===t.name).length<2)
      .filter(t=>t.name!=="read_art_reference"||read.filter(x=>x===t.name).length<2)
      .filter(t=>t.name!=="read_blueprint"||read.filter(x=>x===t.name).length<2)
      .filter(t=>t.name!=="inspect_ecology"||!read.includes(t.name))
      .filter(t=>t.name!=="remember_priest"||!updates.some(u=>u.tool===t.name))
      .filter(t=>t.name!=="read_blueprint"||saved.length>0)
      .filter(t=>t.name!=="review_priest"||o.commitments?.length&&!updates.some(u=>u.tool===t.name));
    if(draft){
      tools=tools.filter(t=>["ink_species","file_species","revise_species","reply_to_player","remember_priest","draft_species","redraw_part","accept_fruit_pose"].includes(t.name));
      if(acceptedDrafts>=3)tools=tools.filter(t=>!["draft_species","redraw_part"].includes(t.name));
      if(editedWork)tools=tools.filter(t=>["revise_species","redraw_part","reply_to_player","remember_priest"].includes(t.name));
    }
    if(singlePart && !draft) {
      const art=tools.find(t=>t.name==="read_art_reference");
      tools=[fn("reply_to_player","对象含糊、能力不符或玩家只在询问时说明；请求明确且可执行时直接改笔。",{reply:text})];
      if(art) tools.push(art);
      if(context.original_parts.length)tools.unshift(fn("redraw_part","对 original_parts 中明确的同一只局部改绘并送交现场。找到玩家所指的原件，改轮廓、步相请用 pose，仅提交 outline、edge_bends、phase、rate 或 amplitude 中要改的字段，继承原骨节与活动内笔。拾果嘴的原命中顶点留在同一序号和坐标。detail 只换本件内笔，replacement 可完整重绘一件。三种写法选一种。",
        {work_id:choices(context.original_parts.map(w=>w.work_id)),part_id:text,replacement:part,detail:inkDetail,pose:poseEdit,...brief},["work_id","part_id","goal","reason","reply"]));
    }
    const state=(singlePart?"\n这是同一个体的单件委托。original_parts 是发送时现场可改个体的完整原笔和当前阶段。原文中描述的部位由你读图选择。无需另查图纸；本次 redraw_part 把改笔交给这个 work_id。若玩家明确请你补眼、添纹样，完成需要实际 redraw_part；回复只用于澄清或说明困难。当前饱食见 creatures.satiety，拾果吃饱阈值见 fruit_full_at；at_brush 为 false 时，牧师还要走近、等原只落地，再由现场确认收笔。":"")+"\n当前为第"+(n+1)+"步。按以上已取得的工具结果推进；本步只发一个工具调用，不能并行或附带文字。";
    let turn;
    try {turn=await stream(prompt+"\n本局："+JSON.stringify(context)+"\n此前已执行："+JSON.stringify(thoughts)+state+(chat?" 当前玩家正在说："+o.player_text+"（以前聊天仅供参照。）":"")+(draft?" 你已有一张已通过审稿的图纸，编号严格为 draft。若改活体按其原编号 revise_species；若玩家要出生，现在调用 ink_species，并选择观察列表中的原样地块编号。":""),tools,6500);}
    catch(e){
      if((e.message==="invalid-command"||e.code==="invalid_command")&&!thoughts.some(t=>t.tool==="format_error")){
        thoughts.push({tool:"format_error",result:"服务商本步未给出可执行的单项调用。请只选下一项工具，提交一个完整参数对象。"});continue;
      }
      throw e;
    }
    const {calls,trace}=turn;
    const c=calls[0];if(calls.length!==1||!c?.id||!tools.some(t=>t.name===c.name))throw Error("invalid-command");
    const step={call_id:c.id,tool:c.name,model:trace?.response_model??""};journal.push(step);
    let result;
    try {
      const supplied=parseArguments(c);
      if(c.name==="draft_species"){pendingPose=null;step.submitted_design=supplied.design;}
      const a={...supplied};
      if(c.name==="reply_to_player"&&typeof a.reply==="string") {
        a.reply=a.reply.trim().slice(0,560);
        if(inkTouchUp && context.original_parts?.length===1) {
          const obstacle=journal.findLast(s=>s.tool==="redraw_part" && s.obstacle);
          if(obstacle) {
            a.reply="内笔尚未收稿："+obstacle.obstacle;
          } else throw Error("这句答复承诺实际补笔，但本轮还没有笔画。可对 original_parts 的原件用 redraw_part.detail 交 marks 或 mark_refs。若有具体疑问可向玩家提问。");
        }
      }
      switch(c.name){
        case "accept_fruit_pose":{
          if(!pendingPose)throw Error("没有待确认的口缘姿势");
          draft=readSpecies({...pendingPose.design,fruit_bite:pendingPose.pose});
          acceptedDrafts++;
          reply.priest_draft={design:draft,call_id:pendingPose.call_id,pose_call_id:c.id,model:step.model};
          step.original_call_id=pendingPose.call_id;
          step.measured=mouthMeasurement(draft);
          result={blueprint_id:"draft",accepted:true,pose_review:reviewPose(draft),next:"现在可 ink_species 选实际生境落笔。"};
          pendingPose=null;
          break;}
        case "inspect_ecology":result={pasture_care:husbandry,population:o.population,recent_effects:o.recent_effects,pending_placement:o.pending_placement,habitats:o.habitats,creatures:o.creatures,people:o.local_life,protected_tree:o.protected_tree};break;
        case "read_art_reference":{
          if(a.topic==="wader"){
            result=waderStudy(a.part_id);
            Object.assign(step,{path:result.path,sha256:result.sha256,source_sha256:result.source_sha256,trace_sha256:result.trace_sha256,
              forms:result.parts.map(p=>p.id)});
            break;
          }
          if(a.part_id!==undefined)throw Error("part_id 用于 wader 页选件；其他参考只填 topic。");
          if(a.topic==="wet-bank"){
            result=wetBankStudy();
            Object.assign(step,{path:studyPath,sha256:studyHash,source_sha256:result.source_sha256,forms:result.parts.map(p=>p.id),mark_resource:result.mark_resource,mark_ids:result.marks.map(m=>m.id)});
            break;
          }
          if(!["motion","form-and-ink"].includes(a.topic))throw Error("无此参考");
          const path="tools/skills/priest-life/references/"+a.topic+".md";
          const body=await readFile(new URL("./"+path.slice(6),import.meta.url),"utf8");
          const sha256=createHash("sha256").update(body).digest("hex");
          result={path,sha256,body};Object.assign(step,{path,sha256});break;
        }
        case "recall_priest":result=recallPriest(o,String(a.query??""));break;
        case "remember_priest":{
          if((o.commitments??[]).length+updates.filter(u=>u.tool===c.name).length>=128)throw Error("长期手记已满，可更新原承诺");
          if(!words(a.topic)||!words(a.intent)||!words(a.review_when)||a.blueprint_id&&!(a.blueprint_id==="draft"&&draft)&&!saved.some(b=>b.blueprint_id===a.blueprint_id)||a.work_id&&a.work_id!=="draft"&&!o.creatures.some(b=>b.work_id===a.work_id))throw Error("需写明主题、意图、复查条件及有效的关联编号");
          updates.push({tool:c.name,note_id:"note-"+createHash("sha256").update(c.id).digest("hex").slice(0,24),topic:a.topic,intent:a.intent,review_when:a.review_when,blueprint_id:a.blueprint_id??"",work_id:a.work_id??""});
          result={recorded:updates.at(-1).note_id};break;
        }
        case "review_priest":{
          if(!(o.commitments??[]).some(n=>n.note_id===a.note_id))throw Error("本队无此编号，先按主题检索手记");
          if(typeof a.outcome!=="string"||!a.outcome.trim()||a.outcome.length>1000)throw Error("实查结论需为1到1000字");
          if(!["open","resolved"].includes(a.status))throw Error("status 只填 open 或 resolved");
          updates.push({tool:c.name,note_id:a.note_id,outcome:a.outcome,status:a.status});result={reviewed:a.note_id};break;
        }
        case "read_blueprint":result=saved.find(b=>b.blueprint_id===a.blueprint_id)??{error:"目录中无此编号"};break;
        case "redraw_part":
        case "draft_species":{
          let next, source;
          if(c.name==="redraw_part"){
            if(editedWork && a.part_id!==editedPart)throw Error("这次局部改绘只可重画原先选中的同一件");
            if(editedWork && a.work_id!==editedWork.work_id && a.work_id!=="draft")throw Error("一次只能改同一只活体");
            if(singlePart && !draft && !context.original_parts.some(w=>w.work_id===a.work_id))throw Error("请选择本次委托所指的活体原件");
            source=a.work_id==="draft"?null:o.editable_works?.find(w=>w.work_id===a.work_id);
            const base=a.work_id==="draft"?draft:source?.design;
            const prior=base?.parts.find(p=>p.id===a.part_id);
            if(a.pose!==undefined) {
              if(!prior || a.detail!==undefined || a.replacement!==undefined || !a.pose || typeof a.pose!=="object" ||
                  Array.isArray(a.pose) || !Object.keys(a.pose).length || Object.keys(a.pose).some(k=>!poseFields.includes(k))) {
                throw Error("pose 只交原件要修改的轮廓或步相，不能与 detail、replacement 同交。");
              }
              const bite=base.fruit_bite;
              if(bite?.part_id===prior.id && a.pose.outline!==undefined &&
                  !isDeepStrictEqual(a.pose.outline?.[bite.vertex],prior.outline[bite.vertex])) {
                throw Error("此件的实际拾果点须保留。原 outline["+bite.vertex+"] = "+JSON.stringify(prior.outline[bite.vertex])+"。");
              }
              if (prior.edge_bends?.length && a.pose.outline && a.pose.outline.length!==prior.outline.length && a.pose.edge_bends===undefined)
                throw Error("原轮廓的锚点数量已改变。请用新编号重列 edge_bends，若全用直线请交空数组。");
              a.replacement={...prior,...a.pose};
            }
            if(a.detail!==undefined){
              if(!prior||a.replacement!==undefined||!a.detail||typeof a.detail!=="object"||Array.isArray(a.detail)||Object.keys(a.detail).some(k=>!["marks","mark_refs"].includes(k))||a.detail.marks===undefined && a.detail.mark_refs===undefined)throw Error("只换内笔时请给 detail.marks 或 detail.mark_refs，并保留原件编号。");
              a.replacement={...prior,marks:[],...a.detail};
            }
            if(!prior || a.replacement?.id!==a.part_id)throw Error("请给可达的原作或 draft、原件编号和同编号的新笔稿");
            if(inkTouchUp){
              const {marks:oldInk,mark_refs:oldRefs,...oldBody}=prior;
              const {marks:newInk,mark_refs:newRefs,...newBody}=a.replacement;
              if(!isDeepStrictEqual(oldBody,newBody))throw Error("补内笔时须保留原轮廓和关节。用 detail.marks 或 detail.mark_refs 提交本部件的改笔即可。");
            }
            if(isDeepStrictEqual(base.parts.find(p=>p.id===a.part_id),a.replacement))throw Error("这件笔稿没有变化，请交回修订后的部件");
            next=readSpecies({...base,parts:base.parts.map(p=>p.id===a.part_id?a.replacement:p)});
            if(isDeepStrictEqual(prior,next.parts.find(p=>p.id===a.part_id)))throw Error("这件原笔没有变化。");
          }else next=readSpecies(a.design);
          if(source){editedWork=source;editedPart=a.part_id;}
          draft=next;pendingPose=null;acceptedDrafts++;
          result={blueprint_id:"draft",design:draft,pose_review:reviewPose(draft),accepted:true,next:"若委托要求出生，用 ink_species，blueprint_id 填 draft，habitat_id 必须来自现场。"};
          step.pose_review=result.pose_review;
          const details=draft.parts.filter(p=>p.marks?.length).map(p=>({part_id:p.id,count:p.marks.length,
            strokes:p.marks.map((m,i)=>({index:i,brush:m.brush,pigment:m.pigment,points:m.points.length,source:m.source??null})),
            sha256:createHash("sha256").update(JSON.stringify(p.marks)).digest("hex")}));
          if(details.length || a.detail) {step.part_ink=details;result.part_ink=details;}
          if(draft.fruit_bite)step.measured=mouthMeasurement(draft);
          if(c.name==="redraw_part"){
            step.part_id=a.part_id;
            if(a.pose)step.pose_fields=Object.keys(a.pose);
          }
          reply.priest_draft={design:draft,call_id:c.id,model:step.model};
          if(singlePart && c.name==="redraw_part" && (a.goal!==undefined || a.reason!==undefined || a.reply!==undefined)) {
            if(!source || ![a.goal,a.reason,a.reply].every(words))throw Error("请给出原个体编号及简短目标、理由和回复");
            step.result="单件改稿已交游戏现场复核";
            reply.raw_tool_call={id:c.id,name:c.name,arguments:supplied};
            return {tool_call_id:c.id,command:projectDiet({tool:"revise_species",call_id:c.id,served_model:step.model,
              source_blueprint_id:source.blueprint_id,edit_part_id:a.part_id,work_id:source.work_id,design:draft,
              goal:a.goal,reason:a.reason,reply:a.reply,memory_updates:updates},[{work_id:source.work_id,feeding:draft.actions}],o.player_text)};
          }
          break;}
        default:{
          if(!(typeof a.reply==="string"&&a.reply.trim()&&a.reply.length<=(c.name==="reply_to_player"?560:220))||c.name!=="reply_to_player"&&(!words(a.reason)||!words(a.goal)))throw Error("请填写简短的中文回复、目标和现场理由");
          const command={memory_updates:updates,tool:c.name,call_id:c.id,served_model:step.model,reply:a.reply.trim(),goal:a.goal?.trim(),reason:a.reason?.trim()};

          if(c.name==="adapt_fruit_diet"){
            const base=editable.find(w=>w.work_id===a.work_id);
            if(!base || !chat || base.design.actions.includes("eat_ground_fruit"))throw Error("请选择委托所指的尚无拾果食性的现有个体。");
            const design=readSpecies({...base.design,actions:[...new Set([...base.design.actions,"sense_food","eat_ground_fruit"])],fruit_bite:a.fruit_bite});
            Object.assign(command,{tool:"revise_species",work_id:base.work_id,source_blueprint_id:base.blueprint_id,design});
            projectDiet(command,[{work_id:base.work_id,feeding:design.actions}],o.player_text);
          } else if(c.name==="transplant_pasture"){
            const target=transplantTargets.find(b=>b.work_id===a.work_id);
            if(!target?.sites.some(s=>s.id===a.site_id) || Boolean(a.root_id)===Boolean(a.source_id) || (a.root_id?!rootIDs.includes(a.root_id):!donorIDs.includes(a.source_id)))throw Error("请选择同一只原兽实测能采的栽点，以及一处可分草场或牧师在手的一簇根。");
            Object.assign(command,{work_id:a.work_id,source_id:a.source_id,root_id:a.root_id,site_id:a.site_id});
          } else if(c.name==="feed_livestock"){
            if(!hungry.some(h=>h.work_id===a.work_id)||!(o.carried_grass?a.pasture_id==="":pastureIDs.includes(a.pasture_id)))throw Error("请选实查的饥饿个体和可割的草场");
            Object.assign(command,{work_id:a.work_id,pasture_id:a.pasture_id});
          } else if(c.name==="choose_creation_site"){
            if(!held.options.some(site=>site.id===a.option_id))throw Error("请选现场列出的落点编号");
            command.option_id=a.option_id;
          } else if(c.name==="set_aside_creation"){
            if(!canResolve)throw Error("没有待选的笔稿");
          } else if(c.name==="travel_to_place"){
            const site=o.navigation_sites.find(s=>s.id===a.place_id);
            if(a.place_id&&!site)throw Error("观察中的地点编号无效");
            const at=site?.at??[a.x,a.y];
            if(!Array.isArray(at)||at.length!==2||!at.every(x=>validNumber(x,-1e6,1e6)))throw Error("请给有效脚底坐标");
            Object.assign(command,{at,place_id:a.place_id,label:site?.name??site?.label??a.place_id??""});
          } else if(c.name==="ink_species"){
            const book=saved.find(b=>b.blueprint_id===a.blueprint_id);
            const design=a.blueprint_id==="draft"?draft:book?.design;
            if(!design)throw Error("选择 draft 或目录中的真实编号");
            const site=ground.find(h=>h.id===a.habitat_id);
            if(!site||!site.room_for_species||!viable(site,design))throw Error("复核种群或生境失败，选择其他确有食物的地块或暂缓");
            const description=a.reply.replace(/(?:不(?:会|能|再|去)?|没有|尚未|无法|不能够)(?:捡|吃|啃|采食|猎)[^，。；、]{0,8}/g,"");
            if(needsFruitFood(description) && !design.actions.includes("eat_ground_fruit"))throw Error("这张图纸缺少 eat_ground_fruit 和真实口缘，不能声称能拾食果实。");
            if(/吃(?:地表|地上|牧|嫩)?草|采食牧草/.test(description) && !design.actions.includes("graze_grass"))throw Error("回复所称吃草与原稿 actions 不符；请修稿增加真实食草或准确描述现有行为。");
            Object.assign(command,{blueprint_id:a.blueprint_id,habitat_id:site.id,design});
          } else if(c.name==="file_species")command.design=draft;
          else if(c.name==="revise_species"){
            if(editedWork&&editedWork.work_id!==a.work_id)throw Error("必须改绘本轮选中特定个体");
            if(editedWork) Object.assign(command,{source_blueprint_id:editedWork.blueprint_id,edit_part_id:editedPart});
            if(!o.editable_works.some(w=>w.work_id===a.work_id&&w.design.schema===schema))throw Error("原作已不可达");
            Object.assign(command,{work_id:a.work_id,source_blueprint_id:o.editable_works.find(w=>w.work_id===a.work_id).blueprint_id,design:draft});
            projectDiet(command,[{work_id:a.work_id,feeding:draft.actions}],o.player_text);
          } else if(c.name!=="reply_to_player"){
            const h=o.habitats.find(h=>h.id===a.habitat_id);if(!h)throw Error("请选择观测中的生境编号");
            command.habitat_id=h.id;
            if(c.name==="tend_habitat"){
              if(!h.trees.some(t=>t.id===a.tree_id&&t.hp>0&&t.lost_hp>0))throw Error("该地块没有这棵受伤活树");
              command.tree_id=a.tree_id;
            }
          }
          if(c.name==="reply_to_player")presentDietReply(command,o);
          step.result="已交游戏现场复核";reply.raw_tool_call={id:c.id,name:c.name,arguments:supplied};return {tool_call_id:c.id,command};
        }
      }
      step.result=["draft_species","redraw_part","accept_fruit_pose"].includes(c.name)?"拆件有效，共 "+draft.parts.length+" 件":"查得现场记录";
    } catch(e){
      result={error:e.message};step.result=e.message;
      if(c.name==="redraw_part")step.obstacle=e.message;
      if(e.poseOffer && c.name==="draft_species" && step.submitted_design){
        pendingPose={design:step.submitted_design,pose:e.poseOffer.settings,call_id:c.id};
        result.measured={pose:e.poseOffer.settings,mouth_height:e.poseOffer.height,unit:"m"};
        result.next="用 accept_fruit_pose 批准这份实测原稿，或再交自选的设计。";
        step.measured=result.measured;
      }else step.arguments=JSON.stringify(c.arguments).slice(0,300);
    }
    thoughts.push({tool:c.name,result});
  }
  throw Error("牧师本轮已达十次工具调用，尚未决定落笔");
}
