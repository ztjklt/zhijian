import {readFileSync} from "node:fs";
import {createHash} from "node:crypto";

const path="tools/skills/priest-life/references/wet-bank.json";
const data=readFileSync(new URL("./skills/priest-life/references/wet-bank.json",import.meta.url));
const page=JSON.parse(data);
const hash=createHash("sha256").update(data).digest("hex");
const round=value=>Number(value.toFixed(4));
const shapes=new Map(page.forms.map(form=>{
  const outline=form.outline_px.map(([x,y])=>[
    round((form.pivot_px[0]-x)/form.pixels_per_m),round((form.pivot_px[1]-y)/form.pixels_per_m)
  ]);
  return [form.id,{id:form.id,name:form.name,pigment:form.pigment,outline,note:form.note}];
}));

export const markPath="tools/skills/priest-life/references/wet-bank-marks.json";
const markBytes=readFileSync(new URL("./skills/priest-life/references/wet-bank-marks.json",import.meta.url));
export const markHash=createHash("sha256").update(markBytes).digest("hex");
const extracted=JSON.parse(markBytes);
if(extracted.source.sha256!==page.source_sha256)throw Error("湿岸细笔与轮廓来源不一致。");
const inkLibrary=new Map(extracted.marks.map(row=>{
  const [left,top,right,bottom]=row.source.host_box_px;
  const source="wet-bank/"+row.id;
  const points=row.source.vertices_px.map(([x,y])=>[round((right-x)/(right-left)),round((bottom-y)/(bottom-top))]);
  return [row.id,{id:row.id,name:row.name,frame:row.source.frame,brush:row.brush,pigment:row.color,points,source}];
}));

function attachMarks(part) {
  if(!part || part.mark_refs===undefined)return part;
  const {mark_refs:refs,...base}=part;
  if(!Array.isArray(refs) || refs.length>8 || new Set(refs).size!==refs.length || !Array.isArray(base.marks??[]))throw Error("mark_refs 需为不同的取形原笔编号，marks 需为数组。");
  const chosen=refs.map(id=>{
    const sample=inkLibrary.get(id);
    if(!sample)throw Error("取形页没有原笔 "+String(id)+"，可选 read_art_reference 查询。");
    const {brush,pigment,points,source}=sample;
    return {brush,pigment,points:points.map(p=>[...p]),source};
  });
  return {...base,marks:[...(base.marks??[]),...chosen]};
}
const waderPath="tools/skills/priest-life/references/wader.json";
const waderBytes=readFileSync(new URL("./skills/priest-life/references/wader.json",import.meta.url));
const waderPage=JSON.parse(waderBytes);
const waderHash=createHash("sha256").update(waderBytes).digest("hex");
const metres=value=>Number(value.toFixed(5));
const waderParts=new Map(waderPage.forms.map(form=>{
  const [px,py]=form.pivot_px;
  const local=([x,y])=>[metres((x-px)/waderPage.pixels_per_metre),metres((py-y)/waderPage.pixels_per_metre)];
  const outline=form.original_anchors_px.map(local);
  const edge_bends=Object.entries(form.original_controls_px).map(([edge,point])=>({edge:Number(edge),control:local(point)}));
  return [form.id,{...form,outline,edge_bends}];
}));
export const waderIDs=[...waderParts.keys()];
export const studyIDs=[...shapes.keys(),...waderIDs];
export function waderStudy(partID) {
  if(partID!==undefined && !waderParts.has(partID))throw Error("请选择涉禽页上的一个 study 编号。");
  const parts=partID===undefined?[...waderParts.values()]:[waderParts.get(partID)];
  return {study:waderPage.id,title:waderPage.title,path:waderPath,sha256:waderHash,
    source:waderPage.source,source_sha256:waderPage.source_sha256,source_kind:waderPage.source_kind,
    trace_source:waderPage.trace_source,trace_sha256:waderPage.trace_sha256,source_size_px:waderPage.source_size_px,
    pixels_per_metre:waderPage.pixels_per_metre,
    coordinates:"像素原点在原图左上。outline 与 edge_bends.control 用原件枢轴起算的米，+x 朝头、+y 向上。edge 从 0 数到下一锚点，末边回第 0 点。study_scale 同时缩放锚点与控制点。只借外形即可，自选父件、joint、相位与颜料。另画 outline 时自行指定弯边；edge_bends:[] 全部留直。折翼与步足可取自不同原件，动作由真实图纸定义。",
    parts:structuredClone(parts)};
}
export const studyPath=path;
export const studyHash=hash;
export function wetBankStudy() {
  return {study:page.id,source:page.source,source_sha256:page.source_sha256,path,sha256:hash,
    mark_resource:{path:markPath,sha256:markHash},marks:[...inkLibrary.values()],mark_coordinates:"每笔按头、尾或躯干原裁区而非单笔外框归一化，已转换为游戏 +x朝头、+y朝上。可挑 mark_refs 中的 id，或用 marks 自画/重新布置 UV。",
    mount_examples:{unit:"米，以下组合在现场量过，可单独取用或改画，原始形状不带关节。",body:"mantle:[0,0]。近前腿在[0.335,0]，缩放[0.67,0.87]；后掌在[-0.27,-0.05]，缩放[0.79,0.84]。左右各自错相。",head:"upper_bill 挂在躯干[0.38,0.13]，缩放[0.91,0.85]。lower_bill 挂在上颌[0.017,-0.034]，缩放[0.92,0.66]。fruit_bite 可只给下口沿原件的 part_id 请引擎试量。",tail:"fan 挂在躯干[-0.45,0.035]，宽高可分别缩放；尾辐贴在扇根。",original:"自己决定体型、部件选用与自绘部位、比例、步态和颜料。每个组都可以改造。"},
    coordinates:"以原件枢轴为零点，+x 朝头、+y 朝上，单位米。选用时传 study 和可选 study_scale；自己给拓扑、joint、运动、颜色。自绘 outline 优先。",parts:[...shapes.values()]};
}
export function resolveStudy(part) {
  part=attachMarks(part);
  if(!part || !part.study) {
    if(part?.study_scale!==undefined)throw Error("使用 study_scale 需先指定取形原件。");
    return part;
  }
  const wader=waderParts.get(part.study);
  const sample=wader??shapes.get(part.study);
  if(!sample)throw Error("取形编号无效，可读 wet-bank 或 wader 查原件编号。");
  const scale=part.study_scale??[1,1];
  if(!Array.isArray(scale)||scale.length!==2||scale.some(v=>!Number.isFinite(v)||v<.20||v>2.5))throw Error("原件两轴缩放均为0.20–2.50。");
  if(wader) {
    // A filed sheet already has its explicit anchors and controls.
    if(part.outline!==undefined)return part;
    const scalePoint=([x,y])=>[metres(x*scale[0]),metres(y*scale[1])];
    const outline=wader.outline.map(scalePoint);
    const edge_bends=part.edge_bends===undefined
      ? wader.edge_bends.map(({edge,control})=>({edge,control:scalePoint(control)}))
      : part.edge_bends;
    return {...part,outline,edge_bends};
  }
  const outline=part.outline??sample.outline.map(([x,y])=>[round(x*scale[0]),round(y*scale[1])]);
  return {...part,outline};
}
