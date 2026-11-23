import { expandCurveMark, withCurveGeometry } from "./paper_curve.mjs";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { buildingStudyCatalogue, expandBuildingStudyGroup, resolveBuildingStudy } from "./building_studies.mjs";
import { assignTrade, tradeSchema } from "./building_trade.mjs";
import { parseArguments } from "./east_painter.mjs";

const washes = ["wash", "wash_pool"];
const brushes = ["bold", "fine", ...washes];
const pigments = ["inherit", "ochre", "cinnabar", "indigo", "malachite"];
const styles = ["ink", "pencil"];
const obj = properties => ({ type: "object", properties, required: Object.keys(properties), additionalProperties: false });
const list = (items, minItems, maxItems, description) => ({ type: "array", items, minItems, maxItems, description });
const pair = list({ type: "number" }, 2, 2, "相对图纸底部原点的[x,y]米，向右、向上为正");
const label = { type: "string", minLength: 1, maxLength: 32 };
const enumOf = values => ({ type: "string", enum: values });
const indexEnum = values => ({ type:"integer", enum:values });
const strokeIndex = value => Number.isInteger(value)?value:
  typeof value==="string"&&/^(?:-1|0|[1-9][0-9]{0,3})$/u.test(value)?Number(value):NaN;
const freeMark = obj({ layer: { ...label, description: "这笔画的是哪一层或构件" },
  brush: enumOf(brushes), pigment: enumOf(pigments), points: list(pair, 2, 32, "模型实际绘制的连续一笔；直处省点、弯处采点") });
const selectedMark = obj({layer:label, study:{type:"string",description:"建筑参考页的完整 study 编号"},
  stroke:{type:"integer",minimum:0,description:"该页原笔号，从0起"}, origin:pair,
  scale:list({type:"number",exclusiveMinimum:0},2,2,"绕共用页原点缩放宽高"),
  mirror_x:{type:"boolean"}, pigment:enumOf(["source",...pigments])});
const mark = {anyOf:[...withCurveGeometry(freeMark).anyOf,selectedMark]};
const referencePlacement = obj({...selectedMark.properties,
  before:{type:"integer",minimum:0,description:"在手绘笔数组的哪个0基笔号之前插入。等于手绘笔数表示追加。同位置引用按数组顺序。"}});
function groupedPlacement(selector, field) {
  const {stroke, ...common}=selectedMark.properties;
  return {type:"object",additionalProperties:false,properties:{...common,[selector]:field,before:referencePlacement.properties.before},
    required:["layer","study",selector,"origin","before"]};
}
const groupByStroke=groupedPlacement("strokes",{type:"array",minItems:1,maxItems:32,uniqueItems:true,items:{type:"integer",minimum:0},description:"同一参考页原笔号，自动按原作先后展开"});
const groupByPart=groupedPlacement("part",{type:"string",description:"取 reference_pages 中该页 parts 的部件名或 groups[].layer；按原笔顺展开"});
const referenceMarks = list({anyOf:[referencePlacement,groupByStroke,groupByPart]}, 0, 32,
  "使用实际参考原笔时填这里。单笔或一组共用变换，纯手绘可留空。展开后此处最多32笔，另检查全图笔数。");
const station = obj({ x:{type:"number"}, use:{...label,description:"人物在这一处办理的具体用途"},
  cover:enumOf(["sheltered","open"]),
  roof_layers:list(label,0,6,"遮蔽站位填写实际遮雨屋面笔的完整唯一图层名，可写一笔连续棚面或若干相接屋面。露天站位填空数组。"),
  fixture_layers:list(label,0,8,"为这个站位服务的实体台面、柜身、正面架板或堆货所在层。站在它旁边，不能让这些墨迹穿过人体；无实物时可为空。") });
const layoutFields = {
  supports_x: list({type:"number"}, 2, 12, "抄出落在局部地平线 y=0 上的墙脚、屋柱或棚柱的 x。每个 x 必须有你真实画出的 [x,0] 锚点；桌面与柜腿无需填报。"),
  stations: list(station,1,6,"画出工作净空后逐个申报使用位。肩宽0.60米、净高1.50米；遮雨站位两肩都必须在指定屋面下方。")
};
const baseTool = { name: "design_building", description: "自由设计一套新的建筑母图，用真实公共笔刷逐笔画出用途、轮廓、结构与可达工作位置。",
  parameters: obj({ name: label, style: enumOf(styles),
    reference_marks: referenceMarks,
    marks: list(mark, 0, 48, "其他手绘笔按从背后到前景的实际绘制顺序，连同取件展开后须有3至48笔"), ...layoutFields }) };
function variantTool(count) {
  const index = { type: "integer", enum: Array.from({length:count},(_,i)=>i) };
  return { name: "variant_building", description: "保留一份编号母图，把适应当地需要的局部改稿另存为新图。索引始终指原母图。",
    parameters: obj({ name: label, replace: list(obj({ index, mark }), 0, 36, "替换原稿中编号笔画，原先顺序保留"),
      remove: list(index, 0, 36, "移除母图中指定编号的笔画"),
      reference_marks: {...referenceMarks,description:referenceMarks.description+" 此处 before 以 add 的笔序为准。"},
      add: list(mark, 0, 36, "追加在末层的笔画，或留空"),
      ...layoutFields }) };
}

function need(condition, explanation) { if (!condition) throw new RangeError(explanation); }
const point = v => Array.isArray(v) && v.length === 2 && v.every(Number.isFinite);
const distance = (a,b) => Math.hypot(a[0]-b[0], a[1]-b[1]);
const digest = obj => createHash("sha256").update(JSON.stringify(obj)).digest("hex");
function nameOf(value) {
  need(typeof value === "string" && value.trim().length > 0 && [...value].length <= 32 &&
    !/[\u0000-\u001f\u007f]/u.test(value), "名称或构件图层需要1至32字简短文字");
  return value.trim();
}
function exactly(row, fields) {
  need(row && typeof row === "object" && !Array.isArray(row) && Object.keys(row).length === fields.length &&
    fields.every(key => Object.hasOwn(row,key)), "仅接受工具列出的必填字段");
}
function mergeReferencePlacements(drawing,variant) {
  const {reference_marks:references,...rest}=drawing;
  if(references===undefined)return rest;
  const key=variant?"add":"marks";
  const marks=rest[key];
  need(Array.isArray(references)&&references.length<=32&&Array.isArray(marks),"取件需要有效的 reference_marks 和手绘笔数组");
  const byPosition=Array.from({length:marks.length+1},()=>[]);
  let expandedCount=0;
  for(const placement of references){
    need(placement && typeof placement==="object","每项引用须给出原页、笔号或部件与插入位置");
    const {before,...reference}=placement;
    need(Number.isInteger(before)&&before>=0&&before<=marks.length,"取件 before 须在0至手绘笔数之间");
    let selected;
    if(Object.hasOwn(reference,"strokes") || Object.hasOwn(reference,"part")){
      selected=expandBuildingStudyGroup(reference);
    }else{
      exactly(placement,Object.keys(referencePlacement.properties));
      selected=[reference];
    }
    expandedCount+=selected.length;
    need(expandedCount<=32,"reference_marks 展开共"+expandedCount+"笔，原接口最多32笔；请缩减选笔");
    byPosition[before].push(...selected);
  }
  return {...rest,[key]:marks.flatMap((ink,i)=>[...byPosition[i],ink]).concat(byPosition.at(-1))};
}

function segmentDistance(p,a,b) {
  const dx=b[0]-a[0], dy=b[1]-a[1], denominator=dx*dx+dy*dy;
  const u = denominator ? Math.max(0,Math.min(1,((p[0]-a[0])*dx+(p[1]-a[1])*dy)/denominator)) : 0;
  return distance(p,[a[0]+u*dx,a[1]+u*dy]);
}
const turn = (a,b,c) => (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0]);
function washBoundary(points) {
  need(points.length >= 4 && distance(points[0],points.at(-1)) <= 0.025, "淡墨须沿边绕一圈，最后回到自己的起点");
  const ring = points.slice(0,-1).filter((p,i) => i === 0 || distance(p,points[i-1]) > 0.0001);
  const length = ring.length;
  const area = ring.reduce((sum,a,i) => sum + turn([0,0],a,ring[(i+1)%length]),0);
  need(length >= 3 && Math.abs(area) > .00001, "闭合淡墨需要有面积的单一轮廓");
  for (let i=0; i<length; i++) {
    const a=ring[i], b=ring[(i+1)%length];
    for (let j=i+2; j<length; j++) {
      if (i === 0 && j === length-1) continue;
      const c=ring[j], d=ring[(j+1)%length];
      const touch = [segmentDistance(a,c,d),segmentDistance(b,c,d),segmentDistance(c,a,b),segmentDistance(d,a,b)].some(v => v < 1e-7);
      need(!touch && !(turn(a,b,c)*turn(a,b,d) < 0 && turn(c,d,a)*turn(c,d,b) < 0), "闭合淡墨轮廓不能自交；复杂形体请拆作不同色块");
    }
  }
}
function readMark(input, fromParent = false) {
  if (!fromParent && input && Object.hasOwn(input,"study")) {
    const {source,...ink}=resolveBuildingStudy(input);
    return {...readGeometry(ink,true),source};
  }
  return readGeometry(fromParent ? input : expandCurveMark(input),fromParent,fromParent);
}
function readGeometry(input, longPath, inherited = false) {
  exactly(input,["layer","brush","pigment","points"]);
  const {points,brush,pigment} = input;
  need(brushes.includes(brush) && pigments.includes(pigment), "请选公共笔触与色板里的颜料");
  need(Array.isArray(points) && points.length >= 2 && points.length <= (longPath ? 8192 : 32), "每条新墨线须有2至32个点");
  need(points.every(p => point(p) && Math.hypot(...p)<=24),
    "图纸的米制局部笔迹距原点最多24米；请勿提交世界坐标");
  need(points.slice(1).reduce((n,p,i) => n+distance(p,points[i]),0) >= .045, "景物笔的最短笔长是0.045米");
  if (washes.includes(brush) && !inherited) washBoundary(points);
  return { layer:nameOf(input.layer), brush, pigment, points:points.map(p=>[...p]) };
}

function parentPage(parent) {
  need(Number.isInteger(parent?.id) && parent.id>0, "改稿需要一张本轮选定的编号母图");
  const command=parent.command, layout=parent.layout;
  need(command?.tool === "draw_scenery" && styles.includes(command.style) && Array.isArray(command.strokes) &&
    command.strokes.length >= 1 && command.strokes.length <= 128 && layout?.layers?.length === command.strokes.length,
    "改稿需要母图的零原点完整逐笔稿、笔触和图层");
  need(command.strokes.reduce((n,path)=>n+(Array.isArray(path)?path.length:8193),0)<=8192,
    "母图超过公共图纸8192个采样点的上限");
  for (const field of ["brushes","pigments"]) {
    need(command[field]===undefined || Array.isArray(command[field]) && command[field].length===command.strokes.length,
      "母图公共笔触或颜料数量与笔画不一致");
  }
  const marks=command.strokes.map((points,i) => readMark({ layer:layout.layers[i], points,
    brush:command.brushes?.[i] ?? "bold", pigment:command.pigments?.[i] ?? "inherit" },true));
  if (layout.stroke_sources) {
    need(Array.isArray(layout.stroke_sources) && layout.stroke_sources.length===marks.length,"母图逐笔出处与图层数量不符");
    for(const [i,source] of layout.stroke_sources.entries()){
      if (source===null) continue;
      need(typeof source?.source_work_id==="string" && Number.isInteger(source.source_stroke) && source.source_stroke>=0,"母图原笔出处无效");
      marks[i].source={source_work_id:source.source_work_id,source_stroke:source.source_stroke};
    }
  }
  need(Array.isArray(layout.supports) && Array.isArray(layout.access) && [...layout.supports,...layout.access].every(point),
    "母图缺少支点或使用位");
  return {id:parent.id,name:parent.name,style:command.style,marks,supports:layout.supports,access:layout.access,
    stations:Array.isArray(layout.stations)?layout.stations:[]};
}

const shoulder = .30, stepAllowance = .10, pairedShift = .33, personHeight = 1.50;
const workersAt=(s,program)=>program?.workers===2&&s.use===program.use?2:1;
const bodyRadius=(s,program)=>shoulder+stepAllowance+(workersAt(s,program)===2?pairedShift:0);
function referencedLayers(names,marks,maximum) {
  need(Array.isArray(names)&&names.length<=maximum,"工作位引用的构件层数无效");
  return [...new Set(names.map(name=>{
    const indices=marks.map((m,i)=>m.layer===name?i:-1).filter(i=>i>=0);
    need(indices.length===1,`站位所引「${name}」需与最终稿的一笔图层名完全相同且唯一`);
    return indices[0];
  }))];
}

// Clip each polyline segment to the body's full horizontal interval. Its end
// heights bound its continuous height on that interval, including sloped roofs.
function clippedSegment(a,b,left,right) {
  if (a[0]>b[0]) [a,b]=[b,a];
  const lo=Math.max(left,a[0]), hi=Math.min(right,b[0]);
  if (hi<lo) return null;
  if (a[0]===b[0]) return [lo,hi,Math.min(a[1],b[1]),Math.max(a[1],b[1])];
  const height=x=>a[1]+(b[1]-a[1])*(x-a[0])/(b[0]-a[0]);
  return [lo,hi,Math.min(height(lo),height(hi)),Math.max(height(lo),height(hi))];
}
export function verifyStations(stations,marks,supports,shelterRequired,program) {
  need(Array.isArray(stations)&&stations.length>=1&&stations.length<=6,"设计须列出人物在哪里办理用途");
  const verified=stations.map(s=>{
    exactly(s,["x","use","cover","roof_layers","fixture_layers"]);
    need(Number.isFinite(s.x)&&["sheltered","open"].includes(s.cover),"站位需要横坐标及 sheltered 或 open");
    const use=nameOf(s.use), roof=referencedLayers(s.roof_layers,marks,6), fixtures=referencedLayers(s.fixture_layers,marks,8);
    const radius=bodyRadius(s,program);
    const left=s.x-radius,right=s.x+radius;
    need(supports.every(p=>Math.abs(p[0]-s.x)>=radius+.015),`「${use}」人物双肩区间 [${left.toFixed(2)},${right.toFixed(2)}] 与柱脚相撞，请把站位与柱错开`);
    need((s.cover==="sheltered") === (roof.length>0),"遮雨位必须引用真实屋面层，露天使用位的屋面列表须为空");
    const spans=[];
    for(const i of [...roof,...fixtures]) {
      const points=marks[i].points;
      for(let j=1;j<points.length;j++) {
        const clip=clippedSegment(points[j-1],points[j],left,right);
        if(!clip) continue;
        const [lo,hi,min,max]=clip;
        if(fixtures.includes(i)) {
          need(max<=.04 || min>=personHeight,`「${use}」身体范围与「${marks[i].layer}」相交，挪到柜/货旁空位或改变构件形状`);
        }
        if(roof.includes(i)) {
          need(min>=personHeight-1e-6,`「${use}」上方「${marks[i].layer}」最低 ${min.toFixed(2)} 米，达不到1.50米净高`);
          if(hi-lo>1e-8) spans.push({lo,hi,min,stroke:i});
        }
      }
    }
    if(roof.length) {
      spans.sort((a,b)=>a.lo-b.lo);
      let edge=left;
      for(const span of spans){ if(span.lo>edge+1e-6) break; edge=Math.max(edge,span.hi); }
      need(edge>=right-1e-6,`「${use}」双肩区间 [${left.toFixed(2)},${right.toFixed(2)}] 米没有被指定屋面完整覆盖。从 x=${edge.toFixed(2)} 起有缺口。至少留出 ${(radius*2).toFixed(2)} 米宽的棚内通行空间，再申报其中心与真实棚面层。`);
    }
    return {x:s.x,use,cover:s.cover,workers:workersAt(s,program),walk_tolerance:stepAllowance,roof_layers:s.roof_layers,roof_indices:roof,fixture_layers:s.fixture_layers,
      fixture_indices:fixtures,body_x:[left,right],required_height:personHeight,minimum_roof_y:spans.length?Math.min(...spans.map(v=>v.min)):null};
  });
  need(!shelterRequired||verified.some(s=>s.cover==="sheltered"),"委托中的遮雨用途需要至少一个实际受屋面保护的工作位");
  return verified;
}

// Each candidate is tested with the same continuous geometry that will
// authorize the finished page. The artist chooses; no site is moved silently.
function alternatives(stations,marks,supports,program) {
  const xs=marks.flatMap(m=>m.points.map(p=>p[0])), lo=Math.min(...xs)-.8, hi=Math.max(...xs)+.8;
  const options=[];
  stations.forEach((s,index)=>{
    const choices=[];
    const accept=x=>{
      try{verifyStations([{...s,x}],marks,supports,false,program);choices.push(x);}catch(e){if(!(e instanceof RangeError))throw e;}
    };
    accept(s.x);
    for(let grid=Math.ceil(lo*25);grid<=Math.floor(hi*25);grid++)accept(grid/25);
    const distinct=[];
    for(const x of choices.sort((a,b)=>Math.abs(a-s.x)-Math.abs(b-s.x))) {
      if(distinct.length===8) break;
      if(distinct.every(other=>Math.abs(other-x)>.16))distinct.push(x);
    }
    distinct.forEach((x,i)=>options.push({id:`s${index}-${i}`,index,x,use:s.use,cover:s.cover}));
  });
  return options;
}

// Find the shoulder-width strip under each chosen roof before moving furniture.
// Roofs and all non-local marks remain immutable through a work-bay revision.
function bayOptions(stations,marks,supports,program) {
  const empty=stations.map(s=>({...s,fixture_layers:[]}));
  const candidates=alternatives(empty,marks,supports,program).filter(o=>!program.shelter_required ||
    (o.use===program.use&&o.cover==="sheltered"));
  const options=[];
  for(const o of candidates) {
    const station=stations[o.index], roof=referencedLayers(station.roof_layers,marks,6);
    const fixtures=referencedLayers(station.fixture_layers,marks,8);
    const radius=bodyRadius(station,program);
    const blockers=fixtures.filter(i=>marks[i].points.slice(1).some((b,j)=>{
      const c=clippedSegment(marks[i].points[j],b,o.x-radius,o.x+radius);
      return c&&c[2]<personHeight&&c[3]>.04;
    }));
    if(!blockers.length)continue;
    const coords=blockers.flatMap(i=>marks[i].points);
    const lower=Math.min(...coords.map(p=>p[0]))-.65, upper=Math.max(...coords.map(p=>p[0]))+.65;
    const ceiling=Math.max(1.65,...coords.map(p=>p[1]+.85));
    const editable=[];
    marks.forEach((m,i)=>{
      if(roof.includes(i))return;
      // A connected counter, its legs, loaded baskets and goods may move as
      // one group. A wall/roof spanning beyond the work fixture is preserved.
      if(blockers.includes(i)||m.points.every(p=>p[0]>=lower&&p[0]<=upper&&p[1]<=ceiling))editable.push(i);
    });
    options.push({...o,body:[o.x-radius,o.x+radius],blockers,editable});
  }
  return options;
}

function workBayAttachments(marks,site,stations,supports) {
  const bounds=marks.map(({points})=>({
    x0:Math.min(...points.map(p=>p[0])),x1:Math.max(...points.map(p=>p[0])),
    y0:Math.min(...points.map(p=>p[1])),y1:Math.max(...points.map(p=>p[1]))
  }));
  const edges=marks.map(({points})=>points.slice(1).map((b,i)=>[points[i],b]));
  const roof=new Set(stations.flatMap(s=>referencedLayers(s.roof_layers,marks,6)));
  const rooted=(i,box)=>box.y0<=.15&&box.y1>=personHeight&&supports.some(([x,y])=>
    x>=box.x0-.08&&x<=box.x1+.08&&edges[i].some(([a,b])=>segmentDistance([x,y],a,b)<.085));
  const fixed=(i,box)=>roof.has(i)||rooted(i,box)||
    /^(?:主屋|房屋|墙体|墙身|门框|窗框|屋顶|屋脊|檐口|梁饰|梁身|脊梁)|棚(?:面|檐|柱|梁|柱脚|横梁|木撑|短木撑)/u.test(marks[i].layer);
  const links=[];
  const group=new Set(site.blockers);
  const touch=.055;
  for(const base of group){
    for(const i of site.editable){
      if(group.has(i)||fixed(i,bounds[i]))continue;
      const a=bounds[i], b=bounds[base];
      const x=(a.x0+a.x1)*.5;
      if(a.x0>b.x1+touch||a.x1<b.x0-touch||a.y0>b.y1+.28||a.y1<b.y0-touch)continue;
      const overheadSpan=a.y0>=b.y1-touch&&a.x1-a.x0>1.1&&(a.x1-a.x0)>(b.x1-b.x0)+.30;
      const touching=!overheadSpan&&a.y0<=b.y1+touch&&edges[i].some(([p,q])=>edges[base].some(([v,w])=>
        (turn(p,q,v)*turn(p,q,w)<0&&turn(v,w,p)*turn(v,w,q)<0) ||
        [segmentDistance(p,v,w),segmentDistance(q,v,w),segmentDistance(v,p,q),segmentDistance(w,p,q)].some(d=>d<=touch)));
      // Front-view fruit may be drawn a small distance above its rim so
      // the silhouette reads. Carry it if a real shelf/rim spans its centre
      // under the lower edge, and then follow contacting outline and stem.
      const resting=a.y0>=.35&&a.x1-a.x0<=1.35&&a.y1-a.y0<=1.20&&edges[base].some(([p,q])=>{
        if(Math.abs(p[0]-q[0])<.12||Math.abs(p[1]-q[1])>.72*Math.abs(p[0]-q[0]))return false;
        const at=clippedSegment(p,q,x,x);
        return at&&at[2]<=a.y0+.035&&a.y0-at[2]<=.28;
      });
      if(touching||resting){
        group.add(i);
        links.push({layer:marks[i].layer,attached_to:marks[base].layer,reason:touching?"contact":"above_surface"});
      }
    }
  }
  return {indices:[...group].sort((a,b)=>a-b),links};
}

function repositionBay(marks,supports,choice,edits) {
  exactly(edits,["target_id","layers","side","width_ratio"]);
  need(["left","right"].includes(edits.side)&&Number.isFinite(edits.width_ratio)&&edits.width_ratio>=.35&&edits.width_ratio<=1,
    "局部改柜需选择靠左或靠右，并保留35%至100%的原宽");
  need(Array.isArray(edits.layers)&&edits.layers.length>0&&edits.layers.length<=36,"局部改稿须指明移动的柜身或附属构件笔层");
  const indices=referencedLayers(edits.layers,marks,36);
  need(indices.every(i=>choice.editable.includes(i))&&choice.blockers.every(i=>indices.includes(i)),
    "只能成组修改当前可编辑构件，且须包含所有挡住该站位的柜板");
  const selected=indices.map(i=>marks[i]);
  const xs=selected.flatMap(m=>m.points.map(p=>p[0]));
  const left=Math.min(...xs),right=Math.max(...xs);
  const ratio=edits.width_ratio;
  const newLeft=edits.side==="left"?choice.body[0]-.06-(right-left)*ratio:choice.body[1]+.06;
  const mapX=x=>newLeft+(x-left)*ratio;
  const adjusted=marks.map((m,i)=>indices.includes(i)?{...m,points:m.points.map(([x,y])=>[mapX(x),y])}:m);
  const newSupports=supports.map(p=>{
    const anchored=m=>m.points.some(q=>distance(q,p)<.016);
    // A station's fixture leg can share a footing with a structural post.
    // Keep that post's footing and only move an anchor unique to the group.
    return selected.some(anchored)&&!marks.some((m,i)=>!indices.includes(i)&&anchored(m))?[mapX(p[0]),p[1]]:p;
  });
  return {marks:adjusted,supports:newSupports,indices};
}
function inspectLayout(marks,supports,access) {
  need(Array.isArray(supports) && supports.length>=2 && supports.length<=12 && Array.isArray(access) &&
    access.length>=1 && access.length<=6 && [...supports,...access].every(point), "图纸需有2至12处可见支点及1至6个使用位");
  const segments=marks.flatMap((mark,i)=>mark.points.slice(1).map((b,j)=>({a:mark.points[j],b,i})));
  const xs=marks.flatMap(mark=>mark.points.map(p=>p[0]));
  const left=Math.min(...xs), right=Math.max(...xs);
  const footing=supports.map(p=>Math.min(...segments.map(s=>segmentDistance(p,s.a,s.b))));
  for (let i=0;i<supports.length;i++) {
    const p=supports[i];
    const nearest=segments.reduce((best,s)=>segmentDistance(p,s.a,s.b)<segmentDistance(p,best.a,best.b)?s:best);
    need(Math.abs(p[1])<=.25 && footing[i]<=.085,
      `支点必须落地。第${i+1}处 ${JSON.stringify(p)} 最近的「${marks[nearest.i].layer}」相距${footing[i].toFixed(2)}米。将该墙脚或柱脚本身画到 [${p[0]},0]，或改选一处已有的 y=0 真实柱脚，只报它的x。`);
    need(supports.slice(0,i).every(other=>distance(p,other)>.015),"同一柱脚只报一次");
  }
  const headroom = access.map(p => {
    if(!(Math.abs(p[1])<=.25 && p[0]>=left-.85 && p[0]<=right+.85 && supports.every(q=>distance(p,q)>.23))){
      const error=new RangeError("使用位应在门前或柜边的地面，与承重柱脚错开");error.name="BuildingStationError";throw error;
    }
    const overhead=[];
    for (const {a,b,i} of segments) {
      if (Math.abs(a[0]-b[0])<.06 || p[0]<Math.min(a[0],b[0]) || p[0]>Math.max(a[0],b[0])) continue;
      const height=a[1]+(b[1]-a[1])*(p[0]-a[0])/(b[0]-a[0])-p[1];
      if (height>=.95) overhead.push({stroke:i,layer:marks[i].layer,height});
    }
    return {at:p,overhead};
  });
  return { footing_distances:footing, access_overhead:headroom };
}

function shapeSignature(marks) {
  // Relative to the page's lowest x and y, independent of mark order, brush,
  // title and layer. A translated facsimile cannot authorize a new design.
  const pts=marks.flatMap(mark=>mark.points), minX=Math.min(...pts.map(p=>p[0])), minY=Math.min(...pts.map(p=>p[1]));
  return digest(marks.map(mark=> {
    const forward=mark.points.map(p=>[Math.round((p[0]-minX)*1000),Math.round((p[1]-minY)*1000)]);
    const a=JSON.stringify(forward), b=JSON.stringify(forward.reverse()); return a<b?a:b;
  }).sort());
}
function pageHash(page) {
  // Godot stores Vector2 components as float32. Quantize in millimetres so a
  // cold-read page and its source have the same durable local design digest.
  const mm=p=>p.map(value=>Math.round(value*1000));
  return digest({style:page.style,marks:page.marks.map(m=>({...m,points:m.points.map(mm)})),
    supports:page.supports.map(mm),access:page.access.map(mm)});
}

export function compileBuilding(args, building, variant, workProgram) {
  need(point(building?.origin), "建筑图纸缺少本轮的落脚原点");
  const origin=building.origin;
  let marks, style, parent=null, edits=null;
  if (variant) {
    parent=parentPage(building.parent);
    exactly(args,["name","replace","remove","add","supports","access"]);
    need([args.replace,args.remove,args.add].every(v=>Array.isArray(v) && v.length<=36),"改稿须列出替换、删除与追加的笔画");
    const changed=new Map();
    for (const index of args.remove) {
      need(!changed.has(index),"同一母图笔画只可改动一次");
      changed.set(index,null);
    }
    for (const update of args.replace) {
      exactly(update,["index","mark"]);
      need(!changed.has(update.index),"同一母图笔画只可改动一次");
      changed.set(update.index,readMark(update.mark));
    }
    need([...changed.keys()].every(i=>Number.isInteger(i)&&i>=0&&i<parent.marks.length),"找不到母图笔画编号");
    const added=args.add.map(m=>readMark(m));
    marks=parent.marks.flatMap((m,i)=>changed.has(i)?[changed.get(i)].filter(Boolean):[m]).concat(added);
    need(marks.length>0 && marks.length<=128,"另存图纸的笔画总数须为1至128");
    need(shapeSignature(marks)!==shapeSignature(parent.marks),"另存应真实改变构件点列或轮廓；仅改色、改名、排序或整体平移不构成当地变体");
    edits={replaced:args.replace.map(v=>v.index),removed:args.remove,added:added.length};
    style=parent.style;
  } else {
    exactly(args,["name","style","marks","supports","access"]);
    need(Array.isArray(args.marks)&&args.marks.length>=3&&args.marks.length<=48&&styles.includes(args.style),"母图须包含3至48笔公共景物笔迹和有效墨色");
    marks=args.marks.map(m=>readMark(m)); style=args.style;
  }
  const name=nameOf(args.name), access=args.access;
  let supports=args.supports;
  if(workProgram?.adjustment){
    const revision=repositionBay(marks,supports,workProgram.adjustment.site,workProgram.adjustment.edit);
    marks=revision.marks.map(({source,...m})=>source ? {...readGeometry(m,true),source} : readGeometry(m,true));
    supports=revision.supports;
  }
  if(workProgram?.capture)workProgram.capture(marks);
  need(marks.reduce((count,m)=>count+m.points.length,0)<=8192,"整张图纸最多8192个实际采样点，请减少细节");
  const metrics=inspectLayout(marks,supports,access);
  const layout={supports,access,layers:marks.map(m=>m.layer)};
  if(marks.some(m=>m.source)) layout.stroke_sources=marks.map(m=>m.source??null);
  if(workProgram) {
    let checked;
    try{checked=verifyStations(workProgram.stations,marks,supports,workProgram.shelter_required,workProgram.program);}
    catch(error){if(error instanceof RangeError)error.name="BuildingStationError";throw error;}
    layout.stations=checked.map(({x,use,cover,roof_layers,fixture_layers,workers})=>({x,use,cover,roof_layers,fixture_layers,workers}));
    metrics.station_checks=checked;
  }
  const command={tool:"draw_scenery",name,style,strokes:marks.map(m=>m.points.map(p=>[origin[0]+p[0],origin[1]+p[1]])),
    brushes:marks.map(m=>m.brush),pigments:marks.map(m=>m.pigment)};
  return {args:{name,parent_id:parent?.id??-1,origin,command,layout},receipt:{version:"building-plan-v1",mode:variant?"variant":"design",
    local_sha256:pageHash({marks,style,supports,access}),geometry_sha256:shapeSignature(marks),parent_id:parent?.id??-1,
    parent_sha256:parent?pageHash(parent):null,stroke_count:marks.length,edits,...metrics}};
}

// Offer only local furniture revisions already checked against the entire
// drawing. The model chooses a physical Edit, and the exact same page is
// submitted. A roof or unrelated original stroke cannot become an edit.
async function reviseWorkBay(stations,marks,supports,program,compile,error,stream,reply,art){
  const options=[];
  for(const site of bayOptions(stations,marks,supports,program)){
    const {indices:related,links}=workBayAttachments(marks,site,stations,supports);
    const layers=related.map(i=>marks[i].layer);
    if(layers.length>36||new Set(layers).size!==layers.length)continue;
    for(const side of ["left","right"]){
      for(const width_ratio of [1,.82,.64,.48,.35]){
        const edit={target_id:site.id,layers,side,width_ratio};
        const station={...stations[site.index],x:site.x};
        const selection=stations.filter((_,i)=>i!==site.index);
        const adjustment={site,edit};
        let page;
        try{
          // Keep the required work bay first and retain other working bays
          // whenever they survive the local revision.
          page=compile([station,...selection],adjustment);
        }catch(e){
          if(!(e instanceof RangeError))throw e;
          try{page=compile([station],adjustment);}
          catch(invalid){if(!(invalid instanceof RangeError))throw invalid;continue;}
        }
        const bent=page.args.command.strokes;
        const shift=Math.max(...related.map(i=>Math.abs(bent[i][0][0]-page.args.origin[0]-marks[i].points[0][0])));
        if(shift>3)continue;
        options.push({id:`e${options.length}`,site,edit,station,shift,page,links});
        break;
      }
    }
    if(options.length>=6)break;
  }
  if(!options.length)throw error;
  const offers=options.map(o=>({id:o.id,x:o.site.x,body:o.site.body,
    blockers:o.site.blockers.map(index=>({index,layer:marks[index].layer,points:marks[index].points})),
    edit:o.edit,shift:o.shift,attachment_links:o.links,kept_stations:o.page.args.layout.stations.map(s=>s.use)}));
  const tool={name:"revise_work_bay",description:"亲自选择一项已经过全图净空复核的家具局部改法，保存房屋屋面与其他原笔。",
    parameters:obj({id:enumOf(offers.map(o=>o.id))})};
  const designTrace=reply.model_trace;
  const entry={reason:error.message,design_call_id:reply.raw_tool_call.id,original_stations:stations,options:offers};
  (reply.station_adjustments??=[]).push(entry);
  try{
    const tip=`你是阿靛。这次建筑仍是刚才的委托。屋面、构图及无关笔保持原样。原稿受阻：${error.message}。本次实际笔法：\n${art}\n下列是经核验的局部改法：选站位，柜及指定相连货物一起平移/缩窄。优先功能可达和少改。用途 ${JSON.stringify(program)}。候选 ${JSON.stringify(offers)}。直接调用 revise_work_bay，参数只写 {"id":"某个候选编号"}。`;
    let args;
    for(let attempt=1;attempt<=2;attempt++){
      try{
        const {calls:[pick]}=await stream(tip,[tool],1050);
        need(pick?.name===tool.name&&pick.id,"请使用局部改柜工具");
        args=parseArguments(pick);
        exactly(args,["id"]);
        if(!options.some(o=>o.id===args.id))throw new RangeError("局部改法编号已失效");
        entry.tool_call={id:pick.id,name:pick.name,arguments:args};
        break;
      }catch(e){
        if(!(e instanceof RangeError||e instanceof SyntaxError||e.message==="invalid-command"))throw e;
        (entry.invalid_choices??=[]).push({attempt,reason:e.message,model_trace:reply.model_trace});
        if(attempt===2)throw e;
      }
    }
    const selected=options.find(o=>o.id===args.id);
    need(selected,"局部改法编号已经失效");
    entry.applied=offers.find(o=>o.id===args.id);
    selected.page.receipt.local_revision=entry.applied;
    return selected.page;
  }finally{entry.model_trace=reply.model_trace??null;reply.model_trace=designTrace;}
}

async function finishStations(drawing,supports,stations,building,variant,program,stream,reply,art){
  let marks;
  const compile=(selection,adjustment)=>compileBuilding({...drawing,supports,access:selection.map(s=>[s.x,0])},building,variant,
    {stations:selection,shelter_required:program.shelter_required,program,adjustment,capture:value=>{if(!adjustment)marks=value;}});
  try{return compile(stations);}
  catch(error){
    if(error.name!=="BuildingStationError" || !marks)throw error;
    const options=alternatives(stations,marks,supports,program);
    if(!options.length || program.shelter_required&&!options.some(o=>o.cover==="sheltered"&&o.use===program.use)){
      return await reviseWorkBay(stations,marks,supports,program,compile,error,stream,reply,art);
    }
    const tool={name:"choose_work_stations",description:"从这份实画中检查通过的位置亲自选择施工使用位，保留母稿的原有笔画。",
      parameters:obj({ids:list(enumOf(options.map(o=>o.id)),1,6,"至少保留委托所需用途的一处，同一原始站位最多选一个")})};
    const designTrace=reply.model_trace;
    const entry={reason:error.message,design_call_id:reply.raw_tool_call.id,original_stations:stations,options};
    (reply.station_adjustments??=[]).push(entry);
    try{
      const {calls:[pick]}=await stream(`你是阿靛。当前建筑笔画保持不动。刚才提出的站位未通过施工检查：${error.message}。下列坐标经本稿真实屋面覆盖、整人净高和柱柜净空校验。根据使用者目的选择合适位置，编号按偏好排列；同一原站位只采用你排在最前面的合法编号。可省略额外的非必需站位。必须保留委托需要的受遮蔽用途。只提交一份编号列表。笔法参照：\n${art}\n用途 ${JSON.stringify(program)}。候选 ${JSON.stringify(options)}`,[tool],350);
      need(pick?.name===tool.name&&pick.id,"请使用原稿复选工具");
      const args=parseArguments(pick);
      entry.tool_call={id:pick.id,name:pick.name,arguments:args};
      exactly(args,["ids"]);
      need(Array.isArray(args.ids)&&args.ids.length>=1&&args.ids.length<=6,"工作位复选数量无效");
      const picks=args.ids.map(id=>options.find(o=>o.id===id));
      need(picks.every(Boolean),"复选只能选择本轮候选");
      const chosen=picks.filter((item,i)=>picks.findIndex(first=>first.index===item.index)===i);
      need(!program.shelter_required||chosen.some(o=>o.cover==="sheltered"&&o.use===program.use),"复选需要保留委托的有顶工作位");
      return compile(chosen.map(o=>({...stations[o.index],x:o.x})));
    }finally{entry.model_trace=reply.model_trace??null;reply.model_trace=designTrace;}
  }
}

async function fixVariantReferences(draft,parent,stream,reply,art){
  if(!Array.isArray(draft.replace)||!Array.isArray(draft.remove))return draft;
  const allowed=Array.from({length:parent.marks.length},(_,i)=>i);
  const seen=new Set();
  const pending=[];
  const replace=[];
  for(const item of draft.replace){
    need(item && typeof item==="object","变体中的每项替换都需要母图编号和新笔画");
    if(allowed.includes(item.index)&&!seen.has(item.index)){seen.add(item.index);replace.push(item);}
    else pending.push(item);
  }
  const remove=[];
  const unknown=[];
  for(const index of draft.remove){
    if(allowed.includes(index)&&!seen.has(index)){seen.add(index);remove.push(index);}
    else unknown.push(index);
  }
  if(!pending.length&&!unknown.length)return draft;
  const free=allowed.filter(i=>!seen.has(i));
  const target=indexEnum([-1,...free]);
  const tool={name:"correct_mother_page_references",description:"只修这份变体引用错的母图索引，保留合法改稿。-1 表示撤销本条。",
    parameters:obj({replace:list(target,0,pending.length,"按错误替换的原顺序，每项填原始母图索引或-1"),
      remove:list(indexEnum(free.length?free:[-1]),0,36,"要删除的其余真实母图索引；无目标留空")})};
  const draftTrace=reply.model_trace;
  const correction={source:reply.raw_tool_call.id,out_of_range:unknown,unbound_replacements:pending};
  (reply.index_repairs??=[]).push(correction);
  try{
    const {calls:[call]}=await stream(`原始母图对应 0 至 ${allowed.length-1}，新追加笔不会增加母图索引。上稿中的无效删除 ${JSON.stringify(unknown)}，无效替换 ${JSON.stringify(pending.map(p=>({index:p.index,layer:p.mark?.layer})))}。合法项已保留。对无效替换逐项选可用索引或 -1；不存在的删除没有对应对象时留空。不要重画。母图索引与层 ${JSON.stringify(free.map(index=>({index,layer:parent.marks[index].layer})))}。本次笔法：\n${art}`,[tool],850);
    need(call?.name===tool.name&&call.id,"没有收到母图索引修正");
    const args=parseArguments(call);
    correction.tool_call={id:call.id,name:call.name,arguments:args};
    exactly(args,["replace","remove"]);
    need(Array.isArray(args.replace)&&args.replace.length===pending.length&&Array.isArray(args.remove),"母图引用修正缺少对应项");
    const replacement=args.replace.map(strokeIndex), removal=args.remove.map(strokeIndex);
    const selected=[...replacement.filter(i=>i!==-1),...removal];
    need(selected.every(i=>free.includes(i))&&new Set(selected).size===selected.length,"修正的每个母图编号必须存在且只使用一次");
    pending.forEach((item,i)=>{if(replacement[i]!==-1)replace.push({...item,index:replacement[i]});});
    return {...draft,replace,remove:[...remove,...removal]};
  }finally{correction.model_trace=reply.model_trace??null;reply.model_trace=draftTrace;}
}

async function trimBuildingPage(draft,supports,stations,stream,reply,art) {
  const maxMarks=48;
  if(!Array.isArray(draft.marks)||draft.marks.length<=maxMarks)return draft;
  const markCount=draft.marks.length;
  need(markCount<=128,"原稿超过128笔，请先按功能构件重画成最多48笔");
  const references=new Set(stations.flatMap(s=>[s?.roof_layers,s?.fixture_layers].filter(Array.isArray).flat()));
  const mustKeep=new Set();
  const geometry=draft.marks.map(m=>m&&Object.hasOwn(m,"study")?readMark(m):expandCurveMark(m));
  const marks=geometry.map((m,index)=>{
    need(m&&Array.isArray(m.points)&&m.points.length>=2&&m.points.length<=(m.source?8192:32)&&m.points.every(point),"缩减原稿前需有可识别的笔迹");
    const x=m.points.map(p=>p[0]), y=m.points.map(p=>p[1]);
    if(references.has(m.layer))mustKeep.add(index);
    return {index,layer:m.layer,brush:m.brush,pigment:m.pigment,box:[Math.min(...x),Math.min(...y),Math.max(...x),Math.max(...y)]};
  });
  for(const x of supports){
    const anchored=marks.filter(({index})=>geometry[index].points.some(p=>distance(p,[x,0])<=.085));
    anchored.sort((a,b)=>(b.box[3]-b.box[1])-(a.box[3]-a.box[1]));
    if(anchored.length)mustKeep.add(anchored[0].index);
  }
  const disposable=marks.filter(m=>!mustKeep.has(m.index)).map(m=>m.index);
  need(mustKeep.size<=maxMarks,"申报的柱脚、屋面和使用设施本身超过48笔，请合并同一构件");
  const required=markCount-maxMarks;
  const allowed=new Set(disposable), removed=new Set();
  const entry={source:reply.raw_tool_call.id,before:markCount,protected:[...mustKeep],attempts:[]};
  (reply.mark_budget_repairs??=[]).push(entry);
  const designTrace=reply.model_trace;
  try{
    for(let attempt=1;attempt<=2&&removed.size<required;attempt++){
      const rest=disposable.filter(i=>!removed.has(i));
      const needCount=required-removed.size;
      const tool={name:"trim_building_marks",description:"只从原稿删冗余笔，保留原形与剩余笔序，使整页不超过48笔。",
        parameters:obj({drop:list(indexEnum(rest),needCount,needCount,"按删除优先顺序填写原稿实际笔号，不重复。")})};
      const trace={need:needCount};
      entry.attempts.push(trace);
      try{
        const correction=removed.size?`已有 ${removed.size} 个可删编号，不要重复；只需在余下的可删项补足 ${needCount} 项。`:"";
        const {calls:[call]}=await stream(`沿用刚才的图，只选要删的原稿实际编号。最多48笔；这次至少删${needCount}笔，按优先级给编号。已采纳 ${JSON.stringify([...removed])}。必留编号 ${JSON.stringify(entry.protected)}，绝不删。保留可辨识的门棚、柜面和成组主要货物，让果形与梗相连。优先省掉重复描边、大面积重复淡墨和装饰。每笔包围盒为左/下/右/上，原笔层 ${JSON.stringify(marks)}。${correction}直接调用 trim_building_marks。当前笔法：\n${art}`,[tool],1600);
        need(call?.name===tool.name&&call.id,"未收到原稿删笔编号");
        const args=parseArguments(call);
        trace.tool_call={id:call.id,name:call.name,arguments:args};
        entry.tool_call=trace.tool_call;
        exactly(args,["drop"]);
        need(Array.isArray(args.drop),"删笔工具需要编号列表");
        trace.ignored=[];
        for(const value of args.drop){
          if(removed.size===required)break;
          const index=strokeIndex(value);
          if(allowed.has(index))removed.add(index);
          else trace.ignored.push(value);
        }
      }catch(error){
        if(!(error instanceof RangeError||error instanceof SyntaxError||error.message==="invalid-command"))throw error;
        trace.reason=error.message;
      }finally{trace.model_trace=reply.model_trace??null;}
    }
    need(removed.size===required,"可用删笔编号不足，仍需删"+(required-removed.size)+"笔");
    const result=draft.marks.filter((_,i)=>!removed.has(i));
    entry.dropped=[...removed];
    entry.after=result.length;
    return {...draft,marks:result};
  }finally{entry.model_trace=reply.model_trace??null;reply.model_trace=designTrace;}
}

async function repairWashMarks(draft,variant,stream,reply,art){
  if(variant&&(!Array.isArray(draft.replace)||!Array.isArray(draft.add)))return draft;
  const marks=variant?[...draft.replace.map(row=>row?.mark),...draft.add]:draft.marks;
  if(!Array.isArray(marks))return draft;
  const invalid=[];
  for(const [index,ink] of marks.entries()){
    if(!washes.includes(ink?.brush))continue;
    try{readMark(ink);}
    catch(error){
      if(!(error instanceof RangeError))throw error;
      if(/淡墨|铺色/.test(error.message))invalid.push({index,ink,reason:error.message});
    }
  }
  if(!invalid.length)return draft;
  const tool={name:"repair_wash_marks",description:"只修指出的淡墨轮廓，保留原有构件名称和所有其余笔画。",
    parameters:obj({marks:list(obj({index:indexEnum(invalid.map(row=>row.index)),brush:enumOf(brushes),
      points:list(pair,2,32,"沿同一构件修闭合边界；若原意是细线或浓线可选择对应笔刷")}),invalid.length,invalid.length)})};
  const draftTrace=reply.model_trace;
  const entry={source:reply.raw_tool_call.id,invalid};
  (reply.wash_repairs??=[]).push(entry);
  try{
    const {calls:[call]}=await stream(`仍是同一次建筑委托。只修出错的几笔，保留这些笔画的原构件用法与其余图纸。逐条实际问题 ${JSON.stringify(invalid)}。本次笔法：\n${art}`,[tool],1800);
    need(call?.name===tool.name&&call.id,"淡墨修稿没有返回有效工具");
    const args=parseArguments(call);
    entry.tool_call={id:call.id,name:call.name,arguments:args};
    exactly(args,["marks"]);
    need(Array.isArray(args.marks)&&args.marks.length===invalid.length,"淡墨修稿的笔数不符");
    const revised=[...marks], seen=new Set();
    for(const row of args.marks){
      exactly(row,["index","brush","points"]);
      const index=strokeIndex(row.index);
      need(invalid.some(entry=>entry.index===index)&&!seen.has(index),"只能修改报告指出的淡墨笔");
      seen.add(index);
      revised[index]=readMark({...expandCurveMark(marks[index]),brush:row.brush,points:row.points});
    }
    if(!variant)return {...draft,marks:revised};
    return {...draft,replace:draft.replace.map((row,i)=>({...row,mark:revised[i]})),add:revised.slice(draft.replace.length)};
  }finally{entry.model_trace=reply.model_trace??null;reply.model_trace=draftTrace;}
}

export async function decideBuilding(observation, stream, reply) {
  const variant=observation.invitation.kind==="building_variant", building=observation.building;
  need(point(building?.origin),"建筑图纸需要地图提供底部原点");
  const parent=variant?parentPage(building.parent):null;
  const tradeSite=observation.scene_project?.trade===true && observation.scene_project?.current?.kind==="building";
  const tools=[structuredClone(variant?variantTool(parent.marks.length):baseTool)];
  tools[0].parameters.properties.counter_offer=tradeSchema;
  if(tradeSite){
    tools[0]=structuredClone(tools[0]);
    tools[0].parameters.properties.visitor_use={...label,
      description:"逐字抄 stations 中确供来客站立、交货付款的 use。若柜后还有摊主，摊主请另标服务者；不会注册成玩家交易点。"};
  }
  const path="tools/skills/paper-landscape/SKILL.md";
  const file=await readFile(new URL("./skills/paper-landscape/SKILL.md",import.meta.url));
  const section=file.toString("utf8").match(/^## 建筑笔法\s*\n([\s\S]*?)(?=^## |(?![\s\S]))/m)?.[1]?.trim();
  need(section&&section.includes("建筑技法版本"),"找不到当前建筑笔法版本");
  reply.building_skill={path,section:"建筑笔法",version:section.match(/建筑技法版本\s+([\d.]+)/)?.[1]??null,
    sha256:createHash("sha256").update(file).digest("hex"),section_sha256:createHash("sha256").update(section).digest("hex")};
  // This is a movable master sheet. Site terrain and world translation belong
  // to placement/preview and must never tilt or raise the drafting baseline.
  const site=building.site??{};
  const scene={reference_pages:buildingStudyCatalogue(),commission:observation.invitation.text,medium:{brushes:site.brushes??brushes,pigments:site.pigments??pigments},
    place_label:typeof site.label==="string"?site.label:"",counter_context:site.counter_context??null,parent:parent?{
    id:parent.id,name:parent.name,style:parent.style,supports:parent.supports,access:parent.access,
    stations:parent.stations,marks:parent.marks.map((m,index)=>({index,...m}))}:null};
  const relations=observation.scene_project?.frame_measurements?.spatial_relations;
  if(relations)scene.project_spatial_relations=relations;
  if(Array.isArray(site.supports)) {
    scene.actual_site={origin:building.origin,surfaces:site.supports,foundation:site.foundation??null,shore:site.shore??null,
      notes:"横纵皆是相对实际落地原点的米。柱脚和办理用途的脚面要落到列出的同一实体层。如已选 foundation，从这处真实平地设计紧凑稿，把来客使用位设在小纸 x=0 并让整幅墨线和所有柱脚落进实测岸肩总宽，棚外也不要伸出导致冲突。地表有缺口时在实面选站位，保留建筑主体。"};
  }
  const prior=building.previous_draft;
  if(prior?.tool===tools[0].name&&prior.args&&typeof prior.args==="object"&&typeof prior.reason==="string"){
    const text=JSON.stringify(prior.args);
    if(Buffer.byteLength(text)<=95000)scene.previous_draft={reason:prior.reason.slice(0,300),tool:prior.tool,args:prior.args};
  }
  const programTool={name:"read_building_use",description:"读懂委托里的使用条件，以供收稿时核对。",parameters:obj({
    shelter_required:{type:"boolean",description:"本次委托或需继承的母图用途是否要求人物在覆盖物下办理至少一项工作"},
    workers:{type:"integer",enum:[1,2],description:"只有委托明确要求两个人在同一侧并排站，同时共享这个受遮蔽的地面区，才填2。有柜后摊主与柜前顾客时，柜前来客位仍填1。单人或人数未指定也填1。"},
    use:{...label,description:"若要求遮蔽，写出这项要遮雨或有顶的具体工作；否则概括实际用途"}
  })};
  const briefContext={commission:scene.commission,parent_name:parent?.name??null,parent_stations:parent?.stations??[]};
  function saleStation(result,offer,legacyUse) {
    assignTrade(result.args.layout.stations,offer,legacyUse,scene.commission,tradeSite,parent?.stations);
    const width=site.foundation?.frontage?.width_m;
    const counter=result.args.layout.stations.find(station=>station.service);
    if (!Number.isFinite(width) || !counter) return;
    const center=building.origin[0]+counter.x;
    const points=result.args.command.strokes.flat();
    const left=Math.min(...points.map(point=>point[0]))-center;
    const right=Math.max(...points.map(point=>point[0]))-center;
    need(right-left<=width+.02,
      `实测可用岸肩总宽 ${width.toFixed(2)} 米。当前从左檐到右檐宽 ${(right-left).toFixed(2)} 米。请缩小占地并保留原来客净空。柜位可以偏左或偏右，原生施工时再核每根柱和脚位。`);
  }
  const readBrief="你是阿靛。先读懂使用者要在哪里做什么。把工作功能填写到工具。只看自然语言和母图已存在的工作位。若要求人在檐、棚、屋顶或其他遮蔽物下面进行活动，就需要受遮蔽的使用位。露天工作可留在外头；仅要求装饰屋顶不必据此认定某个露天工作要遮蔽。改稿时保留仍在使用的母图功能。现场 "+JSON.stringify(briefContext);
  let reading,program;
  for(let attempt=1;attempt<=2;attempt++){
    try{
      const {calls:[call]}=await stream(readBrief+"。请立即调用 read_building_use，只填工具列出的参数。",[programTool],900);
      need(call?.name===programTool.name&&call.id,"未能读取本次建筑用途");
      const args=parseArguments(call);
      exactly(args,Object.hasOwn(args,"workers")?["shelter_required","use","workers"]:["shelter_required","use"]);
      need([1,2].includes(args.workers??1),"同时站位人数需要为1或2");
      need(typeof args.shelter_required==="boolean","用途回执缺少遮蔽要求");
      nameOf(args.use);
      reading=call;
      program=args;
      break;
    }catch(error){
      if (!(error instanceof RangeError || error instanceof SyntaxError || error.message==="invalid-command")) throw error;
      (reply.program_rejections??=[]).push({attempt,reason:error.message,model_trace:reply.model_trace??null});
      if(attempt===2)return {error:"阿靛未能读清这次建筑用途。可以保留原话继续委托。",execution_status:"rejected"};
    }
  }
  reply.building_program={tool_call:{id:reading.id,name:reading.name,arguments:program},model_trace:reply.model_trace??null};
  if(scene.previous_draft && typeof prior.call_id==="string" && prior.call_id){
    const original=prior.args;
    const {supports_x,stations:previousStations,access_x,visitor_use,counter_offer,...rawDrawing}=original;
    reply.prior_draft={tool_call:{id:prior.call_id,name:prior.tool,arguments:original},reason:prior.reason};
    reply.raw_tool_call=reply.prior_draft.tool_call;
    try{
      const drawing=mergeReferencePlacements(rawDrawing,variant);
      need(Array.isArray(supports_x)&&supports_x.every(Number.isFinite),"旧稿没有完整的可核验柱脚");
      let stations=previousStations;
      if(!Array.isArray(stations) && Array.isArray(access_x) && access_x.every(Number.isFinite)){
        const annotate={name:"identify_work_layers",description:"阅读你上一份未收存的建筑，给原位置标出真实遮蔽物与工作家具。",
          parameters:obj({stations:{...layoutFields.stations,minItems:access_x.length,maxItems:access_x.length}})};
        const {calls:[call]}=await stream(`你是阿靛。保留旧稿的所有笔画和原站位。只给指定旧站位标注真实屋面和交接家具。必需用途 use 写成 ${JSON.stringify(program.use)}，逐一引用旧稿已存在的层名称，不要增删站位。只填 ${access_x.length} 个，严格按这些横坐标的顺序 ${JSON.stringify(access_x)}。不要移位。委托 ${JSON.stringify(scene.commission)}；旧图和冲突原因 ${JSON.stringify(scene.previous_draft)}`,[annotate],800);
        need(call?.name===annotate.name&&call.id,"未取得旧图的构件标注");
        const args=parseArguments(call);
        exactly(args,["stations"]);
        need(Array.isArray(args.stations)&&args.stations.length===access_x.length,"只可给旧站位标构件");
        stations=args.stations.map((row,i)=>({...row,x:access_x[i]}));
        reply.prior_annotation={tool_call:{id:call.id,name:call.name,arguments:args},model_trace:reply.model_trace};
      }
      need(Array.isArray(stations)&&stations.length>0,"旧稿没有可读取的站位");
      // The current brief reading may paraphrase the exact same previously
      // protected activity. Keep all station geometry and identify its use by
      // the prior recorded program when available.
      const protectedUse=prior.use??stations.find(s=>s.cover==="sheltered")?.use;
      const revisionProgram={...program,use:protectedUse??program.use};
      const budgeted=variant?drawing:await trimBuildingPage(drawing,supports_x,stations,stream,reply,section);
      const clean=await repairWashMarks(budgeted,variant,stream,reply,section);
      const addressed=variant?await fixVariantReferences(clean,parent,stream,reply,section):clean;
      const repaired=await finishStations(addressed,supports_x.map(x=>[x,0]),stations,building,variant,revisionProgram,stream,reply,section);
      saleStation(repaired,counter_offer,visitor_use);
      const repairId=reply.station_adjustments?.at(-1)?.tool_call?.id??reply.prior_annotation?.tool_call?.id??reading.id;
      return {tool_call_id:repairId,command:{tool:prior.tool,args:repaired.args,call_id:repairId},
        building_receipt:repaired.receipt,execution_status:"pending_game_validation"};
    }catch(error){
      if(!(error instanceof RangeError||error instanceof SyntaxError||error.message==="invalid-command"))throw error;
      reply.prior_draft.repair_error=error.message;
    }
  }
  const prompt=`你是《纸间》的画家阿靛，现在独立设计一份可随身保管并在别处重新施工的建筑图纸。根据这一次委托和现场，决定建筑的形状、用途、比例、朝向、色彩和每笔真实点位；正面或轻侧面的剪影要清楚。只调用一次指定工具。
图纸以建筑底部的一个基准点为(0,0)，局部单位为米，x向右、y向上。人高约1.5米。${scene.actual_site?.foundation?.frontage ? `此处只验证了 ${scene.actual_site.foundation.frontage.width_m} 米总净宽。外檐、墙、柜与各柱的总宽不能超过该实测岸肩。柜位可偏一侧，保持肩线无阻，原生落图再次选址。` : "村中小建筑建议宽约4至6米、高约2至3.5米。"}无需画地面或旁边已有建筑。你可逐笔自由画，或从 reference_pages 自选几笔拼入同一母图；设计、用途和取舍由你决定。引用一笔填 layer、study、stroke（从0起）、origin（参考页零点放在哪个图纸坐标）、scale:[宽倍数,高倍数]、mirror_x、pigment（source 沿用原色）。同一组用相同变换让笔迹相接；各自取独立层名。bounds 是该原页左、下、右、上边界（米），groups 列原笔号范围。自由笔填写 layer、brush、pigment。折笔用 points；流畅弯笔可用 curve 自选椭圆弧或三次贝塞尔，沿用同一局部坐标。每取一笔占用一笔额度。不同构件要有相接的屋面厚度、梁、墙面或柱脚；如有附属空间，让人能从剪影读出它和主体的关系。把当地用途画到可辨认的设施和货物上，不靠写招牌描述代替轮廓。按主次浓淡分层，先薄洗后勾轮廓；可用小面积色彩与活动位置区分材料和货物。给人物留白，细笔装饰顺着构件而走。每笔的实际连线总长至少0.045米，小点改用一小道连续墨线；报给站位的盖檐与柜面名字逐字对应其最终唯一图层。建议约16到30笔，整张新母图最多48笔。为关键构件分配墨线和少量淡墨，装饰用剩余笔数。bold 浓线、fine 细线、wash 平薄洗、wash_pool 积色薄洗均为公共景物笔。要画墙或一层檐面透纸，可挑一笔 wash_pool，上薄下沿局部积色。靠边的主轮廓仍用清楚的实线，货与人物之间先留纸。若委托包含侧翼空间，自行安排它与主屋的比例和连接，避免雷同的方框。每种薄洗首尾点须相同，无自交，每笔只绕一个区域。不要用文字、符号或标签充当实物。
这张可复用母图画在水平桌上，地平线严格为局部 y=0。选两处以上结构支点，在墙脚、主屋柱或外棚柱的真实笔迹 points 中亲自画出 [x,0]，再把这些 x 抄入 supports_x。柜台的面、架板和家具腿不是房屋地基。不要把整张画托离底边。 
你读到的建筑功能为 ${JSON.stringify(program)}。先放客位，再画屋柱、柜台和檐。单来客优先把客位设在局部 x=0，按 x±0.40 的完整站立带留空；柜或货放站立带外，棚顶仍跨过这段。若同一张图还有柜后摊主，另写其用途，不与客位共坐标。先在建筑草图里给每项工作预留净高1.50米的空间，单人净宽0.80米，若本次明确两人并排工作则给该项留净宽1.46米，再围绕这块空白安排柜、架、柱与覆盖物；人可以在柜台一侧伸手接物。申报 stations，给每处写 use、中心 x、sheltered/open。若要求遮蔽，该项受保护用途填作 use="${program.use}"，roof_layers 引用确切且唯一的棚面/屋面笔层名。预留完整的横向站位带，单人 x±0.40、两人 x±0.73，都要在真实棚面下；不要把檐外站位、头顶招牌、果篮、柜面或远景当成屋面。fixture_layers 引用实际用于交接的柜面或架板层，净空内不能穿过柜板、货箱或立柱。露天位留空屋面列表。请用有意义且唯一的图层名方便复核。位置、构件外观及伸出的方向由你设计。 
${variant?"你看到的是自己那张编号母图的完整逐笔原稿。依照新的实际用途做另存改稿：保留可沿用的笔画，用replace/remove/add改动真正需要变动的结构与轮廓，检查改变的屋顶、柜台、柱脚和使用位置彼此对得上。保留部分细节让两张图看得出同源。各索引均为母图原始编号，先决定所有改动，再返回完整的支点与使用位。":"这次从空纸立项。"}\n现场 ${JSON.stringify(scene)}`;
  let correction="\n本次调用实际采用的建筑笔法：\n"+section;
  correction+="\n当你想取一组原笔，可在 reference_marks 中只填一次 {study,strokes:[原笔号,…],layer:组名,origin:[x,y],before:序号}，或把 strokes 换为 part:该页 parts 的部件名或 groups 的层名。scale、mirror_x、pigment 省略时是[1,1]、false、source。组内保持原笔顺，每一层名为 组名·原层名#原笔号，屋面/柜面可用这个全名报站位。before 指原手绘 marks（另存图用 add）的序号，同位的组、单笔按 reference_marks 顺序。引用展开后这里共最多32笔。可混用手绘、单笔和组笔，也可完全手画。";
  correction+="\n能买卖的店铺请填 counter_offer，visitor_use 逐字引用来客站位。按来客原话区分收货与售货，给出实际商品与单价。柜里只卖有库存的货，买入的货来自客人背包。不能经营的货请说明；装饰或非经营建筑省略报价。counter_context 给出双方的实钱和材料。作者余墨充足时可从真墨备一盏纸灯；收货柜需实际准备钱匣，玩家可以自愿存入自己的一金。请勿描述未发生的交易。";
  if(typeof observation.scene_skill==="string")correction+="\n本次也是已立项的场景工序。\n"+observation.scene_skill;
  if(scene.previous_draft)correction+="\n你正在继续同一个委托。previous_draft 是你上次被拒的相对原稿。先按 reason 修复局部构件/站位并保留能沿用的笔画，再补齐当前工具协议。";
  const skillAndHistory=correction;
  for (let attempt=1;attempt<=2;attempt++) {
    reply.draft_count=attempt;
    delete reply.raw_tool_call;
    try {
      const {calls:[call]}=await stream(prompt+correction,tools,8500);
      need(call?.name===tools[0].name && typeof call.id==="string" && call.id.length>0,"需调用本轮提供的建筑设计工具");
      reply.raw_tool_call={id:call.id,name:call.name,arguments:call.arguments};
      const args=parseArguments(call);
      reply.raw_tool_call.arguments=args;
      const {supports_x,stations,visitor_use,counter_offer,...rawDrawing}=args;
      const draft=mergeReferencePlacements(rawDrawing,variant);
      need(Array.isArray(supports_x)&&supports_x.every(Number.isFinite)&&Array.isArray(stations)&&stations.every(s=>Number.isFinite(s?.x))&&
        !Object.hasOwn(draft,"supports")&&!Object.hasOwn(draft,"access"),"支点请填 supports_x；每个工作位单列 stations，须有横坐标和遮蔽说明");
      need(!program.shelter_required||stations.some(s=>s.cover==="sheltered"&&s.use===program.use),
        "受遮蔽的实际工作位 use 请逐字填写「"+program.use+"」，并引用真正的遮雨屋面");
      const budgeted=variant?draft:await trimBuildingPage(draft,supports_x,stations,stream,reply,section);
      const clean=await repairWashMarks(budgeted,variant,stream,reply,section);
      const drawing=variant?await fixVariantReferences(clean,parent,stream,reply,section):clean;
      const result=await finishStations(drawing,supports_x.map(x=>[x,0]),stations,building,variant,program,stream,reply,section);
      saleStation(result,counter_offer,visitor_use);
      need(Buffer.byteLength(JSON.stringify(result.args))+Buffer.byteLength(JSON.stringify(result.receipt))<30500,
        "建筑笔稿超过游戏本轮回执容量，请合并同层重复细节、精简冗余坐标");
      return {tool_call_id:call.id,command:{tool:call.name,args:result.args,call_id:call.id},
        building_receipt:result.receipt,execution_status:"pending_game_validation"};
    } catch (error) {
      if (!(error instanceof RangeError || error instanceof SyntaxError || error.message==="invalid-command")) throw error;
      const reason=error instanceof RangeError?error.message:"请提交一次完整的规范 JSON 工具调用";
      (reply.rejected_drafts??=[]).push({attempt,reason,model_trace:reply.model_trace??null,tool_call:reply.raw_tool_call??null});
      if (attempt===2) return {error:"阿靛的建筑图纸尚未通过校验："+reason,execution_status:"rejected"};
      correction=skillAndHistory+"\n游戏尚未收存上稿："+reason+"。修正局部问题后重新提交一次。上稿："+JSON.stringify(reply.raw_tool_call?.arguments??null);
    }
  }
}
