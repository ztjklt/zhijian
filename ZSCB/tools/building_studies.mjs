import { readFileSync } from "node:fs";

const assets = ["traced_market_parts.json", "mill_studies.json", "counter_goods_studies.json"].map(file =>
  new URL("../assets/medieval/ink/" + file, import.meta.url));
const colors = ["inherit", "ochre", "cinnabar", "indigo", "malachite"];
let pages;

function catalogue() {
  if (pages) return pages;
  const entries = assets.flatMap(asset => Object.values(JSON.parse(readFileSync(asset, "utf8"))));
  const ink = new URL("../assets/medieval/ink/", import.meta.url);
  const streetPages = JSON.parse(readFileSync(new URL("east_field_studies.json", ink), "utf8"));
  const namedParts = JSON.parse(readFileSync(new URL("study_parts.json", ink), "utf8"));
  for (const page of entries) if (namedParts[page.reference_id]) page.parts = namedParts[page.reference_id];
  for (const id of ["east_bothy", "east_hamlet", "east_stilt", "east_counter", "east_loft"]) {
    entries.push({...streetPages[id], parts:namedParts[id]});
  }
  pages = new Map(entries.map(page => [page.reference_id, page]));
  return pages;
}

// The page origin is retained across every stroke in a component, including
// negative coordinates. Mirroring is about that common origin, not a stroke tip.
export function buildingStudyCatalogue() {
  return [...catalogue().values()].map(page => {
    const bounds = [Infinity, Infinity, -Infinity, -Infinity];
    const groups = [];
    for (const [index, stroke] of page.strokes.entries()) {
      const group = groups.at(-1);
      if (group?.layer === stroke.layer) group.last = index;
      else groups.push({layer:stroke.layer, first:index, last:index});
      for (const [x, y] of stroke.points) {
        bounds[0] = Math.min(bounds[0], x);
        bounds[1] = Math.min(bounds[1], y);
        bounds[2] = Math.max(bounds[2], x);
        bounds[3] = Math.max(bounds[3], y);
      }
    }
    return {study:page.reference_id, name:page.name, bounds, groups, ...(page.parts ? {parts:page.parts} : {})};
  });
}

export function resolveBuildingStudy(input) {
  const fields = ["study", "stroke", "layer", "origin", "scale", "mirror_x", "pigment"];
  if (!input || Object.keys(input).length !== fields.length || fields.some(k => !Object.hasOwn(input, k)))
    throw new RangeError("取图一笔需要页号、原笔号、图层、相对原点、缩放、镜像和颜料");
  const page = catalogue().get(input.study);
  if (!page) throw new RangeError("所选建筑参考页不存在");
  if (!Number.isInteger(input.stroke) || input.stroke < 0 || input.stroke >= page.strokes.length)
    throw new RangeError("《" + page.name + "》原笔号须在 0 至 " + (page.strokes.length - 1) + " 之间");
  const pair = a => Array.isArray(a) && a.length === 2 && a.every(Number.isFinite);
  if (!pair(input.origin) || !pair(input.scale) || input.scale.some(n => n <= 0) || typeof input.mirror_x !== "boolean")
    throw new RangeError("取笔原点须是图纸内的米制坐标，两个缩放倍率须为正数");
  if (input.pigment !== "source" && !colors.includes(input.pigment))
    throw new RangeError("取笔可沿用 source 原色，或改用公共色板");
  const mark = page.strokes[input.stroke];
  const [ox, oy] = input.origin;
  const [sx, sy] = input.scale;
  return {
    layer:input.layer, brush:mark.brush,
    pigment:input.pigment === "source" ? mark.pigment : input.pigment,
    points:mark.points.map(([x,y]) => [ox + x * (input.mirror_x ? -sx : sx), oy + y * sy]),
    source:{source_work_id:page.reference_id, source_stroke:input.stroke}
  };
}

// Expand a single component at the page origin. The emitted objects use the
// ordinary single-stroke contract, including its later colour and geometry checks.
export function expandBuildingStudyGroup(selection) {
  const {study, layer, strokes, part, origin, scale=[1,1], mirror_x=false, pigment="source"} = selection;
  const page=catalogue().get(study);
  if(!page)throw new RangeError("所选建筑参考页不存在");
  const byNumber=Object.hasOwn(selection,"strokes");
  if(byNumber===Object.hasOwn(selection,"part"))throw new RangeError("请用 strokes 原笔号或 part 公开部件名二选一");
  const fields=["study","layer",byNumber?"strokes":"part","origin","scale","mirror_x","pigment"];
  if(Object.keys(selection).some(key=>!fields.includes(key)))throw new RangeError("组笔含未识别字段");
  if(typeof layer!=="string" || !layer.trim() || /[\u0000-\u001f\u007f]/u.test(layer))throw new RangeError("请给这一组命名");
  const publishedPart = Object.hasOwn(page.parts ?? {}, part) ? page.parts[part] : undefined;
  const ids=byNumber?strokes:publishedPart ?? page.strokes.flatMap((stroke,i)=>stroke.layer===part?[i]:[]);
  if(!Array.isArray(ids)||ids.length===0)throw new RangeError("请选非空原笔号，或该页 parts 的部件名或 groups 的层名");
  if(ids.length>page.strokes.length||ids.some(id=>!Number.isInteger(id)||id<0||id>=page.strokes.length))
    throw new RangeError("《"+page.name+"》原笔号须在 0 至 "+(page.strokes.length-1)+" 之间");
  if(new Set(ids).size!==ids.length)throw new RangeError("同组不要重复选同一原笔号");
  return [...ids].sort((a,b)=>a-b).map(stroke=>{
    const name=layer.trim()+"·"+page.strokes[stroke].layer+"#"+stroke;
    if([...name].length>32)throw new RangeError("展开的笔层名超过32字，请缩短组名");
    return {study,stroke,layer:name,origin,scale,mirror_x,pigment};
  });
}
