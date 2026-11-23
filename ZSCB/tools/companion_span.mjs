// Side-elevation drawing constraints. The agent authors the section, spring
// heights, ring, crown, stone joints and separate ridge in this observation.
const num = (minimum, maximum, description) => ({ type: "number", minimum, maximum, description });
const obj = properties => ({ type: "object", properties, required: Object.keys(properties), additionalProperties: false });
const unit = d => num(0,1,d);
const parameters = obj({
  left_foot: num(0,.28,"主景区内左外桥脚的位置比例"),
  right_foot: num(.72,1,"主景区内右外桥脚的位置比例"),
  left_pier: num(.28,.72,"左端桥台的实心宽度，米"), right_pier: num(.28,.72,"右端桥台宽，米"),
  apex: num(.32,.68,"拱顶在净跨内的位置比例，可不对称"),
  headroom: num(.88,1.44,"拱顶到谷底的期望垂直净空，米"),
  left_spring: num(.18,.42,"左侧起拱处距当地土面高度，米"), right_spring: num(.18,.42,"右侧起拱高度，米"),
  left_shoulder: num(.32,.85,"左拱曲线的饱满度，值越大拱肩越圆"), right_shoulder: num(.32,.85,"右拱饱满度"),
  ring: num(.12,.26,"拱圈石材的厚度，米"), deck: num(.12,.26,"桥面板厚度，米"),
  camber: num(0,.18,"桥面相对左右端的中央起拱，米；平面给0"),
  joints: { type:"array", maxItems:4, items:unit("沿拱圈从左端到右端的分石缝位置比例；只选你想落笔的位置") }
});
parameters.description = "可选的单孔跨越结构笔法。选择左右岸、净跨、起拱及桥面，按实测地表接两端桥脚，拱内留白；可以在桥以外独画一处远山。";
parameters.properties.ridge = obj({
  side:{type:"string",enum:["left","right"]}, width:num(1.25,2.45,"侧方远山占宽，米"),
  gap:num(.42,.9,"山与桥之间的最小横向留白，米"), height:num(.42,1.65,"远山高度，米"),
  points:{type:"array",minItems:3,maxItems:10,description:"你自己勾的一笔侧方山形。从左到右，局部原点在左下，每个[u,v]为0至1。",
    items:{type:"array",minItems:2,maxItems:2,items:unit("相对坐标")}}
});
export const masonrySpanSchema = parameters;

function check(ok, message) {
  if (!ok) { const e = new RangeError(message); e.name = "PainterGeometryError"; throw e; }
}
const lerp = (a,b,t) => a + (b-a)*t;
const mix = (a,b,t) => [lerp(a[0],b[0],t),lerp(a[1],b[1],t)];
const add = (a,b) => [a[0]+b[0],a[1]+b[1]];
const delta = (a,b) => [a[0]-b[0],a[1]-b[1]];
const clamp = (v,lo,hi) => Math.min(hi,Math.max(lo,v));

function distanceToChord(p,a,b) {
  const dx=b[0]-a[0], dy=b[1]-a[1], length=dx*dx+dy*dy;
  const t=length ? clamp(((p[0]-a[0])*dx+(p[1]-a[1])*dy)/length,0,1) : 0;
  return Math.hypot(p[0]-a[0]-dx*t,p[1]-a[1]-dy*t);
}

// Same finite-chord flatness (9 mm), max depth and subdivision as
// MedievalInkCurve.bake. Using doubles here differs only at float32 rounding.
export function sectionPolyline(points, handles = []) {
  const poly=[points[0]];
  function split(a,c1,c2,b,depth) {
    if (depth>=5 || Math.max(distanceToChord(c1,a,b),distanceToChord(c2,a,b))<=.009) {
      poly.push(b); return;
    }
    const ac=mix(a,c1,.5), mid=mix(c1,c2,.5), cb=mix(c2,b,.5);
    const l=mix(ac,mid,.5), r=mix(mid,cb,.5), m=mix(l,r,.5);
    split(a,ac,l,m,depth+1); split(m,r,cb,b,depth+1);
  }
  for (let i=0;i<points.length-1;i++) {
    const h=handles[i], a=points[i], b=points[i+1];
    if (h) split(a,add(a,h.slice(0,2)),add(b,h.slice(2)),b,0);
    else poly.push(b);
  }
  return poly;
}

export function sectionHeight(poly,x) {
  for (let i=1;i<poly.length;i++) {
    const a=poly[i-1], b=poly[i];
    if (x<=b[0]) return lerp(a[1],b[1],clamp((x-a[0])/(b[0]-a[0]),0,1));
  }
  return poly.at(-1)[1];
}

function numeric(value, schema, field) {
  check(Number.isFinite(value) && value>=schema.minimum && value<=schema.maximum,
    `单孔构图的${field}须在${schema.minimum}和${schema.maximum}之间`);
  return value;
}

function archHandles(a, b, roundness, isLeft) {
  const w=b[0]-a[0], h=b[1]-a[1];
  // Tangents spring vertically from each pier and meet horizontally at the crown.
  return isLeft ? [0,h*roundness,-w*roundness,0] : [w*roundness,0,0,-h*roundness];
}

function cubicAt(a,b,h,t) {
  const c=add(a,h.slice(0,2)), d=add(b,h.slice(2));
  return mix(mix(mix(a,c,t),mix(c,d,t),t),mix(mix(c,d,t),mix(d,b,t),t),t);
}

export function compileMasonrySpan(design, groundPoints, groundHandles, fixes=[], layout={}) {
  check(design && typeof design==="object","单拱构图缺少参数");
  for (const key of parameters.required) {
    if (key !== "joints") numeric(design[key],parameters.properties[key],key);
  }
  check(Array.isArray(design.joints) && design.joints.length<=4 && design.joints.every(j=>Number.isFinite(j)&&j>=0&&j<=1),"石缝请给0至4个0–1的位置");
  const ridge=design.ridge;
  if (ridge) {
    const declared=parameters.properties.ridge.properties;
    check(["left","right"].includes(ridge.side),"远山要选桥左侧或右侧");
    for (const key of ["width","height","gap"]) numeric(ridge[key],declared[key],key);
    check(Array.isArray(ridge.points) && ridge.points.length>=3 && ridge.points.length<=10 &&
      ridge.points.every(p=>Array.isArray(p)&&p.length===2&&p.every(v=>Number.isFinite(v)&&v>=0&&v<=1)),"山形由3–10个局部[u,v]点生成，原点左下");
    check(ridge.points.every((p,i)=>!i||p[0]>ridge.points[i-1][0]),"一笔远山的u请按向右顺序给出");
  }
  const soil=sectionPolyline(groundPoints,groundHandles), floor=x=>sectionHeight(soil,x);
  const left=soil[0][0]+.06,right=soil.at(-1)[0]-.06;
  const reserve=ridge ? ridge.width+ridge.gap : 0;
  const start=left+(ridge?.side==="left"?reserve:0), end=right-(ridge?.side==="right"?reserve:0);
  const requestedLeft=lerp(start,end,design.left_foot), requestedRight=lerp(start,end,design.right_foot);
  let x0=requestedLeft, x1=requestedRight;
  // Search real interior troughs, including a level bottom. Keep the original
  // bank selections where possible; never manufacture a valley in the soil.
  const troughs=[];
  for (let i=1; i<soil.length-1; i++) {
    if (soil[i][1]>=soil[i-1][1]-.00003) continue;
    let j=i;
    while(j+1<soil.length && Math.abs(soil[j+1][1]-soil[i][1])<.00003) j++;
    if(j+1<soil.length && soil[j+1][1]>soil[j][1]+.00003) troughs.push(mix(soil[i],soil[j],.5));
    i=j;
  }
  const options=[];
  function findBank(wanted, low, high, height) {
    if (high<low) return null;
    const closest=clamp(wanted,low,high);
    if (floor(closest)>=height) return closest;
    const xs=[low,high,...soil.filter(p=>p[0]>low&&p[0]<high).map(p=>p[0])];
    xs.push(...Array.from({length:80},(_,i)=>lerp(low,high,i/79)));
    return xs.filter(x=>floor(x)>=height).sort((a,b)=>Math.abs(a-wanted)-Math.abs(b-wanted))[0] ?? null;
  }
  for(const trough of troughs) {
    const minBank=trough[1]+.08;
    const l=findBank(x0,start,Math.min(end,trough[0]-.18-design.left_pier), minBank);
    const r=findBank(x1,Math.max(start,trough[0]+.18+design.right_pier),end, minBank);
    if(l!==null && r!==null && r-l-design.left_pier-design.right_pier>=1.65) {
      options.push({l,r,trough,cost:Math.abs(l-x0)+Math.abs(r-x1)});
    }
  }
  const placement=options.sort((a,b)=>a.cost-b.cost)[0];
  check(placement,"单拱需要坐在谷底两侧的岸上。请让主景区中部有先降后升的浅谷；远山放在谷底较远一侧，桥两岸应比谷底至少高0.08米");
  x0=placement.l; x1=placement.r;
  if (placement.cost>.001) fixes.push({target:"masonry_span",mode:"fit_banks",reason:"对齐模型画出的谷底两岸",before:[requestedLeft,requestedRight],after:[x0,x1]});
  const l=x0+design.left_pier,r=x1-design.right_pier,xm=lerp(l,r,design.apex);
  check(r-l>=1.65,"两桥台内缘之间请留至少1.65米；可加大跨距或收窄桥台");
  const base=x=>lerp(floor(x0),floor(x1),(x-x0)/(x1-x0));
  const camber=x=>{const u=(x-x0)/(x1-x0);return 4*design.camber*u*(1-u);};
  const topBase=x=>base(x)+camber(x);
  const leftSpring=[l,floor(l)+design.left_spring],rightSpring=[r,floor(r)+design.right_spring];
  // Leave a readable white aperture while keeping the entire visible deck
  // below the painter's 2 m envelope. Only the vertical lift can be fitted.
  const capDepth=design.deck+design.ring+.035;
  const requested=floor(xm)+design.headroom+capDepth-topBase(xm);
  const lower=Math.max(floor(xm)+.72+capDepth-topBase(xm),
    Math.max(leftSpring[1],rightSpring[1])+.25+capDepth-topBase(xm),
    leftSpring[1]+design.deck+.12-topBase(l-design.ring),rightSpring[1]+design.deck+.12-topBase(r+design.ring));
  const sampleXs=[x0,x1,...soil.filter(p=>p[0]>=x0&&p[0]<=x1).map(p=>p[0]),
    ...Array.from({length:101},(_,i)=>lerp(x0,x1,i/100))];
  const upper=Math.min(...sampleXs.map(x=>floor(x)+1.985-topBase(x)));
  check(lower<=upper,"这两岸落差让拱顶净空不足，请让桥跨过谷底、移桥脚或微调谷坡");
  let lift=clamp(requested,lower,upper);
  const top=x=>topBase(x)+lift;
  if (Math.abs(lift-requested)>.015) fixes.push({target:"masonry_span",mode:"fit_headroom",reason:"保持拱洞净空并使桥面在笔尖可达范围内",before:design.headroom,after:top(xm)-capDepth-floor(xm)});
  let cap=[xm,top(xm)-capDepth];
  const shoulders=[design.left_shoulder,design.right_shoulder];
  const curve = pts=>[archHandles(pts[0],pts[1],shoulders[0],true),archHandles(pts[1],pts[2],shoulders[1],false)];
  const deckLength=x1-x0, grade=(floor(x1)-floor(x0))/deckLength;
  const h=[deckLength/3,(grade+4*design.camber/deckLength)*deckLength/3,-deckLength/3,
    -(grade-4*design.camber/deckLength)*deckLength/3];
  let intrados,extrados,inner,outer,minimumSoffitGap;
  const firstCap=cap[1],firstLift=lift;
  for (let pass=0;pass<8;pass++) {
    intrados=[leftSpring,cap,rightSpring];
    extrados=[[l-design.ring,leftSpring[1]],[xm,cap[1]+design.ring],[r+design.ring,rightSpring[1]]];
    inner=curve(intrados);outer=curve(extrados);
    const back=sectionPolyline(extrados,outer);
    const fascia=sectionPolyline([[x0,top(x0)-design.deck],[x1,top(x1)-design.deck]],[h]);
    const xs=[...back.map(p=>p[0]),...fascia.filter(p=>p[0]>extrados[0][0]&&p[0]<extrados[2][0]).map(p=>p[0])];
    minimumSoffitGap=Math.min(...xs.map(x=>sectionHeight(fascia,x)-sectionHeight(back,x)));
    if(minimumSoffitGap>=.012) break;
    const adjustment=.028-minimumSoffitGap;
    const raise=Math.min(upper-lift,adjustment);
    lift+=raise;
    cap=[xm,cap[1]-(adjustment-raise)];
  }
  check(minimumSoffitGap>=.012 && cap[1]-floor(xm)>=.70,"外拱肩逼近桥面下缘，请放缓两岸高差、收窄拱肩，或将拱冠稍移向高岸");
  if(Math.abs(cap[1]-firstCap)>.001 || Math.abs(lift-firstLift)>.001) fixes.push({target:"masonry_span",mode:"fit_arch_ring",reason:"全拱圈位于桥面下缘以下",before:{crown_y:firstCap,deck_lift:firstLift},after:{crown_y:cap[1],deck_lift:lift}});
  const strokes=[], stroke_handles=[], stroke_ink=[], stroke_contacts=[], roles=[];
  function ink(role,anchors,handles,weight) {
    check(anchors.length>=2 && anchors.length<=16,"一笔需要2–16个锚点");
    roles.push({index:strokes.length,role});
    strokes.push(anchors);stroke_handles.push(handles ?? Array(anchors.length-1).fill(null));stroke_ink.push(weight);
    return strokes.length-1;
  }
  const lf=[x0,floor(x0)], rf=[x1,floor(x1)],li=[l,floor(l)],ri=[r,floor(r)];
  // Four paths join end-to-end. No line crosses the open space under the arch.
  const topStroke=ink("left_end_wall_deck_surface_right_end_wall",[lf,[x0,top(x0)],[x1,top(x1)],rf],[null,h,null],"bold");
  const inside=ink("left_inner_pier_intrados_right_inner_pier",[li,...intrados,ri],[null,...inner,null],"bold");
  function sole(a,b) {return [a,...soil.filter(p=>p[0]>a[0]+.0003&&p[0]<b[0]-.0003),b];}
  ink("left_foot_on_bank",sole(lf,li),null,"fine");ink("right_foot_on_bank",sole(ri,rf),null,"fine");
  stroke_contacts.push([topStroke,0],[topStroke,3],[inside,0],[inside,4]);
  ink("deck_soffit",[[x0,top(x0)-design.deck],[x1,top(x1)-design.deck]],[h],"fine");
  ink("arch_extrados",extrados,outer,"fine");
  for (const joint of design.joints) {
    const arc=joint<design.apex?0:1;
    const t=arc===0?joint/design.apex:(joint-design.apex)/(1-design.apex);
    ink("masonry_joint",[cubicAt(intrados[arc],intrados[arc+1],inner[arc],t),
      cubicAt(extrados[arc],extrados[arc+1],outer[arc],t)],null,"fine");
  }
  if (ridge) {
    const ridgeStart=ridge.side==="left"?left:right-ridge.width;
    const points=ridge.points.map(([u,v])=>{const x=ridgeStart+u*ridge.width;return [x,floor(x)+.07+v*ridge.height];});
    const gap=ridge.side==="left"? x0-Math.max(...points.map(p=>p[0])) : Math.min(...points.map(p=>p[0]))-x1;
    check(gap>=ridge.gap-.0001,"远山需留在桥轮廓外");
    ink("far_ridge",points,null,"faint");
    layout.ridge_gap_m=gap;
  }
  // Check the actual center of the aperture, plus its continuous width at
  // 0.35 m clearance. At ordinary play scale this leaves visible white paper.
  const soffit=sectionPolyline(intrados,inner);
  let wide=0, current=0;
  for (let i=0;i<=100;i++) {
    const x=lerp(l,r,i/100);
    current=sectionHeight(soffit,x)-floor(x)>=.35 ? current+(r-l)/100 : 0;
    wide=Math.max(wide,current);
  }
  check(cap[1]-floor(xm)>=.70 && wide>=1.25,"拱下白洞太小，请扩大跨距或抬高拱顶");
  // Both piecewise-linear surfaces have extrema of relative height at their
  // vertices (including ground vertices between two decoration samples).
  for (let i=0;i<strokes.length;i++) {
    const poly=sectionPolyline(strokes[i],stroke_handles[i]);
    for(let k=1;k<poly.length;k++) {
      const a=poly[k-1],b=poly[k];
      const samples=[a,b];
      if (Math.abs(b[0]-a[0])>.00001) {
        for(const [x] of soil) if(x>Math.min(a[0],b[0])&&x<Math.max(a[0],b[0])) samples.push([x,lerp(a[1],b[1],(x-a[0])/(b[0]-a[0]))]);
      }
      check(samples.every(([x,y])=>y-floor(x)>=-.010&&y-floor(x)<=2.005),
        "这份谷坡或山线穿过笔迹，请放缓桥底地表、收窄桥跨，或略提高山脚点");
    }
  }
  Object.assign(layout,{kind:"masonry_span", stroke_roles:roles, foot_contacts:stroke_contacts,
    banks:[lf,rf], valley:placement.trough, arch_crown:cap,
    aperture_height_m:cap[1]-floor(xm), aperture_width_at_035_m:wide, min_ring_deck_gap_m:minimumSoffitGap});
  return {stroke_space:"world",strokes,stroke_handles,stroke_ink,stroke_contacts};
}
