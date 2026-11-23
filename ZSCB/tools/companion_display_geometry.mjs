// Read-only arrangement of an existing ink group on a drawn surface. World metres, y up.
const isWash = brush => brush === 'wash' || brush === 'wash_pool';
const mm = n => Math.round(n * 1000) / 1000;
const pair = p => p.map(mm);
const plus = (p,d) => [p[0]+d[0],p[1]+d[1]];
const minus = (p,q) => [p[0]-q[0],p[1]-q[1]];
const xyBounds = points => [Math.min(...points.map(p=>p[0])),Math.min(...points.map(p=>p[1])),
  Math.max(...points.map(p=>p[0])),Math.max(...points.map(p=>p[1]))];
const edges = poly => poly.map((p,i)=>[p,poly[(i+1)%poly.length]]);
const winding = (a,b,c) => (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0]);
function contains(poly,p) {
  let hit=false;
  for (const [a,b] of edges(poly))
    if ((a[1]>p[1])!==(b[1]>p[1]) && p[0]<(b[0]-a[0])*(p[1]-a[1])/(b[1]-a[1])+a[0]) hit=!hit;
  return hit;
}
function surface(poly) { return {poly,box:xyBounds(poly)}; }
function touches(a,b) {
  if (a.box[0]>=b.box[2]||a.box[2]<=b.box[0]||a.box[1]>=b.box[3]||a.box[3]<=b.box[1]) return false;
  if (a.poly.some(p=>contains(b.poly,p))||b.poly.some(p=>contains(a.poly,p))) return true;
  return edges(a.poly).some(([p,q])=>edges(b.poly).some(([r,s])=>
    winding(p,q,r)*winding(p,q,s)<0 && winding(r,s,p)*winding(r,s,q)<0));
}
function ink(row) {
  const polygons=[...(row.faces??[])];
  for (const strip of row.ink_core_strips??[]) for(let i=1;i<strip.length;i++)
    polygons.push([strip[i-1][0],strip[i][0],strip[i][1],strip[i-1][1]]);
  return polygons.filter(poly=>poly.length>=3).map(surface);
}
function placed(fig,at) {
  if (!fig?.faces?.length) return [];
  const delta=minus(at,fig.feet);
  return fig.faces.map(poly=>surface(poly.map(p=>plus(p,delta))));
}
function supportEdges(supports) {
  const lines=[];
  for(const row of supports) {
    const segments=row.remaining??row.points.slice(1).map((b,i)=>[i,row.points[i],b]);
    for(const [segment,start,end] of segments) {
      const [a,b]=start[0]<end[0]?[start,end]:[end,start];
      if(b[0]-a[0]<.025||Math.abs(b[1]-a[1])>.36*(b[0]-a[0]))continue;
      lines.push({a,b,index:row.index,segment});
    }
  }
  return lines;
}
function topAt(lines,x) {
  let best;
  for (const line of lines) {
    const {a,b}=line;
    if(x<a[0]-1e-7||x>b[0]+1e-7)continue;
    const y=a[1]+(x-a[0])*(b[1]-a[1])/(b[0]-a[0]);
    if(!best||y>best.y)best={...line,y};
  }
  return best;
}
function worldToPlan(work,p) {
  const [x,y]=minus(p,work.origin),c=Math.cos(work.angle),s=Math.sin(work.angle);
  return pair([c*x+s*y,-s*x+c*y]);
}
function runs(samples,predicate) {
  const result=[]; let run;
  for(const sample of samples){
    if(!sample||!predicate(sample)){run=null;continue;}
    if(!run){run=[];result.push(run);}
    run.push(sample);
  }
  return result;
}
export function inspectDisplay(work,rows,supports,view,scale=1) {
  if(!Number.isFinite(scale)||scale<.1||scale>4)return {ok:false,reason:"display_scale 须在 0.1 至 4 之间，原尺寸填 1"};
  if(!view?.ppu)return {ok:false,reason:"本次观察缺少正常镜头与人物姿态"};
  const lines=supportEdges(supports);
  if(!lines.length)return {ok:false,reason:"所选承托笔没有幸存的近水平段"};
  const shapes=rows.flatMap(ink),all=shapes.flatMap(s=>s.poly);
  const tips=rows.flatMap(r=>r.remaining?r.remaining.flatMap(([,a,b])=>[a,b]):r.points);
  if(!all.length)return {ok:false,reason:"所选笔组已无可见笔面"};
  const box=xyBounds(all),width=(box[2]-box[0])*scale,height=(box[3]-box[1])*scale,pivot=[(box[0]+box[2])/2,box[1]];
  const resize=p=>plus(pivot,minus(p,pivot).map(n=>n*scale));
  const exclude=new Set([...rows,...supports]);
  const scenery=work.layers.filter(r=>!exclude.has(r)).map(row=>({id:row.index,kind:row.brush,surfaces:ink(row)}));
  const people=[];
  for(const who of ['player','painter'])if(view[who])people.push({id:who,feet:view[who].feet,surfaces:placed(view[who],view[who].feet)});
  for (const [i,s] of (work.stands??[]).entries()){
    const figure=s.kind==='counter'?view.player:(view.painter??view.player);
    people.push({id:'stand_'+i,feet:s.feet,surfaces:placed(figure,s.feet),use:s.use});
  }
  const lanes=(work.access_clearance??[]).map(([x,y,X,Y])=>surface([[x,y],[X,y],[X,Y],[x,Y]]));
  const standOverlap=[];
  const projected=people.filter(p=>p.id.startsWith('stand_'));
  for(const [i,a] of projected.entries())for(const b of projected.slice(i+1))
    if(a.surfaces.some(s=>b.surfaces.some(t=>touches(s,t))))standOverlap.push([a.id,b.id]);
  function overlaps(draw) {
    const hit=item=>item.surfaces.some(s=>draw.some(g=>touches(s,g)));
    return {access_overlap:lanes.some(l=>draw.some(s=>touches(s,l))),figures:people.filter(hit).map(p=>p.id),ink:scenery.filter(s=>!isWash(s.kind)&&hit(s)).map(s=>s.id),
      washes:scenery.filter(s=>isWash(s.kind)&&hit(s)).map(s=>s.id)};
  }
  const xs=lines.flatMap(l=>[l.a[0],l.b[0]]),xmin=Math.min(...xs),xmax=Math.max(...xs);
  const step=1/view.ppu,n=Math.ceil((xmax-xmin)/step),samples=[],shelfSamples=[];
  const inkMap=new Map(work.layers.map(r=>[r.index,ink(r)]));
  for(let i=0;i<=n;i++){
    const x=xmin+(xmax-xmin)*i/n,top=topAt(lines,x);
    if(top){
      const p=[x,top.y];
      const over=s=>s.surfaces.some(piece=>contains(piece.poly,p));
      const coveredByInk=work.layers.some(row=>row.index>top.index&&!isWash(row.brush)&&inkMap.get(row.index)?.some(piece=>contains(piece.poly,p)));
      shelfSamples.push({x,visible:!coveredByInk&&!people.some(over)});
    }else shelfSamples.push(null);
    if(!top||!topAt(lines,x-width/2)||!topAt(lines,x+width/2)){samples.push(null);continue;}
    // Require continuous support across the footprint; avoid bridging a broken shelf.
    let seated=true;
    for(let u=x-width/2;u<x+width/2;u+=step) {
      const support=topAt(lines,u);
      if(!support||Math.abs(support.y-top.y)>Math.max(step,width*.19)){seated=false;break;}
    }
    if(!seated){samples.push(null);continue;}
    const at=[x,top.y],d=minus(at,pivot);
    const moved=shapes.map(shape=>surface(shape.poly.map(p=>plus(resize(p),d))));
    const hit=overlaps(moved);
    const dMax=hand=>Math.max(...tips.map(p=>Math.hypot(...minus(plus(resize(p),d),hand))));
    const handRequired=view.hand?dMax(view.hand):null;
    const required=view.current_grip&&view.grounded?dMax(view.current_grip):null;
    samples.push({x,at,d,top,hit,required,handRequired});
  }
  function reading(s) {
    return {world_base_m:pair(s.at),plan_base_m:worldToPlan(work,s.at),translate_world_m:pair(s.d),
      support:[s.top.index,s.top.segment],...s.hit,current_hand_max_m:s.handRequired===null?null:mm(s.handRequired),planning_grip_max_m:s.required===null?null:mm(s.required),
      within_current_brush:s.required===null?null:s.required<=view.reach};
  }
  const clear=s=>!s.hit.access_overlap&&!s.hit.figures.length&&!s.hit.ink.length;
  const zones=[];
  for(const white of [true,false])for(const run of runs(samples,s=>clear(s)&&(s.hit.washes.length===0)===white)){
    const middle=run[Math.floor(run.length/2)];
    zones.push({clearance:white?'无本柜其他墨面':'底有淡洗',center_x_range_m:[mm(run[0].x),mm(run.at(-1).x)],
      reachable_center_x_m:runs(run,s=>s.required!==null&&s.required<=view.reach).map(part=>[mm(part[0].x),mm(part.at(-1).x)]),...reading(middle)});
  }
  zones.sort((a,b)=>Number(!b.washes.length)-Number(!a.washes.length)||
    (b.center_x_range_m[1]-b.center_x_range_m[0])-(a.center_x_range_m[1]-a.center_x_range_m[0]));
  const cost=s=>Number(s.hit.access_overlap)*5+s.hit.figures.length*3+s.hit.ink.length;
  const least=samples.filter(Boolean).sort((a,b)=>cost(a)-cost(b)||a.hit.washes.length-b.hit.washes.length)[0];
  const current=overlaps(shapes);
  const blockerIds=new Set([...current.ink,...current.washes,...(least?.hit.ink??[]),...(least?.hit.washes??[])]);
  const blockers=scenery.filter(s=>blockerIds.has(s.id)&&s.surfaces.length).map(s=>({index:s.id,layer:work.layers[s.id].layer,
    brush:s.kind,world_bounds_m:xyBounds(s.surfaces.flatMap(p=>p.poly)).map(mm)}));
  return {ok:true,ppu:view.ppu,viewport:view.viewport,scope:"本柜其他墨与人物姿态包围面；使用位人影为姿态投影，背景地图另看实景。",
    tested_scale:scale,scale_about_world_m:pair(pivot),group:rows.map(r=>r.index),group_px:[Math.round(width*view.ppu),Math.round(height*view.ppu)],current_world_bounds_m:box.map(mm),
    current_overlaps:current,projected_blockers:blockers,overlapping_stands:standOverlap,figures:people.map(p=>({id:p.id,feet_m:pair(p.feet),projected_bounds_m:p.surfaces.length?xyBounds(p.surfaces.flatMap(s=>s.poly)).map(mm):null,...(p.use?{use:p.use}:{})})),
    hand_m:view.hand?pair(view.hand):null,planning_grip_m:view.current_grip?pair(view.current_grip):null,grounded:view.grounded??null,brush_radius_m:view.reach??null,
    drawn_shelf_x_m:runs(shelfSamples,()=>true).map(r=>[mm(r[0].x),mm(r.at(-1).x)]),
    shelf_line_visible_x_m:runs(shelfSamples,s=>s.visible).map(r=>[mm(r[0].x),mm(r.at(-1).x)]),
    clear_positions:zones.slice(0,3),...(zones.length?{}:{reason:least?"按所试尺寸，各落点仍碰到线笔、人影或使用位净空":"整组宽于连续承托面",
      closest_test:least?reading(least):null})};
}
