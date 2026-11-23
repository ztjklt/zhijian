// Curves use the drawing's local, y-up metre coordinates. The game consumes
// ordinary brush points, including when it saves or reuses a master drawing.
const localNumber = { type: "number", minimum: -24, maximum: 24 };
const xy = { type: "array", minItems: 2, maxItems: 2, items: localNumber };
const degrees = { type: "number", minimum: -360, maximum: 360 };
const radius = { type: "number", exclusiveMinimum: 0, maximum: 24 };
const arc = {
  kind: { type: "string", enum: ["arc"] },
  center: xy,
  radii: { type: "array", minItems: 2, maxItems: 2, items: radius },
  rotation_deg: degrees,
  start_deg: degrees,
  sweep_deg: degrees
};
const cubic = { kind: { type: "string", enum: ["cubic"] }, from: xy, control1: xy, control2: xy, to: xy };
const curve = {
  description: "一笔圆弧、椭圆弧或三次贝塞尔。角度从局部右方起逆时针为正，全圈用360或−360。控制点、半径和端点均以米计。",
  anyOf: [arc, cubic].map(properties => ({
    type: "object", properties, required: Object.keys(properties), additionalProperties: false
  }))
};

// Keep the existing points schema intact as one of the two alternatives.
export function withCurveGeometry(pointsMark) {
  const { points, ...other } = pointsMark.properties;
  return { anyOf: [pointsMark, { ...pointsMark, properties: { ...other, curve },
    required: pointsMark.required.map(field => field === "points" ? "curve" : field) }] };
}

const maxSegments = 31;
const tolerance = 0.01;
const midpoint = (a, b) => [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2];
const validXY = p => Array.isArray(p) && p.length === 2 && p.every(Number.isFinite) && Math.hypot(...p) <= 24;
const validDegrees = n => Number.isFinite(n) && Math.abs(n) <= 360;

function sineCosine(angle) {
  const quadrant = angle / 90;
  if (Number.isInteger(quadrant)) return [[0, 1], [1, 0], [0, -1], [-1, 0]][(quadrant % 4 + 4) % 4];
  const radians = angle * Math.PI / 180;
  return [Math.sin(radians), Math.cos(radians)];
}

function arcPoints({ center, radii, rotation_deg, start_deg, sweep_deg }) {
  if (!validXY(center) || !Array.isArray(radii) || radii.length !== 2 ||
      !radii.every(n => Number.isFinite(n) && n > 0 && n <= 24) ||
      ![rotation_deg, start_deg, sweep_deg].every(validDegrees) || sweep_deg === 0)
    throw new RangeError("弧线须给实际圆心、两个正半径及角度；扫角在−360至360度内且非零");
  const [sinRotation, cosRotation] = sineCosine(rotation_deg);
  const at = angle => {
    const [sin, cos] = sineCosine(angle);
    const x = radii[0] * cos, y = radii[1] * sin;
    return [center[0] + x * cosRotation - y * sinRotation, center[1] + x * sinRotation + y * cosRotation];
  };
  // Keep extrema as vertices. A brush edge touching a counter, footing, or
  // water surface at its lowest point must still touch after tessellation.
  const peaks = [Math.atan2(-radii[1]*sinRotation, radii[0]*cosRotation),
    Math.atan2(radii[1]*cosRotation, radii[0]*sinRotation)];
  const cuts = [0, 1];
  for (const peak of peaks) {
    for (const halfTurn of [0, 180]) {
      const delta = Math.sign(sweep_deg) * (peak * 180/Math.PI + halfTurn - start_deg);
      const t = ((delta % 360 + 360) % 360) / Math.abs(sweep_deg);
      if (t > 1e-12 && t < 1 - 1e-12) cuts.push(t);
    }
  }
  const knots = [...new Set(cuts)].sort((a,b) => a-b);
  const points = [at(start_deg)];
  // Circle chord error also bounds the error after scaling to an ellipse.
  const maxAngle = Math.min(Math.PI/4, 2 * Math.acos(Math.max(-1, 1 - tolerance / Math.max(...radii))));
  const spans = knots.slice(1).map((end,i) => (end - knots[i]) * Math.abs(sweep_deg) * Math.PI/180);
  const counts = spans.map(span => Math.max(1, Math.ceil(span/maxAngle)));
  while (counts.reduce((sum,n) => sum+n, 0) > maxSegments) {
    const coarser = counts.map((n,i) => n > 1 ? spans[i]/(n-1) : Infinity);
    counts[coarser.indexOf(Math.min(...coarser))]--;
  }
  for (const [i,n] of counts.entries()) {
    for (let j=1; j<=n; j++) {
      const t = j===n ? knots[i+1] : knots[i] + (knots[i+1]-knots[i])*j/n;
      points.push(at(start_deg + sweep_deg*t));
    }
  }
  if (Math.abs(sweep_deg) === 360) points[points.length-1] = [...points[0]];
  return points;
}

// Bound the difference from the chord using its two equivalent Bézier
// controls. This also detects collinear curves that double back on themselves.
function chordError([a, b, c, d]) {
  return Math.max(Math.hypot(b[0] - (2*a[0] + d[0])/3, b[1] - (2*a[1] + d[1])/3),
    Math.hypot(c[0] - (a[0] + 2*d[0])/3, c[1] - (a[1] + 2*d[1])/3));
}

function cubicPoints({ from, control1, control2, to }) {
  const paths = [[from, control1, control2, to]];
  if (!paths[0].every(validXY)) throw new RangeError("贝塞尔曲线须给局部24米范围内的起点、两个控制点和终点");
  while (paths.length < maxSegments) {
    const errors = paths.map(chordError);
    const worst = Math.max(...errors);
    if (worst <= tolerance) break;
    const index = errors.indexOf(worst);
    const [a, b, c, d] = paths[index];
    const ab = midpoint(a, b), bc = midpoint(b, c), cd = midpoint(c, d);
    const left = midpoint(ab, bc), right = midpoint(bc, cd);
    const middle = midpoint(left, right);
    paths.splice(index, 1, [a, ab, left, middle], [middle, right, cd, d]);
  }
  return [[...from], ...paths.map(path => [...path[3]])];
}

export function expandCurveMark(mark) {
  if (!mark || !Object.hasOwn(mark, "curve")) return mark;
  const { curve: spec, ...ink } = mark;
  if (Object.hasOwn(ink, "points")) throw new RangeError("一笔请选择点列或曲线其中一种");
  const fields = spec?.kind === "arc" ? arc : spec?.kind === "cubic" ? cubic : null;
  if (!fields || Object.keys(spec).length !== Object.keys(fields).length ||
      !Object.keys(fields).every(key => Object.hasOwn(spec, key)))
    throw new RangeError("曲线类型或参数不全，请按工具列出的弧线或贝塞尔字段填写");
  const points = spec.kind === "arc" ? arcPoints(spec) : cubicPoints(spec);
  if (!points.every(validXY)) throw new RangeError("展开后的实际曲线须在图纸原点24米范围内");
  return { ...ink, points };
}
