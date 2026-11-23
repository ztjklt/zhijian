// Each bend belongs to the edge leaving an original anchor. Joint and bite
// indices always refer to the anchors, including on a previously filed sheet.
export const edgeBendsSchema = {
  type: "array", minItems: 0, maxItems: 12,
  description: "可选弯笔。edge 是起点的原轮廓编号（从0起），弯向 control 指定的部件局部控制点，止在下一原点。末边回第0点。没选的边留直，嘴角、翼尖和爪端可保留角。",
  items: {
    type: "object", required: ["edge", "control"], additionalProperties: false,
    properties: {
      edge: {type: "integer", minimum: 0, maximum: 11},
      control: {type:"array", minItems:2, maxItems:2, items:{type:"number",minimum:-2.5,maximum:2.5}}
    }
  }
};

export function sampleContour(part) {
  const anchors = part.outline;
  if (part.edge_bends === undefined) return anchors;
  if (!Array.isArray(anchors) || !Array.isArray(part.edge_bends) || part.edge_bends.length > anchors.length)
    throw Error("弯笔要配原轮廓，每条边可给一个控制点。");
  const controls = new Map();
  for (const bend of part.edge_bends) {
    if (!bend || !Number.isInteger(bend.edge) || bend.edge < 0 || bend.edge >= anchors.length || controls.has(bend.edge) ||
        !Array.isArray(bend.control) || bend.control.length !== 2 ||
        !bend.control.every(v => Number.isFinite(v) && Math.abs(v) <= 2.5))
      throw Error(part.id+" 的弯笔起点编号不可重复，control 用部件局部米坐标。");
    controls.set(bend.edge,bend.control);
  }
  if (!controls.size) return anchors;
  const shape = [];
  for (let i=0;i<anchors.length;i++) {
    const a = anchors[i], b = anchors[(i+1)%anchors.length];
    shape.push(a);
    const c = controls.get(i);
    if (!c) continue;
    // For a quadratic, the deviation from each sampled chord falls as 1/n².
    const sag = Math.hypot(a[0]-2*c[0]+b[0], a[1]-2*c[1]+b[1]) / 4;
    const slices = Math.max(1, Math.min(16, Math.ceil(Math.sqrt(sag/.006))));
    for (let j=1;j<slices;j++) {
      const t=j/slices, u=1-t;
      shape.push([u*u*a[0]+2*u*t*c[0]+t*t*b[0],u*u*a[1]+2*u*t*c[1]+t*t*b[1]]);
    }
  }
  return shape;
}

// Triangulators may accept a contour which doubles back onto itself. An
// original straight outline keeps its historical validator.
export function contourTouchesItself(points) {
  const epsilon = 1e-6;
  function onSegment(p, a, b) {
    const dx = b[0] - a[0], dy = b[1] - a[1];
    const fraction = Math.max(0, Math.min(1,
      ((p[0]-a[0])*dx + (p[1]-a[1])*dy) / (dx*dx + dy*dy)));
    return Math.hypot(p[0]-a[0]-fraction*dx, p[1]-a[1]-fraction*dy) <= epsilon;
  }
  for (let i=0; i<points.length; i++) {
    const a=points[i], b=points[(i+1)%points.length];
    const previous=points[(i+points.length-1)%points.length];
    if (Math.hypot(a[0]-b[0], a[1]-b[1]) <= epsilon ||
        onSegment(b, previous, a) || onSegment(previous, a, b)) return true;
    for (let j=i+2; j<points.length; j++) {
      if (i===0 && j===points.length-1) continue;
      const c=points[j], d=points[(j+1)%points.length];
      if (onSegment(a,c,d) || onSegment(b,c,d) || onSegment(c,a,b) || onSegment(d,a,b)) return true;
    }
  }
  return false;
}
