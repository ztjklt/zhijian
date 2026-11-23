// Project-scoped ink in metres. Only explicitly requested ink goes in the SDK prompt.
import { inspectDisplay } from "./companion_display_geometry.mjs";
const EPS=1e-8;
const sub=(a,b)=>[a[0]-b[0],a[1]-b[1]];
const dot=(a,b)=>a[0]*b[0]+a[1]*b[1];
const cross=(a,b)=>a[0]*b[1]-a[1]*b[0];
const lerp=(a,b,t)=>[a[0]+t*(b[0]-a[0]),a[1]+t*(b[1]-a[1])];
const len=a=>Math.hypot(...a);
const mm=n=>Math.round(n*1000)/1000;
const pair=p=>p.map(mm);

function project(p,a,b) {
  const d=sub(b,a), n=dot(d,d);
  return lerp(a,b,n>EPS*EPS?Math.max(0,Math.min(1,dot(sub(p,a),d)/n)):0);
}
function intersectionT(a,b,c,d) {
  const u=sub(b,a),v=sub(d,c),w=sub(c,a),den=cross(u,v);
  if(Math.abs(den)<=EPS)return null;
  const t=cross(w,v)/den, s=cross(w,u)/den;
  return t>=-EPS&&t<=1+EPS&&s>=-EPS&&s<=1+EPS?Math.max(0,Math.min(1,t)):null;
}
function segmentGap(a,b,c,d) {
  const t=intersectionT(a,b,c,d);
  if(t!==null){const p=lerp(a,b,t);return {p,q:p,gap:0};}
  let best;
  for(const [p,q] of [[a,project(a,c,d)],[b,project(b,c,d)],[project(c,a,b),c],[project(d,a,b),d]]){
    const gap=len(sub(q,p));
    if(!best||gap<best.gap)best={p,q,gap};
  }
  return best;
}
function edges(poly) {return poly.map((a,i)=>[a,poly[(i+1)%poly.length]]);}
// Boundary is treated as a geometric touch; positive interior lengths are reported separately.
function inside(p,poly) {
  let hits=0;
  for(const [a,b] of edges(poly)){
    if(len(sub(p,project(p,a,b)))<=EPS)return false;
    if((a[1]>p[1])!==(b[1]>p[1])&&p[0]<a[0]+(b[0]-a[0])*(p[1]-a[1])/(b[1]-a[1]))hits++;
  }
  return hits%2===1;
}
function coveredLength(a,b,faces) {
  const cuts=[0,1];
  for(const poly of faces)for(const [c,d] of edges(poly)){
    const t=intersectionT(a,b,c,d);
    if(t!==null)cuts.push(t);
  }
  cuts.sort((x,y)=>x-y);
  let covered=0;
  for(let i=1;i<cuts.length;i++){
    const lo=cuts[i-1],hi=cuts[i];
    if(hi-lo>EPS&&faces.some(poly=>inside(lerp(a,b,(lo+hi)/2),poly)))covered+=hi-lo;
  }
  return covered*len(sub(b,a));
}
function strokes(row) {
  return row.remaining??row.points.slice(1).map((end,i)=>[i,row.points[i],end]);
}
function bounds(points){
  if(!points.length)return null;
  return [Math.min(...points.map(p=>p[0])),Math.min(...points.map(p=>p[1])),Math.max(...points.map(p=>p[0])),Math.max(...points.map(p=>p[1]))].map(mm);
}
function refs(work,labels) {
  if(!Array.isArray(labels)||labels.length>8)return null;
  const rows=new Set();
  for(const key of labels){
    const matches=work.layers.filter(row=>typeof key==="number"?row.index===key:row.layer===key);
    if(!matches.length)return null;
    for(const row of matches)rows.add(row);
  }
  return [...rows];
}
function directory(work){return work.layers.map(row=>[row.index,row.layer]);}
function outline(work,row){
  const segments=strokes(row),coverage=[],lineCores=[];
  for(const later of work.layers.slice(row.index+1)){
    const faces=later.faces??[];
    const cores=(later.ink_core_strips??[]).flatMap(strip=>strip.slice(1).map(([c,d],i)=>[strip[i][0],c,d,strip[i][1]]));
    const covers=polys=>segments.reduce((sum,[,a,b])=>sum+coveredLength(a,b,polys),0);
    const wash=covers(faces),ink=covers(cores);
    if(wash>0.001)coverage.push({later_index:later.index,layer:later.layer,outline_inside_wash_m:mm(wash)});
    if(ink>0.001)lineCores.push({later_index:later.index,layer:later.layer,outline_inside_ink_core_m:mm(ink)});
  }
  const master=row.original?.points;
  const endpointGap=master?.length>=2?mm(len(sub(master[0],master.at(-1)))):null;
  return {index:row.index,layer:row.layer,brush:row.brush,pigment:row.pigment,
    master_endpoints_m:master?.length>=2?[pair(master[0]),pair(master.at(-1))]:null,
    master_endpoint_gap_m:endpointGap,
    master_layer:row.original?.layer??null,master_points_m:row.original?.points.map(pair)??null,
    reference:row.source??null,world_points_m:row.points.map(pair),
    ...(row.remaining?{surviving_authored_segments_m:row.remaining.map(([i,a,b])=>[i,pair(a),pair(b)])}:{}),
    drawn_bounds_m:bounds([...segments.flatMap(([,a,b])=>[a,b]),...(row.faces??[]).flat()]),
    later_wash_overlaps:coverage,later_line_core_overlaps:lineCores};
}
function nearest(rows,targets,filled=false) {
  let best;
  for(const row of rows)for(const [segment,a,b] of strokes(row))for(const target of targets){
    let hit=segmentGap(a,b,target.a,target.b);
    if(filled&&target.face){
      const p=inside(a,target.face)?a:inside(b,target.face)?b:null;
      if(p)hit={p,q:p,gap:0};
    }
    if(!best||hit.gap<best.hit.gap-EPS)best={row,segment,hit,target};
  }
  if(!best)return null;
  const {row,segment,hit,target}=best;
  return {from:{index:row.index,layer:row.layer,segment,at_m:pair(hit.p)},
    to:{...target.ref,at_m:pair(hit.q)},offset_to_target_m:pair(sub(hit.q,hit.p)),
    gap_m:mm(hit.gap),touches:hit.gap<=EPS};
}
export function inspectSceneLayers(snapshot,args){
  const work=snapshot?.works?.find(w=>w.id===args?.work_id);
  if(!work)return {ok:false,reason:"本工程没有这一件已落实物"};
  const base={project_id:snapshot.project_id,work_id:work.id,plan_id:work.plan_id,owner:work.plan_owner,world_origin_m:pair(work.origin),angle_rad:work.angle};
  if(!Array.isArray(args.layers)||!args.layers.length)return {...base,ok:true,layers:directory(work),fixture_layers:work.fixture_layers};
  const rows=refs(work,args.layers);
  if(!rows)return {...base,ok:false,reason:"没有这个笔号或完整图层名",layers:directory(work)};
  if(args.compare==="display"){
    const supports=refs(work,args.other_layers?.length?args.other_layers:work.fixture_layers);
    if(!supports?.length)return {...base,ok:false,reason:"没有可量的柜沿，请指定实际已画的承托层"};
    return {...base,...inspectDisplay(work,rows,supports,snapshot.view,args.display_scale)};
  }
  const result={...base,ok:true,selection:rows.map(row=>outline(work,row))};
  if(args.compare==="water"){
    const rims=[],areas=[];
    for(const wet of snapshot.water){
      wet.rims.forEach(([a,b],i)=>rims.push({a,b,ref:{water_id:wet.id,rim:i}}));
      for(const face of wet.fill)for(const [a,b] of edges(face))areas.push({a,b,face,ref:{water_id:wet.id}});
    }
    result.nearest_exposed_rim=nearest(rows,rims);
    result.nearest_liquid=nearest(rows,areas,true);
    return result;
  }
  if(!["fixtures","layers"].includes(args.compare))return {...base,ok:false,reason:"请选择 water、fixtures、layers 或 display"};
  const compare=refs(work,args.compare==="fixtures"?work.fixture_layers:args.other_layers);
  if(!compare)return {...base,ok:false,reason:"参照层不存在",layers:directory(work)};
  const targets=compare.flatMap(row=>strokes(row).map(([segment,a,b])=>({a,b,ref:{index:row.index,layer:row.layer,segment}})));
  result.nearest_other_outline=nearest(rows,targets);
  return result;
}
const selector={type:"array",maxItems:8,items:{anyOf:[{type:"integer",minimum:0},{type:"string"}]}};
export function withSceneLayerInspection(snapshot,stream,reply) {
  if(!snapshot?.works?.length)return stream;
  const book=snapshot.works.map(w=>({work_id:w.id,name:w.name,layers:directory(w)}));
  const tool={name:"inspect_scene_layers",description:"读本工程已经落地的实物，依母图原层名或零基笔号量实际轮廓。water 对仍存在的水面和水体，fixtures 对该实物登记的案柜边缘，layers 对自选其他层。display 用所选货形在已画柜沿上试排，量顾客及画家当前姿态、使用位投影、墨迹遮叠、可留白的中心范围与当前笔程，未落笔。返回最近线段、偏移、母图来源及同一物件后画淡洗/浓细线笔芯实际叠过的轮廓长度。",parameters:{type:"object",additionalProperties:false,required:["work_id","layers","compare","other_layers"],properties:{display_scale:{type:"number",minimum:.1,maximum:4,description:"仅 display 可选。对所选货组绕底边中点等比试排，缺省 1，实际图纸保持原样。"},work_id:{type:"string",enum:book.map(w=>w.work_id)},layers:selector,compare:{type:"string",enum:["water","fixtures","layers","display"]},other_layers:{...selector,description:"layers 时填参照笔；display 时可指定承托笔，留空用已登记设施。"}}}};
  let reads=0,results="";
  return async(prompt,tools,tokens)=>{
    const canRead=tools.some(t=>["design_building","variant_building","plan_scene","revise_scene_plan","pause_scene","verify_scene","divine_reply","finish_scene_foundation","reuse_shore_plan","finish_vegetation","revise_scene_component"].includes(t.name));
    if(!canRead)return stream(prompt,tools,tokens);
    let context="\n可查的本工程已建实物与原层（编号从0起）。点读一次后原行动仍可选。"+JSON.stringify(book);
    while(reads<2){
      const result=await stream(prompt+context+results,[...tools,tool],tokens);
      const call=result.calls?.[0];
      if(call?.name!==tool.name)return result;
      reads++;
      let args,measurement;
      try{args=typeof call.arguments==="string"?JSON.parse(call.arguments):call.arguments;measurement=inspectSceneLayers(snapshot,args);}
      catch(error){measurement={ok:false,reason:"查询参数无效"};}
      (reply.scene_layer_reads??=[]).push({id:call.id,args,ok:measurement.ok,model_trace:reply.model_trace});
      results+="\n所选实物的当前测量（世界米，y 向上；同一物件后画笔迹与所选轮廓的交叠）"+JSON.stringify(measurement);
    }
    return stream(prompt+context+results,tools,tokens);
  };
}
