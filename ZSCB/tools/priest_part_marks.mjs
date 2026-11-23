// Small details are stored in the original part's own bounding box, in metres-normalized UV.
// The native renderer clips each stroke to the silhouette. Reject marks with no ink inside it.
const unit = {type:"number", minimum:0, maximum:1};
const mark = {type:"object",additionalProperties:false,required:["brush","pigment","points"],properties:{
  brush:{type:"string",enum:["thin","wash"]}, pigment:{type:"string",pattern:"^#[0-9a-fA-F]{6}$"},
  points:{type:"array",minItems:2,maxItems:24,items:{type:"array",minItems:2,maxItems:2,items:unit}},
  source:{type:"string",minLength:1,maxLength:128}
}};
export const markList = {type:"array",maxItems:8,items:mark};
export const markRefs = {type:"array",maxItems:8,uniqueItems:true,items:{type:"string",minLength:1,maxLength:128}};
const epsilon = 1e-9;
const cross = (ax,ay,bx,by) => ax*by-ay*bx;
const pairs = (loop,closed=true) => loop.slice(closed ? 0 : 1).map((_,i)=>[loop[i],loop[(i+1)%loop.length]]);

function crossing([a,b],[c,d]) {
  const dx=b[0]-a[0],dy=b[1]-a[1],ex=d[0]-c[0],ey=d[1]-c[1];
  const denominator=cross(dx,dy,ex,ey);
  if(Math.abs(denominator)<epsilon) return null;
  const ox=c[0]-a[0],oy=c[1]-a[1];
  const t=cross(ox,oy,ex,ey)/denominator,u=cross(ox,oy,dx,dy)/denominator;
  return t>=0 && t<=1 && u>=0 && u<=1 ? t : null;
}
function inside([x,y], edges) {
  let odd=false;
  for(const [a,b] of edges) {
    if((a[1]>y)!==(b[1]>y) && x<(b[0]-a[0])*(y-a[1])/(b[1]-a[1])+a[0]) odd=!odd;
  }
  return odd;
}
function hasInteriorSegment(segment, edges) {
  const [a,b]=segment;
  if(Math.hypot(b[0]-a[0],b[1]-a[1])<epsilon) return false;
  const cuts=[0,1,...edges.map(edge=>crossing(segment,edge)).filter(t=>t!==null)].sort((x,y)=>x-y);
  for(let i=1;i<cuts.length;i++) {
    if(cuts[i]-cuts[i-1]<epsilon) continue;
    const t=(cuts[i]+cuts[i-1])*.5;
    if(inside([a[0]+t*(b[0]-a[0]),a[1]+t*(b[1]-a[1])],edges)) return true;
  }
  return false;
}
function visibleWash(points, outline) {
  const path=points.filter((p,i)=>!i || p[0]!==points[i-1][0] || p[1]!==points[i-1][1]);
  if(path.length && path[0][0]===path.at(-1)[0] && path[0][1]===path.at(-1)[1]) path.pop();
  if(path.length<3) return false;
  const edges=pairs(path);
  if(Math.abs(edges.reduce((area,[a,b])=>area+cross(...a,...b),0))<epsilon) return false;
  for(let i=0;i<edges.length;i++) for(let j=i+2;j<edges.length;j++){
    if(i===0 && j===edges.length-1) continue;
    if(crossing(edges[i],edges[j])!==null) return false;
  }
  // Scan at interior heights between vertices and edge crossings. Positive overlap
  // also detects equal polygons and shapes that enclose the entire cutout.
  const levels=[...path,...outline.map(([a])=>a)].map(p=>p[1]);
  for(const edge of edges) for(const border of outline) {
    const t=crossing(edge,border);
    if(t!==null) levels.push(edge[0][1]+t*(edge[1][1]-edge[0][1]));
  }
  levels.sort((a,b)=>a-b);
  const cutsAt=(rows,y)=>rows.filter(([a,b])=>(a[1]>y)!==(b[1]>y)).map(([a,b])=>a[0]+(b[0]-a[0])*(y-a[1])/(b[1]-a[1])).sort((a,b)=>a-b);
  for(let i=1;i<levels.length;i++) {
    if(levels[i]-levels[i-1]<epsilon) continue;
    const y=(levels[i]+levels[i-1])/2, a=cutsAt(edges,y), b=cutsAt(outline,y);
    for(let k=1;k<a.length;k+=2) for(let j=1;j<b.length;j+=2) {
      if(Math.min(a[k],b[j])-Math.max(a[k-1],b[j-1])>epsilon) return true;
    }
  }
  return false;
}
export function checkMarks(part, silhouette=part.outline) {
  if(part.marks===undefined) return;
  if(!Array.isArray(part.marks) || part.marks.length>8) throw Error(part.id+" 每件可留0–8笔细线或薄洗。");
  const xs=part.outline.map(p=>p[0]),ys=part.outline.map(p=>p[1]);
  const x=Math.min(...xs),y=Math.min(...ys),width=Math.max(...xs)-x,height=Math.max(...ys)-y;
  const edges=pairs(silhouette.map(p=>[(p[0]-x)/width,(p[1]-y)/height]));
  for(const [index,m] of part.marks.entries()) {
    const valid=m && ["thin","wash"].includes(m.brush) && typeof m.pigment==="string" && /^#[0-9a-f]{6}$/i.test(m.pigment)
      && (m.source===undefined || typeof m.source==="string" && m.source.length>0 && [...m.source].length<=128)
      && Array.isArray(m.points) && m.points.length>=(m.brush==="thin"?2:3) && m.points.length<=24
      && m.points.every(p=>Array.isArray(p)&&p.length===2&&p.every(v=>Number.isFinite(v)&&v>=0&&v<=1));
    if(!valid) throw Error(part.id+" 第"+(index+1)+"笔格式无效。thin 至少2点，wash 至少3点，每笔最多24个0..1局部点，颜料用 #rrggbb。");
    const visible=m.brush==="thin" ? pairs(m.points,false).some(edge=>hasInteriorSegment(edge,edges)) : visibleWash(m.points,edges);
    if(!visible) throw Error(part.id+" 第"+(index+1)+"笔在该部件轮廓内没有有效墨迹。检查笔点、自交与取形方向。");
  }
}
