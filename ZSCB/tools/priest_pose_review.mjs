import {sampleContour} from "./priest_contour.mjs";
// The four reported poses use the same pivots, wave and axis as PriestSpecies.frames.
const tau = 2 * Math.PI;
const toWorld = ([x,y], {x:ox,y:oy,angle}) => [
  ox + x * Math.cos(angle) - y * Math.sin(angle),
  oy + x * Math.sin(angle) + y * Math.cos(angle)
];

function sample(parts, phase, mode, bite) {
  const joints = new Map();
  return parts.map(part => {
    const home = joints.get(part.parent) ?? {x:0,y:0,angle:0};
    const [x,y] = toWorld(part.joint, home);
    const amplitude = (mode === "fly" && part.motion === "flap") ? part.amplitude ?? .65 :
      (mode === "walk" && part.motion === "stride") ? part.amplitude ?? .39 :
      (mode === "walk" && part.motion === "sway") ? part.amplitude ?? .16 : 0;
    // At the deepest pickup pose (fraction 0.5) the authored pivot is at full dip.
    const swing = mode === "pickup" && part.id === bite.pivot_id
      ? bite.dip : amplitude * Math.sin(phase * (part.rate ?? 1) + tau * part.phase);
    const angle = home.angle + swing;
    const joint = {x,y,angle};
    joints.set(part.id, joint);
    const shape = {id:part.id, motion:part.motion, depth:part.depth ?? "body",
      points:sampleContour(part).map(p => toWorld(p,joint))};
    if (bite?.part_id === part.id && part.outline[bite.vertex]) shape.mouth = toWorld(part.outline[bite.vertex],joint);
    return shape;
  });
}

function contains(loop,x,y) {
  let inside = false;
  for (let i=0, j=loop.length-1; i<loop.length; j=i++) {
    const [ax,ay] = loop[i], [bx,by] = loop[j];
    if ((ay>y) !== (by>y) && x < ax + (bx-ax)*(y-ay)/(by-ay)) inside = !inside;
  }
  return inside;
}

function edgeDistance(point, a, b) {
  const dx=b[0]-a[0], dy=b[1]-a[1];
  const t=Math.max(0,Math.min(1,((point[0]-a[0])*dx+(point[1]-a[1])*dy)/(dx*dx+dy*dy)));
  return Math.hypot(point[0]-a[0]-t*dx,point[1]-a[1]-t*dy);
}

const depthOrder = {far:0, body:1, near:2};

// InkLifeForm paints from far to near. Equal-depth pieces keep the authored order.
function paintOrder(shapes) {
  return [...shapes].sort((a,b) => depthOrder[a.depth] - depthOrder[b.depth]);
}

function rimDistance(point,shape) {
  return Math.min(...shape.points.map((a,i) =>
    edgeDistance(point,a,shape.points[(i+1)%shape.points.length])));
}

function coveringPart(layers, shape, point) {
  const index = layers.indexOf(shape);
  for (let i=layers.length-1; i>index; i--) {
    const other = layers[i];
    if (contains(other.points,...point) && rimDistance(point,other)>1e-6) return other.id;
  }
  return null;
}

function lowestTips(layers, contacts) {
  return contacts.map(shape => {
    const bottom = Math.min(...shape.points.map(p=>p[1]));
    const tips = shape.points.filter(p => p[1] <= bottom+1e-6);
    const covers = tips.map(tip => coveringPart(layers,shape,tip));
    return {part:shape.id, lowest_points:tips.length,
      exposed_points:covers.filter(id=>id===null).length,
      covered_by:[...new Set(covers.filter(id=>id!==null))]};
  });
}

function pickupReview(design,floor) {
  const bite = design.fruit_bite;
  if (!bite || !Number.isInteger(bite.vertex) || !Number.isFinite(bite.dip)) return null;
  const layers = paintOrder(sample(design.parts,0,"pickup",bite));
  const muzzle = layers.find(part=>part.id===bite.part_id);
  const pivot = layers.find(part=>part.id===bite.pivot_id);
  if (!muzzle?.mouth || !pivot) return null;
  const mouth = muzzle.mouth;
  const strides = layers.filter(part=>part.motion==="stride").map(part=>({
    part, distance:contains(part.points,...mouth) ? 0 : rimDistance(mouth,part)
  })).sort((a,b)=>a.distance-b.distance);
  const nearest = strides.slice(0,2).map(({part,distance}) => ({
    part:part.id, mouth_point_gap_m:+distance.toFixed(3),
    muzzle_outline_gap_m:+polygonGap(muzzle.points,part.points).toFixed(3),
    pivot_outline_gap_m:+polygonGap(pivot.points,part.points).toFixed(3)
  }));
  return {part:muzzle.id, original_vertex:bite.vertex,
    mouth_m:[+mouth[0].toFixed(4),+(mouth[1]-floor).toFixed(4)],
    covered_by:coveringPart(layers,muzzle,mouth), pivot:pivot.id, nearest_stride:nearest};
}

function polygonGap(a,b) {
  if(contains(a,...b[0]) || contains(b,...a[0]))return 0;
  const cross=(p,q,r)=>(q[0]-p[0])*(r[1]-p[1])-(q[1]-p[1])*(r[0]-p[0]);
  let gap=Infinity;
  for(let i=0;i<a.length;i++)for(let j=0;j<b.length;j++){
    const p=a[i],q=a[(i+1)%a.length],r=b[j],s=b[(j+1)%b.length];
    if(cross(p,q,r)*cross(p,q,s)<0 && cross(r,s,p)*cross(r,s,q)<0)return 0;
    gap=Math.min(gap,edgeDistance(p,r,s),edgeDistance(q,r,s),edgeDistance(r,p,q),edgeDistance(s,p,q));
  }
  return gap;
}

function wingOverlap(wings, roots) {
  const points = wings.flatMap(w => w.points);
  const xs = points.map(p => p[0]), ys = points.map(p => p[1]);
  const left = Math.min(...xs), bottom = Math.min(...ys);
  const dx = (Math.max(...xs)-left)/48, dy = (Math.max(...ys)-bottom)/48;
  let shared = 0, independent = 0, union = 0;
  for (let j=0; j<48; j++) for (let i=0; i<48; i++) {
    const filled = wings.filter(w => contains(w.points,left+(i+.5)*dx,bottom+(j+.5)*dy));
    if (filled.length) union++;
    if (filled.length<2) continue;
    shared++;
    const firstRoot=roots.get(filled[0].id);
    if(filled.some(w=>roots.get(w.id)!==firstRoot))independent++;
  }
  return [shared,independent].map(area=>union ? Math.round(100*area/union) : null);
}

export function reviewPose(design) {
  const result = {units:"m", wing_overlap_pct:[], wing_branch_overlap_pct:[], walking_support:[], joints:[], joint_gaps_m:{}};
  const parts = design.parts;
  // Overlap of a wrist and its own tip is normal articulation. Compare
  // independent flapping chains to measure overlap between distinct wings.
  const byId=new Map(parts.map(p=>[p.id,p]));
  const wingRoots=new Map();
  for (const part of parts.filter(p=>p.motion==="flap")) {
    let root=part;
    for (let parent=byId.get(part.parent); parent; parent=byId.get(parent.parent)) {
      if(parent.motion==="flap")root=parent;
    }
    wingRoots.set(part.id,root.id);
  }
  const hasSeparateWings=new Set(wingRoots.values()).size>=2;
  const minimum = polygons => Math.min(...polygons.flatMap(p => p.points.map(v => v[1])));
  const rest = sample(parts,0,"rest"), floor = minimum(rest);
  const limbs = parts.filter(p => p.motion==="stride");
  for (const part of parts) result.joints.push([part.id,part.parent,part.motion,part.phase]);
  for (let n=0; n<4; n++) {
    const phase = n*tau/4;
    const flown = sample(parts,phase,"fly"), walk = sample(parts,phase,"walk");
    const wings = flown.filter(p => p.motion==="flap");
    for(const shapes of [flown,walk,rest]){
      const byID=new Map(shapes.map(s=>[s.id,s.points]));
      for(const p of parts){
        if(!p.parent)continue;
        const gap=polygonGap(byID.get(p.id),byID.get(p.parent));
        if(gap>.002)result.joint_gaps_m[p.id]=Math.max(result.joint_gaps_m[p.id]??0,+gap.toFixed(3));
      }
    }
    if (wings.length>=2) {
      const [all,independent]=wingOverlap(wings,wingRoots);
      result.wing_overlap_pct.push(all);
      if(hasSeparateWings)result.wing_branch_overlap_pct.push(independent);
    }
    if (!limbs.length) continue;
    const bottom = minimum(walk);
    const contacts = walk.filter(p=>minimum([p])<=bottom+.035);
    result.walking_support.push({phase:n/4,lowest_m:+(bottom-floor).toFixed(3),
      ground_adjustment_m:parts.some(p=>p.wash!==undefined)?+(floor-bottom).toFixed(3):0,
      contact_parts:contacts.map(p=>p.id), lowest_tips:lowestTips(paintOrder(walk),contacts)});
  }
  const pickup = pickupReview(design,floor);
  if (pickup) result.lowest_pickup = pickup;
  result.silhouette_note = "平地侧视的图纸投影。lowest_tips 数每件最低的原轮廓采样点，covered_by 是画在上面并包住该点的部件。lowest_pickup 在低头最深处取原嘴点，列最近两件步足到嘴点、整件嘴轮廓及低头枢轴所在部件轮廓的距离。实际坡面、果实位置与取食请到现场核实。";
  result.note="四个翼相的 wing_branch_overlap_pct 只比较不同翼根支链，相交投影占所有翼投影面积的估计百分比；wing_overlap_pct 也计入同翼关节相接。低点取未贴地的骨架，相对静姿脚面；淡彩稿的地面动作会按 ground_adjustment_m 对齐真实支撑。joint_gaps_m 列出采样时父子轮廓间大于 2 毫米的最大空隙。高重叠或同脚长期承重时先重画一件再复看。";
  return result;
}
