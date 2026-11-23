// One character chooses one capability from what it can perceive in this world.
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { compileMasonrySpan, masonrySpanSchema } from "./companion_span.mjs";
import { withSceneLayerInspection } from "./companion_layer_geometry.mjs";
import { decideBuilding } from "./companion_building.mjs";
import { readSceneSkill, sceneCommand, channelFrontierTurn, sceneTools } from "./companion_scene.mjs";
import { parseArguments, runWorker } from "./east_painter.mjs";

const pair = { type: "array", minItems: 2, maxItems: 2, items: { type: "number" } };
const name = { type: "string", description: "你给作品起的简短中文名，最多12字" };
const text = { type: "string", description: "当面说的一句简短中文，至多40字" };
function object(properties) {
  return { type: "object", properties, required: Object.keys(properties), additionalProperties: false };
}
function line(minItems, maxItems, description) {
  return { type: "array", minItems, maxItems, items: pair, description };
}
function strokes(minItems, maxItems, maxPoints, description) {
  return { type: "array", minItems, maxItems, description,
    items: object({ points: line(2, maxPoints, description) }) };
}

const curveMode = { type: "string", enum: ["smooth", "line"] };
const handles = { ...curveMode, description: "整条路径的基础笔法：smooth为贯连圆弧，line保留棱角。需要局部变化时可加overrides。" };
const overrides = { type: "array", maxItems: 10, description: "可选的局部笔法，省略时整笔沿用基础笔法。span从0开始。四个数分别相对起点和末点给出出柄dx,dy和入柄dx,dy。", items: object({
  span: { type: "integer", minimum: 0 }, mode: { anyOf: [curveMode,
    { type: "array", minItems: 4, maxItems: 4, items: { type: "number" } }] }
}) };
const landscapePath = "tools/skills/paper-landscape/SKILL.md";
async function readLandscapeSkill() {
  const bytes = await readFile(new URL("./skills/paper-landscape/SKILL.md", import.meta.url));
  const content = bytes.toString("utf8");
  const summary = content.match(/^description:\s*(.+)$/m)?.[1]?.trim() ?? "";
  return { content, receipt: { path: landscapePath, bytes: bytes.length, summary,
    sha256: createHash("sha256").update(bytes).digest("hex") } };
}

function fieldOfView(source) {
  const list = (key, limit) => Array.isArray(source[key]) ? source[key].slice(0, limit) : [];
  return {
    world_reports: source.world_reports,
    identity: "阿靛", self: source.self, human: source.human, sites: list("sites", 12),
    nearby: list("nearby", 12), built: list("built", 12), nearby_npcs: list("nearby_npcs", 12),
    recent_dialogue: (source.recent_dialogue ?? []).slice(-12), invitation: source.invitation ?? {},
    can_draw: Boolean(source.can_draw), last_result: source.last_result ?? {},
    edge: source.edge ?? {}, pen: source.pen ?? {}, autonomy: source.autonomy??null,
    site_pen: source.site_pen??{}, divine_chat:source.divine_chat??null, scene_project:source.scene_project??null,
    scene_components:list("scene_components",4),scene_plans:list("scene_plans",36), scene_foundation:list("scene_foundation",25), scene_shore:source.scene_shore??null, scene_siting:list("scene_siting",7), scene_revisions:list("scene_revisions",12),
    scene_counters:list("scene_counters",3),scene_underpass:source.scene_underpass??null,scene_basins:list("scene_basins",5),scene_water:source.scene_water??null,scene_studies:Array.isArray(source.scene_studies)?source.scene_studies:[],scene_study_index:source.scene_study_index??null,scene_distant:source.scene_distant===true,scene_distant_frames:list("scene_distant_frames",16),scene_study:source.scene_study??null,scene_plant:source.scene_plant??null
  };
}

function checkCarveRing(points, stroke) {
  const open = points.filter((point, index) => !index || Math.hypot(
    point[0]-points[index-1][0], point[1]-points[index-1][1]) > .0001);
  if (open.length > 1 && Math.hypot(open[0][0]-open.at(-1)[0], open[0][1]-open.at(-1)[1]) <= .0001) open.pop();
  const turn = (a,b,c) => (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0]);
  const twiceArea = open.reduce((sum, point, i) => sum + turn(open[0], point, open[(i+1)%open.length]), 0);
  const hint = `第${stroke + 1}笔开槽须围出一块单独的面积。先沿一侧画到远端，再从不同高度画另一侧回到首点；收笔线不能穿过中间的边。`;
  requireValue(open.length >= 3 && Math.abs(twiceArea) > .00001, hint);
  for(let i=0; i<open.length-2; i++){
    const a=open[i], b=open[i+1];
    for(let j=i+2; j<open.length; j++){
      if(i===0 && j===open.length-1) continue;
      const c=open[j], d=open[(j+1)%open.length];
      if(turn(a,b,c)*turn(a,b,d)<-1e-10 && turn(c,d,a)*turn(c,d,b)<-1e-10) requireValue(false,hint);
    }
  }
}

function editablePaperProject(view) {
  const scene = view.scene_project;
  return view.divine_chat && !view.divine_chat.project_id && scene?.project_id &&
    ["working","paused"].includes(scene.stage) && ["landscape","water","verify"].includes(scene.current?.kind)
    ? scene : null;
}

function paperModes(view) {
  const modes=view.autonomy?.paper?.modes??[];
  const ambient=view.autonomy&&!view.divine_chat&&!view.invitation?.kind;
  return ambient ? modes.filter(mode=>mode!=="water"&&mode!=="carve") : modes;
}

function capabilities(view) {
  const tools = [];
  function offer(name, description, properties = {}) {
    tools.push({ name, description, parameters: object(properties) });
  }
  const modes=paperModes(view);
  function offerPaper(extra = {}) {
    if (!Array.isArray(modes)||!modes.length || view.autonomy.paper.brush?.stations?.length===0) return;
    offer("paper_ink","用真实二维地形笔在当前现场动手。承重浮台 / 实岩 / 挖空 / 背墙 / 水 / 远景以用途选择。",{
      name,direction:{type:"string",enum:["west","east","up","down"]},
      strokes:{type:"array",minItems:1,maxItems:5,items:object({mode:{type:"string",enum:modes},
        anchor:object({kind:{type:"string",enum:["ground","wall","hanging","free"]},
          at:{...pair,description:"实际首笔支点。ground 使用接缝 seam、current_floor 或已测脚面。无脚面探测值 probe_x 不是支点。"}}),
        points:line(2,48,"绝对世界坐标。岩、水、挖空、背墙是闭合轮廓（提交时自动连首尾），浮台是单向横折线。每点在阿靛手笔附近。")})},
      ...extra
    });
    const project = editablePaperProject(view);
    if (project) tools.at(-1).parameters.properties.project_id = {
      type:"string", enum:[project.project_id],
      description:"只在玩家明确要延续这一项现存工程时填当前工程编号。新作品随同一工程保存，普通单笔另作省略。"
    };
    const sections=(view.scene_project?.channel_plan?.sections??[]).filter(row=>!row.verified);
    if ((project || view.divine_chat?.project_id) && sections.length) {
      tools.at(-1).parameters.properties.segment_id = {
        type:"string",enum:sections.map(row=>row.id),
        description:"沿已登记的分段施工稿落这一笔时选择实际小段。工作由现场笔程约束，不把整个施工稿当一笔。"
      };
      if (view.divine_chat?.project_id && view.scene_underpass) tools.at(-1).parameters.required.push("segment_id");
    }
  }
  function offerFrontierPaint(extra = {}) {
    if (!Array.isArray(view.edge.edge) || view.edge.busy) return;
    const stroke = object({ points: line(2, 12, "同一地标框里的局部锚点[u,v]，以0..1为画格，超过边缘时整幅比例映射入框。原点在左下，u向右，v向上；拱顶中央v大于两端，垂枝末梢v小于分叉点。把分枝根点与主干、枝杈上的局部锚点重合。"),
      brush: { type: "string", description: "力度_笔势：smooth为曲线，line为折线；单写力度就是原始锚点直连。",
        enum: ["bold_smooth", "fine_smooth", "faint_smooth", "bold_line", "fine_line", "faint_line", "bold", "fine", "faint"] } });
    stroke.properties.overrides = overrides;
    stroke.properties.level = { type: "boolean", description: "仅真正的水平线如水面设true，整笔保持第一点的世界高度；默认false。" };
    offer("paint_edge", "亲自用铅笔从当前东边缘续画地面与小景。", {
      name, style: { type: "string", description: "简述这段地势的笔法，至多32字" },
      landmark: { type: "string", description: "本次具体画的地标及其特征，至多48字" },
      terrain_handles: handles,
      width: { type: "number", minimum: 8, maximum: 9, description: "路段总宽，单位米。" },
      runs: { type: "array", minItems: 3, maxItems: 9, description: "从左到右的连续地表。每段先分配0.4米，剩余宽度按你选的weight分配。grade是升高/水平距离；正值上坡，负值下坡，0是平台。", items: object({
        weight: { type: "number", minimum: 0.1, maximum: 20 }, grade: { type: "number", minimum: -0.56, maximum: 0.56 }
      }) },
      landmark_box: object({ place: { type: "number", minimum: 0, maximum: 1, description: "地标框在路段余宽中的位置，0靠左，1靠右。" },
        width: { type: "number", minimum: 2.4, maximum: 4 }, height: { type: "number", minimum: 1.3, maximum: 2 } }),
      strokes: { type: "array", minItems: 1, maxItems: 9, items: stroke },
      ...extra
    });
    const paint = tools.at(-1).parameters;
    paint.properties.terrain_overrides = overrides;
    paint.properties.ground_material = {type:"string",enum:["soil","stone","bank","paper"],
      description:"道床断面的画法。土层选 soil、实岩 stone、可见湿岸 bank、保留原纸线与作者轮廓用 paper；这里的材料只影响绘制。"};
    paint.properties.masonry_span = masonrySpanSchema;
    paint.required = paint.required.filter(key => key !== "landmark_box" && key !== "strokes");
    paint.oneOf = [{ required: ["landmark_box", "strokes"] }, { required: ["masonry_span"] }];
  }
  if (view.divine_chat) {
    const message={ type:"string", description:"给玩家一句自然中文答复或进度，至多80字" };
    const extension = view.divine_chat.selected_site?.after_arrival === "expand";
    if (extension || view.edge?.edge && !view.divine_chat.project_id) offerFrontierPaint({message});
    if (!extension && !view.divine_chat.project_id && view.divine_chat.east_frontier?.distance > .75 && view.divine_chat.travel_left > 0)
      offer("travel_frontier","把地图外沿接出新的可走陆地。先亲自走到实测的东侧纸边，到场后按同一句委托作一份连续地表。玩家说扩充地图、向外接图、拓宽世界时用此项。",{message});
    if (!view.divine_chat.project_id) offer("divine_reply","回答、咨询说明或只问一个仍缺少的澄清信息。此动作不会创作。",{message});
    if (extension) return tools;
    sceneTools(view,offer);
    if (view.divine_chat.project_id) {
      const phase=view.scene_project?.current;
      const checks=["reuse_shore_plan","finish_scene_foundation"];
      if (phase?.form==="foundation" && view.scene_project.trade && !view.scene_underpass && !view.scene_counters.length && tools.some(tool=>checks.includes(tool.name))) {
        return tools.filter(tool=>checks.includes(tool.name)||tool.name==="pause_scene");
      }
      const structural=phase?.kind==="landscape"&&!["distant","scenery"].includes(phase.form)&&!view.scene_project?.subject;
      if (structural && !(view.scene_underpass&&view.scene_project?.channel_plan?.sections?.length)) offerFrontierPaint({message});
      const measuredWater=tools.some(tool=>["cut_scene_basin","fill_scene_basin","open_scene_bank"].includes(tool.name));
      if (structural || phase?.kind==="water"&&(!measuredWater || view.scene_underpass)) offerPaper({message});
      return tools;
    }
    offerPaper({message});
    const banks=(view.scene_underpass?.reachable_lower_approaches??[]).filter(row=>row.distance>.45);
    if (banks.length && view.divine_chat.travel_left>0) {
      offer("walk_channel_bank","沿可走的现有干路下到原柜的某一岸。选西岸 west 或东岸 east，再从该岸真实脚面的 route 编号中选。继续画槽时填 create。",{
        bank:{type:"string",enum:[...new Set(banks.map(row=>row.bank))]},
        site:{type:"string",enum:banks.map(row=>row.id)},
        after_arrival:{type:"string",enum:["report","create"]},message
      });
    }
    const routes=(view.autonomy?.routes??[]).filter(row=>row.distance>.75&&Number.isFinite(row.stand?.[1])&&
      !(banks.length && row.id?.startsWith("underpass@")));
    if (routes.length&&view.divine_chat.travel_left>0) {
      offer("travel","前往明确约定的现有地点。只去、探查或看看填 report；玩家明确要求到场施工才填 create。",{id:{type:"string",enum:routes.map(row=>row.id)},
        after_arrival:{type:"string",enum:["report","create"]},message});
    }
    return tools;
  }
  offer("look", view.autonomy ? "暂缓动笔。仅当缺少安全支点、值得等待的世界变化或明确记下风险时使用。" : "看看身边的变化，或安静地歇一歇。");
  if (!view.autonomy && !view.recent_dialogue.length && !view.invitation.kind && !view.last_result.ok) {
    offer("greet", "第一次遇见近旁玩家，朝玩家打招呼。", { text });
  }
  if (!view.autonomy) offer("talk_player", "回应玩家、说出刚刚实际打听到的消息，或分享眼前的发现。", { text });
  if (view.autonomy) {
    const routes=(view.autonomy.routes??[]).filter(row=>row.distance>.75);
    if (view.autonomy.frontier?.distance > .75) {
      offer("survey_frontier","自主开拓时，先亲自走到已查明可达的真实纸边。到达后用当前纸边连续落笔；地图内的小工程不改变纸边。");
    }
    if (routes.length) offer("travel","沿现有实地走向一处值得探查的区域，到了再检查现场。",{id:{type:"string",enum:routes.map(row=>row.id)}});
    if (view.site_pen.ground?.length>0) {
      offer("shape_site","用地形笔整理眼前的经营用地或补通已有作品的入口。笔须承重，留明确进出。",{
        name, points:line(3,12,"绝对世界坐标。x 单向递增，从地表起笔，坡度≤0.62，至少留一段0.9米近水平面。"),
        improves:{type:"string",enum:["",...(view.autonomy.works??[]).map(work=>work.id).filter(Boolean)]}
      });
    }
    offerPaper();
    if (view.autonomy.scene_opportunity?.need) sceneTools(view,offer);
  }
  if (view.nearby_npcs.length) {
    offer("talk_npc", "走近眼前的居民，询问近况、村里的消息，或当地的路和风物。回答由现场返回。", {
      id: { type: "string", enum: view.nearby_npcs.map(npc => npc.id) }, text
    });
  }
  if (view.sites.length) {
    const site = { type: "string", enum: view.sites.map(site => site.id) };
    offer("walk", "自己走去考察一个可达站位。", { site });
    if (view.can_draw) {
      offer("walk_and_draw", "走到空旷站位画一件小物。", { site, name,
        outline: line(4, 18, "相对落点中心的一笔闭合轮廓，x在-0.60到0.60，y在0到1，末点重复首点。") });
    }
  }
  offerFrontierPaint();
  if (["draw_scenery", "draw_terrain", "draw_object"].includes(view.pen.requested)) {
    const penStrokes = strokes(1, 6, 24, "每笔是绝对世界坐标[x,y]，位于ground和view_y范围内，绘于当地地表以上0至1.2米。");
    if (view.pen.brushes?.length) {
      penStrokes.items.properties.brush = {type:"string", enum:view.pen.brushes, description:"bold 浓线，fine 细线，wash 闭合平洗，wash_pool 闭合积色薄洗。薄洗末点应等于首点，按提交顺序叠加。"};
    }
    if (view.pen.pigments?.length) {
      penStrokes.items.properties.pigment = {type:"string", enum:view.pen.pigments, description:"逐笔颜料。inherit 沿用原墨，ochre 赭黄，cinnabar 朱砂，indigo 花青，malachite 石绿。"};
    }
    offer("functional_pen", "拿起玩家递来的功能笔，根据可见地表亲自画出景物、承重地形或可推物件。", {
      command: object({ name, style: { type: "string", enum: view.pen.styles ?? ["ink", "pencil"] },
        strokes: penStrokes })
    });
  }
  if (view.invitation.kind === "copy" && view.pen.reference) {
    offer("copy_scenery", "在手边的画纸上按顺序誊绘玩家递来的景物草稿，原比例落在已选位置。", {
      revision: {type:"integer", enum:[view.pen.reference.revision]}
    });
  }
  // A player's concrete request is a capability selection; the character still
  // authors every word and every point using this observation.
  const invitations = { paint: "paint_edge", pen: "functional_pen", copy: "copy_scenery", npc: "talk_npc", talk: "talk_player" };
  const selected = tools.find(tool => tool.name === invitations[view.invitation.kind]);
  if (view.autonomy) for (const tool of tools) Object.assign(tool.parameters.properties,{
    goal:{type:"string",maxLength:32,description:"可向玩家公开的一句目标"},
    reason:{type:"string",maxLength:56,description:"一个实际观察依据。只填事实摘要，不给私有推理过程。"}
  });
  if (view.autonomy) for (const tool of tools) tool.parameters.required.push("goal","reason");
  if (view.autonomy?.paper?.local_gaps?.length) {
    const paper = tools.findIndex(tool=>tool.name==="paper_ink");
    if(paper>0) tools.unshift(tools.splice(paper,1)[0]);
  }
  const frontierAction = view.autonomy?.frontier_arrival ? "paint_edge" : "survey_frontier";
  if (view.autonomy?.scene_opportunity?.need) {
    const project = tools.findIndex(tool=>tool.name==="plan_scene");
    if (project>0) tools.unshift(tools.splice(project,1)[0]);
  } else if (view.autonomy?.frontier_arrival || view.autonomy?.frontier_priority) {
    const frontier = tools.findIndex(tool=>tool.name===frontierAction);
    if(frontier>0) tools.unshift(tools.splice(frontier,1)[0]);
  }
  return selected ? [selected] : tools;
}

const paperReachInstruction = "paper.brush.feet 是你实际站稳的脚点，paper.surfaces 也包含脚下别层的地面。看 paper.brush.stations：每小段的两个端点必须落在同一可达站位 grip 的 radius 圆内；可分段换站，由你走到后实际挥笔。paper.last_reach_failure 给出上一笔失败的两端、最近可用站点、真实笔长和需要的距离。先改笔高或长度、换站位或 travel 到另一处；若没有能接的安全脚面才暂缓。";

function autonomyPrompt(view, landscape) {
  const relevantTechnique = landscape?.content.split("\n## 建筑笔法")[0]??"";
  return `你是《纸间》的至高神画家阿靛。你和村民、冒险者在同一张纸上生活。你可以营造聚落、画有深浅远近的山水、修一处实际有人需要的设施、到纸边开路，也可以先去问人或走走。你自己选眼下这局最值得做的事。无需玩家领路、允许中途调整或择址。现场已由游戏测量，直接调用一个动作工具，给简短工程目标 goal 和客观依据 reason。
延续 autonomy.engineering 中尚未完成的工程，或因明确的新情况改主意。有可站面和可用笔程时，可以直接用少量笔处理眼前缺口。有更合适的现场则 travel；整理受阻的经营用地则 shape_site；村民确有缺少的信息时才 talk_npc。look 表示等待，你没有观测到明确机会或支点暂不安全时可以选它。若现场没变，重复等待或向同一个人问候不会推进工程。
paper.current_floor 与 paper.local_gaps 的 seam 是游戏采样出的实际支点。缺口方向和 probe_x 指出近处哪里失去脚面，paper.surfaces 给出其它可接的地面及洞顶。绝对坐标以米计，y 向上。${paperReachInstruction} 自行决定方向、长度和构图。platform 可站，要让人从现有支点踏上去；rock 是实体，carve 挖出留白通道，backdrop/scenery 只改变视觉，water 的最高边要水平。
有 edge.edge 时用 paint_edge 接连续坡面和地标，保持原地末端切线。普通路面可有一处长坡或宽肩，留原有排水和干路；少作无用途的凹口。如果决定造水景，先看 paper.nearby_waterlines 里已有哪片真实水岸。若水是主景或用来行船、灌溉，在同一岸先立范围明确的水景工程，连着分笔，别把陆路点缀当池水。
autonomy.frontier 是已核实可走去的真实外沿，frontier_priority 表示已有地图内作品而外沿仍未扩。若没有优先的本地险情，可自主用 survey_frontier 到达它；在新外沿核对真实接缝后用 paint_edge。已经到场的 frontier_arrival 要落实一段向外可行走的地表；现场存在明确阻碍才等候或改目标。小修、询问、用地整理照常保留，不能把村内新笔记成扩边。
${relevantTechnique}\n现场：${JSON.stringify(view)}`;
}

function divineChatPrompt(view, landscape) {
  const technique=landscape?.content.split("\n## 建筑笔法")[0]??"";
  const arrival=view.divine_chat.arrived_at ? `到达事件：你已经走到约定的「${view.divine_chat.selected_site?.label??"施工点"}」，实际身体在 ${JSON.stringify(view.divine_chat.arrived_at)}。这是同一条明确委托后续的现场施工回合。${view.divine_chat.selected_site?.after_arrival==="expand" ? "从 edge.edge 用 paint_edge 画到旧边界之外，交一份连续可走的地表；若现场确实变了，用 divine_reply 说清阻碍。" : "根据到场的脚面用 paper_ink 创作，或用 divine_reply 说明物理阻碍。"}不要再次只说“我会过去/我会画”。\n` : "";
  return `你是《纸间》的至高神画家阿靛。玩家从至高神状态与你讲话，角色可以相距很远。读 divine_chat.text 的真实中文语意，不用问号等符号来分类。
“你能画什么？”是咨询，直接用 divine_reply 正常答复。“去村西看看”是行路，用 travel / report，到场由游戏回报，别添任何笔画。“可以在这里帮我画个浅湖吗？”是已经提出的创作委托。若现场可做，用 paper_ink；若在别处的已知地点，用 travel / create，到达后会带同一句原话和新现场。只有地点或用途确实不明，或现有动作无法做到时，才作一句具体澄清。divine_reply 只送出一句话，不能启动未来的旅行或绘画。
“你去扩充地图吧”“把可走的地图往外接一段”是增加边界外的可走地形。若没到东侧纸边，用 travel_frontier；若 edge.edge 已在现场，用 paint_edge。不要用普通景点的 travel / create、地图内添一块浮台或口头答应代替扩图。自然语言中明确委托局部景物仍用 paper_ink，咨询和纯旅行也保有各自入口。
“这里”“我脚边”通常指 divine_chat.player_at 的玩家发话位置。如果玩家指“你脚边”，看 self 与实际手位。读最近对话和 divine_chat.last_work；如用户说“再浅一点”，用此前一份真实已完成作品的确切位置、点列、模式继续处理，保留其他作品。可通过衔接的新笔局部改善，如砂砾底抬高浅水区；如果当前工具无法可靠完成请求的删除或改形，说明限制或提供能执行的局部处理。不得声称已经完成未执行的稿。
问附近铺子卖或收什么、在哪、有没有货或我在忙什么时，以 divine_chat.local_stalls 的当局事实作普通话答复。每个柜台的 at_m 是来客位，distance_m 是相对发问者的距离，direction=sell_to_customer 才是出售，stock=0 表示售罄；buy_from_customer 是收购，coins_reserved_for_purchases=0 表示当前收款箱无法支付一份。null 表示库存或收购款未能确认，可以报登记价格并说明未知。答复必须符合该柜的 status；没有给出的数据和买入后存放的物品数量不能说成可售量或可付金额。没有匹配的实测铺位，直接说眼下不能确定，别把旧小说或规划中的建筑当已营业。问我在做什么时照 painter.state 如实答。说项目暂停即可，不推测何时会重开工。单纯问询用 divine_reply。
每次只用一个工具。绝对世界坐标以米计，y向上。按四向选择眼前用途：platform 承重，rock 实岩，carve 挖出通道，backdrop 与 scenery 仅景，water 是真实水体。画湖可在同一份 paper_ink 先用 carve 划出能从坡面走入的浅盆，再用 water 填其中的空部。water 最高边必须由相邻两点构成，两点 y 完全相同。开笔优先选少量实际够得着的点。${paperReachInstruction} 地表、挂壁或吊点支撑的笔 first point 贴对应的 anchor.at。local_gaps 的 probe_x 表示缺脚面，可把笔伸过去。seam 才是这方向接近的旧支点。以短句向玩家说准备做什么，真实执行和完成由游戏反馈。
${arrival}${technique}\n现场：${JSON.stringify(view)}`;
}

function atNewFrontier(view) {
  const edge = view.edge.edge;
  const crossed = view.last_result.edge;
  return !view.invitation.kind && view.last_result.ok && view.last_result.tool === "paint_edge" &&
      isPair(edge) && isPair(crossed) && Math.abs(crossed[0] - edge[0]) < 0.01 &&
      isPair(view.self) && Math.abs(view.self[0] - edge[0]) <= 1.5;
}

function requireValue(condition, feedback) {
  if (!condition) {
    const error = new RangeError(feedback);
    error.name = "PainterGeometryError";
    throw error;
  }
}
function isPair(point) {
  return Array.isArray(point) && point.length === 2 && point.every(Number.isFinite);
}
function unpackStrokes(input, maxLines, maxPoints) {
  requireValue(Array.isArray(input) && input.length >= 1 && input.length <= maxLines, "笔画条数越界");
  return input.map(stroke => {
    const points = stroke?.points ?? stroke;
    requireValue(Array.isArray(points) && points.length >= 2 && points.length <= maxPoints && points.every(isPair), "每笔须含有效坐标对");
    return points;
  });
}

function cleanText(value, limit) {
  requireValue(typeof value === "string", "文字缺失");
  const cleaned = value.replace(/[\u0000-\u001f\u007f]/g, " ").trim();
  requireValue(cleaned.length > 0 && cleaned.length <= limit, "文字太长或为空");
  return cleaned;
}

// Convert the model's smooth span into two cubic handles. Limit the three
// derivative control slopes on ground, so all intermediate tangents are walkable.
function smoothSpan(points, i, ground, incoming) {
  const a = points[i], b = points[i + 1];
  const before = points[i - 1] ?? a, after = points[i + 2] ?? b;
  const third = (b[0] - a[0]) / 3;
  if (ground) {
    const slope = (b[1] - a[1]) / (b[0] - a[0]);
    const blend = other => other * slope > 0 ? 2 * slope * other / (slope + other) : 0;
    const limit = value => Math.min(0.6, Math.max(-0.6, value));
    // At the seam the previous work already owns the tangent. At internal
    // knots the same harmonic slope is computed from either neighboring span.
    const outgoing = limit(i === 0 ? (incoming ?? slope) : blend((a[1] - before[1]) / (a[0] - before[0])));
    const arriving = limit(i + 2 >= points.length ? slope : blend((after[1] - b[1]) / (after[0] - b[0])));
    const handlesAt = length => [length, outgoing*length, -length, -arriving*length];
    const withinSlope = length => !invalidHandle(handlesAt(length), a, b, [-Infinity,-Infinity,Infinity,Infinity], true);
    // Preserve the longest valid arm. Shortening arm length (both components)
    // preserves dy/dx at the shared knot even alongside a horizontal terrace.
    if (withinSlope(third)) return handlesAt(third);
    let low = 0, high = third;
    for (let step = 0; step < 18; step++) {
      const middle = (low + high) / 2;
      if (withinSlope(middle)) low = middle;
      else high = middle;
    }
    return handlesAt(low * 0.999);
  }
  // Keep a rounded ornament inside each pair's box, including near a bend
  // that turns back west or reaches its highest permitted ink point.
  const tangent = (previous, knot, next) => {
    const left = knot - previous, right = next - knot;
    return left * right > 0 ? 2 * left * right / (left + right) : 0;
  };
  const out = a.map((v, axis) => (i === 0 ? b[axis] - v : tangent(before[axis], v, b[axis])) / 3);
  const inn = b.map((v, axis) => -(i+2 >= points.length ? v - a[axis] : tangent(a[axis], v, after[axis])) / 3);
  return [...out, ...inn];
}

function compileHandles(spec, points, changes = [], ground = false, incoming = undefined) {
  const spans = points.length - 1;
  const modes = typeof spec === "string" ? Array(spans).fill(spec) : Array.isArray(spec) ? spec.slice() : spec;
  requireValue(Array.isArray(modes) && modes.length === spans, "逐段笔法数量须等于线段数；整笔可直接填smooth或line");
  requireValue(Array.isArray(changes) && changes.length <= spans, "局部笔法必须指定现有线段");
  for (const change of changes) {
    requireValue(Number.isInteger(change?.span) && change.span >= 0 && change.span < spans, "局部切柄的span须是从零计数的线段编号");
    modes[change.span] = change.mode;
  }
  return modes.map((mode, i) => {
    if (mode === "line" || mode === null) return null;
    if (mode === "smooth") return smoothSpan(points, i, ground, incoming);
    requireValue(Array.isArray(mode) && mode.length === 4 && mode.every(Number.isFinite), "控制柄须为四个有限数");
    return mode;
  });
}

// Match MedievalInkCurve.validate_handles: Godot stores anchors and controls
// as float32 Vector2, then checks the quadratic Bernstein derivative extrema.
function invalidHandle(handle, a, b, bounds, ground) {
  const f = Math.fround;
  const p = a.map(f), q = b.map(f);
  const c = p.map((value, i) => f(value + f(handle[i])));
  const d = q.map((value, i) => f(value + f(handle[i + 2])));
  for (const [x, y] of [c, d]) {
    if (x < bounds[0]-0.0002 || y < bounds[1]-0.0002 || x > bounds[2]+0.0002 || y > bounds[3]+0.0002) return "控制点越出纸面";
  }
  if (!ground) return "";
  if (c[0] < p[0] || d[0] < c[0] || q[0] < d[0]) return "地表的相对切柄交叉或逆向";
  const span = [p,c,d,q];
  for (const sign of [-1,1]) {
    const [a,b,c] = span.slice(1).map(([x,y], i) => f(f(f(0.6) * f(x - span[i][0])) + f(sign * f(y - span[i][1]))));
    let min = Math.min(a,c);
    const bend = a - 2*b + c;
    if (bend > 0) {
      const t = (a-b)/bend;
      if (t > 0 && t < 1) min = Math.min(min, (1-t)*(1-t)*a + 2*(1-t)*t*b + t*t*c);
    }
    if (min < -0.00005) return "局部曲率导致坡度超出步行范围";
  }
  return "";
}

function fitHandles(handles, points, bounds, path, fixes, ground, incoming) {
  return handles.map((old, i) => {
    if (old === null) return null;
    const check = h => invalidHandle(h, points[i], points[i+1], bounds, ground);
    const reason = check(old);
    if (!reason) return old;
    // Shorten both handles by the same factor to retain their directions.
    // Impossible tangent directions keep the anchors and use a local smooth span.
    const candidates = [0.7,0.5,0.25].map(scale => ({ mode: "shorten", scale, h: old.map(v => v*scale) }));
    candidates.push({ mode: "smooth", h: smoothSpan(points,i,ground,incoming) });
    const corrected = candidates.find(candidate => !check(candidate.h));
    const next = corrected?.h ?? null;
    fixes.push({ target: path, span: i, reason, mode: corrected?.mode ?? "line", before: old,
      after: next, ...(corrected?.scale ? { scale: corrected.scale } : {}) });
    return next;
  });
}

function checkDryRoad(points) {
  let shoulder=null;
  let bottom=null;
  for(let i=1;i<points.length;i++){
    const previous=points[i-1];
    const point=points[i];
    const rise=point[1]-previous[1];
    if(rise<-.005){
      if(bottom===null||previous[1]>bottom[1]+.03)shoulder=previous;
      bottom=point;
    }
    if(shoulder&&bottom&&rise>.005){
      const floor=Math.min(shoulder[1],point[1])-bottom[1];
      const width=point[0]-shoulder[0];
      requireValue(width>2.1||floor<.08,
        "这段普通干路的两肩之间形成了一个孤立的小坑。请把这段短凹形接成平顺坡面；若要真池或溪，在同一片有用途的岸区立水景工程。");
    }
  }
}

export function groundCommand(args, edge, fixes = [], layout = {}) {
  const origin = edge.edge;
  const inRange = (v, low, high) => Number.isFinite(v) && v >= low && v <= high;
  requireValue(inRange(args.width, 8, 9), "路段总宽须为8到9米");
  const runs = args.runs;
  requireValue(Array.isArray(runs) && runs.length >= 3 && runs.length <= 9 && runs.every(r =>
    inRange(r?.weight, 0.1, 20) && inRange(r?.grade, -0.56, 0.56)), "每段需要横宽权重0.1至20和坡度-0.56至0.56");
  const total = runs.reduce((sum, r) => sum + r.weight, 0);
  const points = [origin];
  for (const { weight, grade } of runs) {
    const dx = 0.4 + (args.width - 0.4 * runs.length) * weight / total;
    const [x, y] = points.at(-1);
    const nextY = y + dx * grade;
    requireValue(inRange(nextY, edge.limits?.min_y ?? -6, edge.limits?.max_y ?? 24), "地表高度越界");
    points.push([x + dx, nextY]);
  }
  const [a, b] = (edge.tail ?? []).slice(-2);
  const incoming = edge.previous_work?.end_slope ?? (a && b && a[0] !== b[0] ? (b[1]-a[1])/(b[0]-a[0]) : undefined);
  const terrainHandles = fitHandles(compileHandles(args.terrain_handles, points, args.terrain_overrides, true, incoming),
    points, [origin[0],edge.limits?.min_y ?? -6,points.at(-1)[0],edge.limits?.max_y ?? 24], "terrain", fixes, true, incoming);
  const ground = { revision: edge.revision, name: cleanText(args.name, 32), style: cleanText(args.style, 32),
    landmark: cleanText(args.landmark, 48), points, terrain_handles: terrainHandles };
  if (args.ground_material!==undefined) {
    requireValue(["soil","stone","bank","paper"].includes(args.ground_material),"道床材质使用 soil、stone、bank 或 paper");
    ground.ground_material=args.ground_material;
  }
  if (args.masonry_span) {
    requireValue(args.landmark_box === undefined && args.strokes === undefined, "单拱笔法与自由地标二选一");
    return { ...ground, ...compileMasonrySpan(args.masonry_span, points, terrainHandles, fixes, layout) };
  }
  const box = args.landmark_box;
  requireValue(box && inRange(box.place, 0, 1) && inRange(box.width, 2.4, 4) && inRange(box.height, 1.3, 2), "地标框的place须为0–1、width须为2.4–4、height须为1.3–2");
  const left = origin[0] + (args.width - box.width) * box.place;
  const localMarks = unpackStrokes(args.strokes, 9, 12);
  const vertices = localMarks.flat();
  requireValue(vertices.every(pt => pt.every(v => Math.abs(v) < 4)), "地标需要同一张约0–1的局部画格，请勿混入世界坐标");
  const us = vertices.map(p => p[0]), vs = vertices.map(p => p[1]);
  const minU = Math.min(0,...us), minV = Math.min(0,...vs), maxU = Math.max(1,...us), maxV = Math.max(1,...vs);
  const sx = box.width/(maxU-minU), sy = box.height/(maxV-minV);
  if (minU !== 0 || minV !== 0 || maxU !== 1 || maxV !== 1) {
    fixes.push({target: "landmark_box", mode: "fit", reason: "将整幅越出局部画格的草图映射入模型选定的地标框",
      local_bounds:[minU,minV,maxU,maxV], width:box.width, height:box.height});
  }
  const marks = localMarks.map(stroke => stroke.map(([u,v]) => [left+(u-minU)*sx,(v-minV)*sy]));
  const weights = [];
  const strokeHandles = args.strokes.map((stroke, i) => {
    const [weight, shape = "line"] = String(stroke.brush).split("_");
    requireValue(["bold", "fine", "faint"].includes(weight) && ["smooth", "line"].includes(shape),
      `第${i+1}笔的brush须选力度+笔势，例如fine_smooth或bold_line`);
    weights.push(weight);
    const hs = compileHandles(shape, localMarks[i], stroke.overrides).map(h => h && [h[0]*sx,h[1]*sy,h[2]*sx,h[3]*sy]);
    return fitHandles(hs, marks[i], [origin[0],0,points.at(-1)[0],2], `stroke[${i}]`, fixes, false);
  });
  return { ...ground, strokes: marks, stroke_handles: strokeHandles, stroke_ink: weights, stroke_level: args.strokes.map(s => s.level === true) };

}

export function checkPenReach(strokes, reach) {
  if (!reach) return;
  for (const [i, line] of strokes.entries()) {
    for (let j = 1; j < line.length; j++) {
      const fits = reach.stations.some(({grip}) => [line[j-1],line[j]].every(
        ([x,y]) => Math.hypot(x-grip[0],y-grip[1]) <= reach.radius
      ));
      requireValue(fits, `第${i+1}笔第${j}段超出真实站位的笔程。用 pen.reach 中同一 grip 为圆心、radius 为半径容纳整段，缩矮或移近，同时保留选定的颜料。`);
    }
  }
}

function checkPaperReach(points, brush, index) {
  if (!Array.isArray(brush?.stations)) return;
  for (let j = 1; j < points.length; j++) {
    let nearest;
    let excess = Infinity;
    for (const station of brush.stations) {
      const distance = Math.max(...[points[j-1], points[j]].map(([x,y]) =>
        Math.hypot(x-station.grip[0], y-station.grip[1])));
      const radius = Math.min(brush.reach??brush.radius, station.radius??brush.radius);
      if (distance-radius < excess) {
        nearest = {station,distance,radius};
        excess = distance-radius;
      }
    }
    const hint = nearest ? `最近可达脚点 ${JSON.stringify(nearest.station.feet)}、握位 ${JSON.stringify(nearest.station.grip)}，整段需 ${nearest.distance.toFixed(2)} 米，计划笔程 ${nearest.radius} 米` : "附近没有已测到的可施工脚点";
    const barrier = brush.blocked_departure ? `。${brush.blocked_departure}` : "";
    requireValue(excess <= 0, `第${index+1}笔第${j}段 ${JSON.stringify([points[j-1],points[j]])} 超出笔程。当前脚点 ${JSON.stringify(brush.feet)}、手位 ${JSON.stringify(brush.hand)}。${hint}${barrier}。抬高、缩短或改选 travel`);
  }
}

// Intermediate samples stay on the model's original straight segment. They
// let the game change stance along a long bank without moving the contour.
function subdivideInk(points) {
  const samples=[points[0]];
  for(let i=1;i<points.length;i++){
    const [x,y]=points[i-1];
    const next=points[i];
    const count=Math.ceil(Math.hypot(next[0]-x,next[1]-y)/.65);
    for(let slice=1;slice<count;slice++)
      samples.push([x+(next[0]-x)*slice/count,y+(next[1]-y)*slice/count]);
    samples.push(next);
  }
  requireValue(samples.length<=128,"这条笔划换站过多，把其中一路拆成下一笔");
  return samples;
}

function normalize(call, view, fixes, layout) {
  const args = parseArguments(call);
  const project = sceneCommand(call.name,args,view,requireValue,cleanText);
  if (project !== undefined) {
    if(call.name==="paint_scene_detail")
      project.command.strokes=project.command.strokes.map((points,index)=>{
        const samples=subdivideInk(points);
        checkPaperReach(samples,view.autonomy?.paper?.brush,index);
        return samples;
      });
    if(call.name==="compose_scene_study"){
      const study=(view.scene_study??view.scene_plant).study;
      const {origin,pivot,scale,mirror_x:mirror,strokes}=project.spec;
      strokes.forEach((id,index)=>{
        const mark=study.strokes.find(row=>row.stroke===id);
        const points=mark.points.map(([x,y])=>[origin[0]+(x-pivot[0])*scale[0]*(mirror?-1:1),
          origin[1]+(y-pivot[1])*scale[1]]);
        if(["wash","wash_pool"].includes(mark.brush)&&points[0].some((v,i)=>v!==points.at(-1)[i]))points.push(points[0]);
        checkPaperReach(subdivideInk(points),view.autonomy?.paper?.brush,index);
      });
    }
    if(["paint_scene_channel","fill_scene_basin","open_scene_bank","cut_scene_basin","excavate_channel_gap","paint_channel_seam","extend_channel_water"].includes(call.name))
      project.strokes.forEach((stroke,index)=>{
        stroke.points=subdivideInk(stroke.points);
        checkPaperReach(stroke.points,view.autonomy?.paper?.brush,index);
      });
    return project;
  }
  switch (call.name) {
    case "survey_frontier":
      requireValue(!view.divine_chat&&view.autonomy?.frontier?.distance>.75,"这轮没有可走去的外沿");
      return {};
    case "travel_frontier":
      requireValue(view.divine_chat?.east_frontier?.distance > .75 && view.divine_chat.travel_left > 0,"本轮没有可走的东侧纸边");
      return {message:cleanText(args.message,80)};
    case "travel":
      requireValue(view.autonomy?.routes.some(row=>row.id===args.id&&row.distance>.75),"目的地不在本轮地图中");
      if(view.divine_chat)requireValue(["report","create"].includes(args.after_arrival),"请区分只需到场的 report 与明确有作画委托的 create");
      return {id:args.id,...(view.divine_chat?{message:cleanText(args.message,80),after_arrival:args.after_arrival}:{})};
    case "shape_site": {
      const ground=view.site_pen.ground??[], pts=args.points;
      requireValue(view.autonomy&&Array.isArray(pts)&&pts.length>=3&&pts.length<=12&&pts.every(isPair),"需一笔3至12个有效地形点");
      requireValue(pts.every(([x,y])=>x>=ground[0]?.[0]&&x<=ground.at(-1)?.[0]&&Math.hypot(x-view.self[0],y-view.self[1])<=4.6),"地形笔须在画家脚下的局部范围");
      let plateau=false;
      for(let i=1;i<pts.length;i++){
        const dx=pts[i][0]-pts[i-1][0], dy=Math.abs(pts[i][1]-pts[i-1][1]);
        requireValue(dx>=.10&&dy<=dx*.62+1e-5,"地形折线不可倒退，坡度须≤0.62");
        if(dx>=.90&&dy<=.08)plateau=true;
      }
      requireValue(plateau,"经营用地至少留0.9米连续近水平面");
      const improves=args.improves??"";
      requireValue(improves===""||view.autonomy.works.some(work=>work.id===improves),"改善对象须来自现场已有作品");
      return {command:{tool:"draw_terrain",name:cleanText(args.name,32),style:"ink",strokes:[pts],improves}};
    }
    case "paper_ink": {
      const paper=view.autonomy?.paper;
      const modes=paperModes(view);
      requireValue(Array.isArray(modes)&&["west","east","up","down"].includes(args.direction),"请选择现场支持方向与公共笔划");
      requireValue(Array.isArray(args.strokes)&&args.strokes.length>=1&&args.strokes.length<=5,"一次只提交1至5笔");
      const close=at=>isPair(at)&&Math.hypot(at[0]-view.self[0],at[1]-view.self[1])<=5.0;
      const accepted=[];
      for(const [index,row] of args.strokes.entries()){
        requireValue(modes.includes(row?.mode)&&["ground","wall","hanging","free"].includes(row.anchor?.kind)&&close(row.anchor.at),"模式或支点不在演员可达现场");
        requireValue(Array.isArray(row.points)&&row.points.length>=2&&row.points.length<=48&&row.points.every(close),"每笔2至48点，必须在实地执笔范围");
        const [anchorX,anchorY]=row.anchor.at;
        const [firstX,firstY]=row.points[0];
        if (row.mode==="platform") {
          const direction = Math.sign(row.points.at(-1)[0]-firstX);
          for (let i=1;i<row.points.length;i++) {
            const [prevX,prevY] = row.points[i-1];
            const [x,y] = row.points[i];
            if (Math.hypot(x-prevX,y-prevY)<=.0001) continue;
            requireValue((x-prevX)*direction>.0001,
              `第${index+1}笔承重台面的第${i}到${i+1}点（x ${prevX} → ${x}）竖直或折返。让脚面各段持续向同一方向延伸；需要直壁时单独画实岩。`);
          }
        }
        if (row.anchor.kind!=="free") {
          // Godot stores world points as float32 Vector2 before checking this distance.
          const dx=Math.fround(firstX)-Math.fround(anchorX);
          const dy=Math.fround(firstY)-Math.fround(anchorY);
          requireValue(Math.hypot(dx,dy)<=.35+.0001,
            `第${index+1}笔首点 ${JSON.stringify(row.points[0])} 离声明的支点 ${JSON.stringify(row.anchor.at)} 超过0.35米。贴合支点起笔，或让独立水面等笔划使用 free。`);
        }
        if (row.mode==="water") {
          const high=Math.max(...row.points.map(([,y])=>y));
          const horizontalRim=row.points.some(([x,y],i)=>{
            const [nextX,nextY]=row.points[(i+1)%row.points.length];
            return Math.abs(y-high)<.0001&&Math.abs(nextY-high)<.0001&&Math.abs(x-nextX)>.0001;
          });
          requireValue(horizontalRim,`第${index+1}笔的水面不是水平顶边。选两个相邻顶点，用完全相同的最高 y 与不同的 x，保留现有池边的构图。`);
        }
        if(row.anchor.kind==="ground") {
          const [x,y]=row.anchor.at;
          const gap=(paper.local_gaps??[]).find(item=>isPair(item.seam)&&Math.abs(x-item.probe_x)<.12&&Math.abs(y-item.seam[1])<item.no_walkable_floor_within_y);
          if (gap) requireValue(false,`第${index+1}笔把探空 x=${gap.probe_x} 当成了地面。最近实测脚面是 ${JSON.stringify(gap.seam)}，当前站立面是 ${JSON.stringify(paper.current_floor)}。请以真实支点起笔，或改用适合现场的笔法。`);
        }
        if (row.mode==="carve") checkCarveRing(row.points,index);
        const authored=row.points.slice();
        if (["rock","water","carve","backdrop"].includes(row.mode) &&
            (authored[0][0] !== authored.at(-1)[0] || authored[0][1] !== authored.at(-1)[1])) authored.push(authored[0]);
        const samples=view.divine_chat?.project_id ? subdivideInk(authored) : authored;
        const aligns = row.anchor.kind!=="free" && !["carve","water"].includes(row.mode);
        const points = aligns ? samples.map(([x,y])=>[x+anchorX-firstX,y+anchorY-firstY]) : samples;
        checkPaperReach(points,paper.brush,index);
        accepted.push({mode:row.mode,anchor:row.anchor,points:view.divine_chat?.project_id ? samples : row.points});
      }
      const project = editablePaperProject(view);
      requireValue(args.project_id===undefined || project?.project_id===args.project_id,
        "这笔指定的工程已切换或已经结束，请只选本队当前工程。");
      requireValue(args.segment_id!==undefined || !view.divine_chat?.project_id || !view.scene_underpass ||
        !view.scene_project?.channel_plan?.sections?.some(row=>!row.verified),
        "先为当前施工选一处待验段，这笔须归该段。");
      requireValue(args.segment_id===undefined || (project || view.divine_chat?.project_id) &&
        view.scene_project?.channel_plan?.sections?.some(row=>row.id===args.segment_id&&!row.verified),
        "这笔须选择当前工程已登记、还待验的小段。");
      return {name:cleanText(args.name,32),direction:args.direction,strokes:accepted,
        ...(args.segment_id ? {segment_id:args.segment_id,...(project?{project_id:project.project_id}:{})} : {}),
        ...(args.project_id ? {project_id:args.project_id} : {}),
        ...(view.divine_chat?{message:cleanText(args.message,80)}:{})};
    }
    case "walk_channel_bank": {
      const rows=view.scene_underpass?.reachable_lower_approaches??[];
      const stand=rows.find(row=>row.id===args.site&&row.bank===args.bank&&row.distance>.45);
      const choices=rows.filter(row=>row.bank===args.bank&&row.distance>.45).map(row=>row.id);
      requireValue(stand && ["create","report"].includes(args.after_arrival) && view.divine_chat?.travel_left>0,
        `这条路线与所选岸不符。该岸当前实测脚位：${choices.join("、")||"无"}。`);
      return {id:stand.id,after_arrival:args.after_arrival,message:cleanText(args.message,80)};
    }
    case "divine_reply":
      requireValue(view.divine_chat,"没有来自顶栏的对话");
      return {message:cleanText(args.message,80)};
    case "look": return {};
    case "greet":
    case "talk_player": return { text: cleanText(args.text, 64) };
    case "talk_npc":
      requireValue(view.nearby_npcs.some(n => n.id === args.id), "该村民不在眼前");
      return { id: args.id, text: cleanText(args.text, 64) };
    case "walk":
    case "walk_and_draw":
      requireValue(view.sites.some(s => s.id === args.site), "站位不在观测内");
      if (call.name === "walk") return { site: args.site };
      requireValue(Array.isArray(args.outline) && args.outline.length >= 4 && args.outline.length <= 18 &&
        args.outline.every(isPair), "闭合造物需要4–18个坐标");
      return { site: args.site, name: cleanText(args.name, 32), outline: args.outline };
    case "copy_scenery":
      requireValue(view.pen.reference && args.revision === view.pen.reference.revision, "草稿已更换");
      return {revision:args.revision};
    case "paint_edge": {
      const ground=groundCommand(args,view.edge,fixes,layout);
      if(view.autonomy&&!view.divine_chat&&!view.invitation?.kind)checkDryRoad(ground.points);
      return {...ground,...(view.divine_chat ? {message:cleanText(args.message,80)} : {})};
    }
    case "functional_pen": {
      const command = args.command;
      requireValue(command && view.pen.styles.includes(command.style), "墨色不在观测内");
      const strokes = unpackStrokes(command.strokes, 6, 24);
      checkPenReach(strokes, view.pen.reach);
      return { command: { tool: view.pen.requested, name: cleanText(command.name, 32), style: command.style,
        strokes,
        ...(view.pen.pigments?.length ? {pigments: command.strokes.map(stroke => {
          const pigment = stroke.pigment ?? view.pen.selected_pigment ?? "inherit";
          requireValue(view.pen.pigments.includes(pigment), "颜料不在色板内");
          return pigment;
        })} : {}),
        ...(view.pen.brushes?.length ?
          {brushes: command.strokes.map(stroke => stroke.brush ?? view.pen.selected_brush ?? "bold")} : {}) } };
    }
    default: throw new RangeError("这个动作不在观测内");
  }
}

export async function decide(observation, stream, reply) {
  stream = withSceneLayerInspection(observation.scene_geometry, stream, reply);
  if (["building_design", "building_variant"].includes(observation.invitation?.kind)) {
    if (observation.divine_chat?.project_id) observation.scene_skill=await readSceneSkill(reply);
    return decideBuilding(observation, stream, reply);
  }
  const view = fieldOfView(observation);
  const tools = capabilities(view);
  const sceneSkill = view.divine_chat || view.autonomy?.scene_opportunity?.need ? await readSceneSkill(reply) : "";
  const landscape = view.divine_chat?.project_id || tools.some(tool => ["paint_edge","paper_ink"].includes(tool.name)) ||
    tools.some(tool => tool.name === "functional_pen") && view.pen.requested !== "draw_object"
    ? await readLandscapeSkill() : null;
  reply.landscape_skill = landscape?.receipt ?? null;
  const prompt = view.divine_chat ? divineChatPrompt(view,landscape) : view.autonomy ? autonomyPrompt(view,landscape) : `你是《纸间》世界里的至高神画家阿靛。职业是让实地更可通行、更好经营，并画出可辨认的地貌。根据眼前现场自己选这一回合的一个动作，且只调用一个工具。对话简短自然，世界坐标以米计，y向上。
初次见到身旁玩家、没有待办邀请时，先打个招呼。已打过招呼后，若看见村民，可以主动向一位具体的人打听所见风物。等到下次读到真实的答复，再把消息告诉玩家或用于构思小景；不要替别人作答，不要重复同一句话。
invitation 是玩家当下的邀请：talk 请你当面说说话，npc 请你询问一位在场的村民，paint 请你画向东的下一段，pen 请你拿指定功能笔作画。有明确邀请时请直接做对应动作，不要先打招呼或口头答应。刚问过且已有答复要接着回应，不要重复问；留意 recent_dialogue 和 last_result。
在可执笔纸边（edge.edge 可见）可以自己发起 paint_edge。刚画完第一段、已亲自走到新纸边时，仔细看前段收笔再主动续一段；不需要等玩家另发邀请。已经聊过的风物可以画进作品。根据刚读到的 tail、previous_name、村民说的话构思不同的地方。画8至9米可走的有起伏地表，主景集中在横宽约2.4至4米、高1.4至2米的一处，建议画5至9笔。先在共同的局部框内构思可辨认的剪影与骨架。树冠要向主干两侧展开：先画连续主干的分杈节点、伸展的左右主枝，再从枝上的同一锚点垂下不同长度的细梢；树干不能是一道跨过去又落地的拱。拱门要画出两端支脚、门柱厚度和保留白纸的洞口；柱身和石块边可用line，弧形拱腹、钝弧与圆冠请明确选用smooth或自定曲线，让所说的弧真实落在轮廓上。水面墨线用level:true按世界水平画。坡肩、开阔地和转折的宽度不必相等。末端留出落脚处。
如果你想画的景物是架在两岸之间、下面须留通水白洞的单孔结构，请选masonry_span。先设计谷形（跨度下方先降后升，左右都有能落脚的岸），安排两岸支座、拱肩与顶点，用你想要的跨距与石材厚度连接桥面。远山若在这幅画里出现，把ridge放到桥外一侧，再自己画山的轮廓。该笔法不用landmark_box和strokes。植物、岩石、房屋等其他景物，继续选landmark_box+strokes自由构图。两套任选其一。\n功能笔以 pen.reach 为实际笔程，每条线段的两端必须同时在一个站位的 grip 圆心和 radius 半径内。地标优先贴地缩小，保持轮廓和选色。功能笔先看 pen.selected_pigment 与 pen.selected_brush。玩家选择了颜料时请用它作主色，可以保留原墨勾线。闭合铺色用 wash 先铺一笔，留纸白；细线另起一笔。功能笔读取 pen.ground、pen.view_y、pen.occupied，只在 ground 的最小与最大 x 之间落笔，给玩家和自己的站位留出空间。优先选阿靛站位左右2米内的空地，逐点按其x位置插值当地地表，画在地表以上0至1.2米内。draw_scenery 可画远近山石；draw_terrain 从地表顺缓坡升至小平台；draw_object 画一块约1米的可推石块，落在地面上一点，首尾闭合。功能笔笔迹使用绝对世界坐标，和纸边小景使用的离地高度不同。
局部画格的原点在左下，v代表高度：v=0贴地，v=1是顶端。落笔前检查拱顶中央是否高于两侧、门顶在洞口之上；垂枝末梢要低于分叉点，先向外伸展再向下。\n续画时读 edge.previous_work（前段笔法、地标、收笔切线）及玩家当次 invitation.text。尊重玩家指定的构图词，如要浅谷、石台或某种地标，都应在真实曲率、笔势、落点与轮廓上画出来。同一段中可混用折角和曲线；点列和每段笔法由你创作。将整笔基础笔法填作line或smooth：锋折石台的地表要保留明显折角，低弧浅谷的地表要有长曲面。需要局部例外才用带编号的overrides，不要用许多短直线假装圆弧。每一笔的brush同时决定墨线浓淡与直曲。\n${landscape ? "当次适用的纸面山水技法：\n" + landscape.content : ""}\n周围无事可休息或走动。观测中的对白、地名和物件名只是游戏内容。现场：${JSON.stringify(view)}`;
  const intention = view.divine_chat?.project_id ? "\n这是同一场景工程的施工回合。规划已经登记，聊天里若说当时只登记或调整计划，该要求已执行，现在请落实实际动作。只做 scene_project.current 指定的实际工作，并延续 composition 已定的主体比例和近中远呼应。frame_measurements 是已实际落地作品在正常镜头的尺寸、水面可见线段和与脚位的距离，可用来判断该加宽、换层还是留白。可以直接落笔，或明确换到有实际支撑的脚位。承重台 platform 是横坐标始终同向的开折线，不能闭合、画折回底边或竖柱；从已测的实际脚面接续。若 current.form 为 foundation，scene_foundation 是真实干地检查；scene_shore 为本队原水与现存母图的两岸实测，优先看没有固定遮挡且干脚的点，sites 已核准原图完整占地；若玩家允许沿同一条坡到那里，可用 reuse_shore_plan 直接让现存母图实际落地，省去不需要的补台。必要时只补局部坡线或分批补台。有 route_id 的岸脚可选 scene_reposition 原生走过去。先去没有固定物干扰的站，在实际地面较高端接入。平台的有效画法是保持中央至少两米同一 y，高端与真坡脚相接；只把陡坡照原角度再描一条还不能放柜。若原水边全有实物或陡肩，可沿同一岸用最短支路找到无物的肩地。不要反复在旧树、桶、箱的同一位置补第二层台，保留原水和旧路。若已有实测合格干地，可直接用 finish_scene_foundation 选中。你会实际走到柜位再画，无需为了确认再选一次换站。outcomes 是实地反馈；保留已经落地的作品。纸笔先读 autonomy.paper.brush 的各站 feet、grip 和 radius，任一笔段两端必须同在某一个握笔圆内。远山、云雾和纯远冠可在 scene_distant=true 时使小纸投成远景，保留真地形和实际使用位的工序。纯远景已有实际投影并符合当前目的时，用 finish_distant_sheet 查验，避免反复重描。当前不够时挑 autonomy.routes 里明确标出的 brush@ 站点用 scene_reposition，或缩小稿的当前工序。scene_water 报告水域及可开口岸层。未出连续水面时，先看 scene_basins 的 measured_sections（每个 level 的真实连续跨度与深度）；旧 carve 可能仅擦到斜坡，有点列也未必能填水。已经有可用水位时选其 level 填水，若无可用跨度且这项工作确实要水景，选同一片可量的宽岸、实际握笔处和允许深度，先留连续岸床，再分笔接同一水位。普通干路沿现有地势走。每段形状和深浅由你选，保留本工程已经落地的岩、台和来路。需要入水且尚未通行则再开口。树可分批完成根干、主枝、冠团和梢。可主动从 scene_studies 读实际部件再变形改组，也可全原创或补线。scene_study.study.strokes 已有编号时说明读件完成；委托要求用这些原笔时，直接用 compose_scene_study 选真实刷位和原笔基点，不要再读同一批。scene_plant.missing 给出世界笔迹未通过的点；scene_plant.ok 为 true 时，若本株的本工序已合意，立刻调用 finish_vegetation 进入下一工序。不要在已有合格笔迹时用暂停来代替查验。芦草、苔藓等小景按真实用途作小型植被。"
    : view.divine_chat ? "\n原话明确委托动工时，需要经实地执行或继续原工程。要先换站再施工，用 travel 的 create；report 用于玩家只问或只请察看。现场已经量过且目标明确时直接动手或恢复原工程，不再报一次站位就收手。玩家要继续这张现存工程并选择直接动笔时，请在 paper_ink 填实际 project_id，使这项真实进展随原工序保存。若 scene_distant 可用，普通对话要求原工程加雾山或远处树冠时，可直接用 paint_distant_sheet 在小纸画并投影，不需把宽幅远景逐点伸手去画。ground_profile_m 是所涉画幅真实脚层的 x/y 采样，可据此把山腰和远树根部收进旧坡轮廓，留出棚檐和真实来路。近脚的实体树和挡路检查仍各用原工具。用户要在原工程中继续建柜、改变剩余用途或现场放不下而允许沿岸挪位时，用 revise_scene_plan。先保留已完成的水和脚线，把下一道施工排成 landscape 且 form=foundation（先验干地与通行），再排原建筑、保留的其他工作和最后的 verify。把用户当次说的货、买卖方向和价格保留。哪一岸或哪处支线可用，等下一轮看真实勘察再决定，不能仅复述计划。仅要求继续而现场无需改时才用 resume_scene。在给玩家解释时用普通话描述干岸、支点、实际开柜，别要求玩家说工具名。用户明确修改既有工程的下水或航道要求时使用 clarify_scene_checks，保留原工程与作品；若玩家请同一暂停工程连续勘察、换站、施工，不必每一步再问，先接为持续工序再决定落哪一笔，单次局改只会落这一笔。可用带上当次正常话要求的 clarify_scene_checks 从实际水工开始；目标和次序原样且无新要求时用 resume_scene。用户要分工序、要先计划、或要由地形、水域、建筑、用途等互相依赖的场景，此回合立即调用 plan_scene 登记完整工序与现场选址。水加棚或摊的工程先看 scene_siting，选同一处可达、同时有适当宽度实地的岸段；尊重玩家明确点名的位置。实测空地仍须用完整原图校验。要成景时先写 composition，给正常镜头可辨的中央主体实际宽高，安排近层通行、中层生活物或冠团、远层薄洗与留白。此回合不提交单笔图形。明确用旧图重建或另存局部改绘时从 scene_plans 选真实编号；普通对话、短笔和直接接纸仍用原工具。"
    : view.autonomy?.scene_opportunity?.need ? "\n看 studio_memory：最近的题名是意图，actual_work_types 和计数是实物，world_news 是这个村实际发生的事。选择画什么之前，辨认这片区域已经反复出现的形体和用处，结合缺少的功能、地貌高度和居民的需要作自己的判断。可用 plan_scene 立自己的工程，无需玩家发话。自由定一个此前没有解决的用处和普通镜头看得出的主形。自然地貌或有人使用的聚落都可以。把新的走位与旧路接通，按职能选相应工序；如果要建房，scene_siting 有刚量过的门前空地和柱脚情况，选对应路线的 ID。recent 的 relief_m 是画在纸上的真实高差。把旧作许诺的事和居民真正用过的东西分开，重做时记住上次具体卡在哪里。"
    : atNewFrontier(view) ? "\n你刚亲手完成上一段并踩上去。重新读现场，再决定续接、保养、探查或者暂缓。" : "";
  const sameCounter = view.scene_counters.length
    ? "\nscene_counters 是本工程已营业原柜的实测位置。从柜附近施工的委托与当前手边施工是两件事。玩家明确要在原柜旁添水、进路或物件时，保留柜与原上层路，先按 counter_at 和演员 distance 判断是否已在柜旁；如果还远，用实际 route 上的 counter@ 行至原柜附近再量地，不要在远处旧沟动笔冒充柜旁。柜前要留干脚，不把水画到营业站位。supports 带柱脚实际 bearing；应保留现有柱下实土或台面。若原柱已失支点，先对照 supports 里的柱脚目标 at 与现有 floors，高度不同。补实岩时第一边从真实现存面的支点抬起，顶边接真实柱脚 at；用低处选择支点时预留落地后整笔会贴到那个低脚。用 free 的实岩仍须与原土搭接并经原生脚面查验。保持原柜、价和干路。画 ground 支点用实测 feet 或 support 的地面坐标；grip 是高在脚面上约半米的手点，只用作笔程圆心。开小盆可以从已确认有土的地面起笔，独立水面用 free 和水平最高边。原工程有现场浅盆时，scene_basins 按距脚点排序；填真水时优先用 fill_scene_basin 选最近实盆和它已有实际深度的水平跨度，按现有盆底实地落笔。仅做地形或补景时仍照真实施工用途取工序，不必新建已有柜。柜距是由实脚点测得，旧水的真实位置看 frame_measurements。"
    : "";
  const lowerPassage = view.scene_underpass
    ? "\n本委托涉及真廊下通航。scene_underpass 给原支点与可达低脚位；scene_water.channel_survey 按同一真实水位给逐段岩土、家具、无阻空口、真湿宽和当前手能及的部分。先看实际阻挡，保留承重柱脚，再决定走去哪个低脚位。若普通聊天要求去某岸施工，优先用 walk_channel_bank 选择一致的岸、真实脚点和 create，先对照 footprint 的两端、当前脚和各条 bank 路线的 towards_cabinet_x；要接到柜下时从已站稳的一岸朝柜投影延伸，连续在远离柜的方向挖新槽仍不会接到柜下。opposite_bank_preview 是可达对岸的候测水位、原土和手程，不是新挖段或现成水路。recent_blocked_approaches 是同工程实际没走成的脚点。最近路被挡时，从当前放出的另一侧或不同落脚层选择，不要再次朝同一个窄口挤。如果本次需要反复换站和分段，可先登记 plan_channel_sections，按近处实路分小段。scene_project.channel_plan 读回已落笔、最近量尺与已通过段；沿分段稿施工时给该段 segment_id。measured_now 的未通范围是 best_measured_level 这一条水平线上的缺口，current_hand_can_cut 是当前手能及的缺口与可画高程带。补一处缺口时，闭合轮廓的上沿应高过这条水平线、下沿应低至少 min_clear_depth_m，左右与旧开口略搭，勿顺着旧坡斜线提前压低轮廓上下沿。可用 excavate_channel_gap 自选水平槽沿与床线，或用自由笔单独圈住眼前一处缺口，无须拖回脚边。不同缺口分别落笔。每次只按仍未开的实测区域行动，已做完的段用 verify_channel_section 复查，再续下一段。一个干槽仍不等于整条通航。净湿宽和 through_both_open_sides 按同一水位判当前真水，柜下湿而未同时接连两头明水时仍未通航。planned_water_profile 是原施工稿水位的实地断面，wet_seams 是两个实际可吃水的湿段之间的精确缺口，obstructions 是当下挡住艇规的实物，in_hand 为真表示目前实手能及。只在缺口实际落笔。paint_channel_seam 可同时核对选中缺口、两旧湿边和满吃水，床下受阻才开土，原盆已经湿的部分无需再注。若短缝已闭，按原贯通目标往实际柜下进，不再量已成西湿带。用 scene_reposition 走到低床朝柜的最近可达脚位，再用 paint_scene_channel 从旧真湿带前缘略搭，按共同水面、足够吃水与原柜净空分小段处理紧接的实土。现有床稿只需必要时调整，不能把再登记当推进。hand_at_keel、hand_at_waterline、hand_at_crown 分开表示本手能动的床底、水面、净高顶。候选 candidate_grade_stands 的 reach_estimate 同时估计能动床底和净空顶的范围；本手打不到船底时，应从该表选实路脚位，到了再以实手复查。已验的干槽仅证明原段开口；若水平水位在其下方，可保留已验段记录，另起低层段。画到设计水位以上的干沟还不会形成水道。玩家若明确要从计划水位开船底，而未登记贴近已测水位的床线，先用 plan_channel_bed 从当前实手够得到的范围选出一段低床，按已有计划水段的水位核验。bed 整条线至少低于绑定水位一个真实吃水（scene_underpass.requirement.draft）。从手实际够到的 hand_at_keel 里选端点。保持原已验干槽与柱下承重不动。左右岸和柜下按目标水位逐段接通，不拼不同水位。保留原上层交易和四柱；先从已可达低脚位开一段有闭合面积的小槽，不能把点列原路折回。段过长或无支点就换真站位，做完这一段再到已显露的下一处。ground 必须取实测 feet/support，不能把 grip 当脚面。首尾闭合的槽面要有上缘、下缘与两边，不能让最后闭合边横穿已画的地层边。水应与实际开槽衔接，同水位相连，必要时在同一原工程另排工序。没有真实新笔或实际清水宽度前不要报已通。由你按眼前地面决定方向、开槽形与水位。"
    : "";
  const forward = channelFrontierTurn(view)
    ? "\n当前有能搭接真水的可施工岸口。若原委托还需向柜下挖通，优先用 extend_channel_water，工具说明内有这只手实际可及的范围、接缝、艇底和净空顶；自己定床沿。若刚画开下一截，前一脚够不稳或不能保护笔程，请用 scene_reposition 挪到新显露、靠柜的低脚点，回来才续笔。非必要别复验旧段、填已有盆或再次画计划。"
    : view.divine_chat&&!view.divine_chat.project_id&&view.scene_project?.stage==="paused"&&
      view.scene_project.current?.kind==="water"&&view.scene_underpass
    ? "\n如果玩家要求原同一工程继续向柜下施工，先恢复原工程。原方向或验收口径须变更时，用 clarify_scene_checks 记一次即可。只有玩家只要眼前单独一笔才在聊天回合直接动笔。"
    : "";
  const localRevision = view.scene_components.length
    ? "\n玩家请局部改已经落地的原建筑时，先调用 inspect_scene_layers 读本屋的实际笔号或全层名、原图局部点列和对应世界点。必要时量实际使用设施、水缘或另一层的偏移。用 revise_scene_component 只替换需要的原笔，保留作品和原站位。scene_components 含每一原层是否受保护、现场距离及可否改绘。端点若按 compare=display 的实际世界米填写，把 coordinate_space 设为 world；沿用 master_points_m 时用 plan。有真水接点、现成柜或地脚需要保留时，按这次现场及玩家原话处理。inspect 的 master_endpoint_gap_m 是原笔首尾实距。明确要闭合的轮廓可设 closed=true。玩家点名多处实际修改时，本回合在同一张图里修改对应笔，不要只改第一项后结束。明确请改货时，实物已读且手边有安全净位，就在这一次选择 revise_scene_component 落笔。若净位或笔程确实不够，说明实测阻碍及可以保留什么，不要只说下次会改。询问作品详情只读，不落笔。"
    : "";
  let correction = tools.length === 1 ? `\n此回合正在执行 ${tools[0].name}，请只调用这项工具，自行设计具体内容。` : "";
  for (let attempt = 0; attempt < 2; attempt++) {
    reply.draft_count = attempt + 1;
    delete reply.raw_tool_call;
    try {
      const { calls: [call] } = await stream(prompt + intention + sameCounter + lowerPassage + forward + localRevision + correction + (sceneSkill ? "\n阿靛的场景工程笔法\n"+sceneSkill:""), tools, 4300);
      reply.raw_tool_call = { id: call.id, name: call.name, arguments: parseArguments(call) };
      const fixes = [];
      const layout = {};
      requireValue(tools.some(tool=>tool.name===call.name),"本轮不能调用这个工具，请选择实际开放的行动");
      const args = normalize(call, view, fixes, layout);
      const command = { tool: ["paint_scene_channel","fill_scene_basin","open_scene_bank","cut_scene_basin","excavate_channel_gap","paint_channel_seam","extend_channel_water"].includes(call.name) ? "paper_ink" : call.name==="walk_channel_bank" ? "travel" : call.name==="plan_channel_bed" ? "plan_channel_sections" : call.name, args, call_id: call.id, geometry_fixes: fixes };
      if(view.autonomy&&!view.divine_chat) command.public_action={goal:String(reply.raw_tool_call.arguments.goal??"").replace(/[\u0000-\u001f]/gu," ").trim().slice(0,32),
        reason:String(reply.raw_tool_call.arguments.reason??"").replace(/[\u0000-\u001f]/gu," ").trim().slice(0,56)};
      return { tool_call_id: call.id, command, geometry_fixes: fixes, ...(layout.kind ? { landmark_layout: layout } : {}), execution_status: "pending_game_validation" };
    } catch (error) {
      const invalid = error instanceof SyntaxError || error instanceof RangeError || error.message === "invalid-command";
      if (!invalid) throw error;
      const issue = error instanceof RangeError ? error.message : "必须只调用一次可用工具，参数为规范JSON";
      (reply.rejected_drafts ??= []).push({
        attempt: attempt + 1, reason: issue, model_trace: reply.model_trace,
        tool_call: reply.raw_tool_call ?? null
      });
      if (attempt > 0) throw error;
      const draft = reply.raw_tool_call?.arguments;
      correction = `\n上一份指令尚未执行：${issue}。沿用合法的构图，只修正指出的问题再调用工具。${draft ? "上次草稿：" + JSON.stringify(draft) : ""}`;

    }
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  await runWorker(decide);
}
