// Project a vertex of the original mouth around a joint on its own parent chain.
// Limits match PriestSpecies.valid and the pickup frame on the actual foot line.
export function fruitPose(design, pivots, floor) {
  const request = design.fruit_bite ?? {};
  const mouth = design.parts.find(part => part.id === request.part_id);
  if (!mouth) throw Error("fruit_bite.part_id 须指向这张图里真实的口缘原件。顶点、枢轴和角度可省略请工具试量。");
  if (request.dip !== undefined && (!Number.isFinite(request.dip) || Math.abs(request.dip) > 1.4)) {
    throw Error("口缘角度 dip 须在 −1.4 至 1.4 弧度之间。");
  }
  const chain = [];
  for (let part = mouth; part; part = design.parts.find(parent => parent.id === part.parent)) chain.push(part);
  const [mouthX, mouthY] = pivots.get(mouth.id);
  const front = Math.max(...mouth.outline.map(([x]) => x));
  const angles = Array.from({length:57}, (_, index) => (index - 28) / 20);
  if (request.dip !== undefined && !angles.includes(request.dip)) angles.push(request.dip);
  let preferred = null;
  let alternative = null;
  let specifiedHeight;
  for (const [depth, joint] of chain.entries()) {
    if (!joint.parent && joint !== mouth && request.pivot_id !== joint.id) continue;
    const [jointX, jointY] = pivots.get(joint.id);
    for (const [index, [x, y]] of mouth.outline.entries()) {
      const dx = mouthX + x - jointX;
      const dy = mouthY + y - jointY;
      for (const angle of angles) {
        const height = jointY + dx * Math.sin(angle) + dy * Math.cos(angle) - floor;
        if (request.vertex === index && request.pivot_id === joint.id && angle === request.dip) specifiedHeight = height;
        if (height < -.035 || height > .235) continue;
        const score = Math.abs(height - .09) + .13 * (front - x) + .016 * Math.abs(angle) + .005 * depth;
        const settings = {part_id:mouth.id, vertex:index, pivot_id:joint.id, dip:angle};
        const sample = {settings, height:Number(height.toFixed(4)), score};
        if (!alternative || score < alternative.score) alternative = sample;
        if (request.vertex !== undefined && request.vertex !== index) continue;
        if (request.pivot_id !== undefined && request.pivot_id !== joint.id) continue;
        if (request.dip !== undefined && request.dip !== angle) continue;
        if (!preferred || score < preferred.score) preferred = sample;
      }
    }
  }
  if (preferred) return preferred;
  const measured = specifiedHeight === undefined ? "" : "指定姿势口缘距脚面 " + specifiedHeight.toFixed(3) + " 米。";
  if (alternative) {
    const error = Error(measured + "指定姿势够不到地果。原稿点列、层次和步相已留存，可确认同一件嘴的实测姿势。");
    error.poseOffer = alternative;
    throw error;
  }
  throw Error(measured + "口件在可用关节和角度内够不到地果。请放低颈根或向嘴前延长口沿，目标是低头后前下缘在脚面上约0.09米。");
}
