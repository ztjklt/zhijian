import { expandCurveMark, withCurveGeometry } from "./paper_curve.mjs";
import { buildingStudyCatalogue, expandBuildingStudyGroup } from "./building_studies.mjs";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";

const kinds = ["landscape", "water", "vegetation", "building", "verify"];
const label = { type: "string", minLength: 1, maxLength: 56 };
const point = { type: "array", minItems: 2, maxItems: 2, items: { type: "number" } };
const record = properties => ({ type: "object", properties, required: Object.keys(properties), additionalProperties: false });
const pigments = ["inherit","ochre","cinnabar","indigo","malachite"];
const washes = ["wash","wash_pool"];
const brushes = ["bold","fine",...washes];
function finishPhases(entries,need,clean) {
  return entries.map((entry,index)=>{
    const beforeFinal=index<entries.length-1;
    const survey=beforeFinal && entry.kind==="verify" && entry.form==="foundation";
    need(!beforeFinal || entry.kind!=="verify" || survey,"开工勘地用 foundation；完工实走 verify 只放最后。");
    return {kind:survey?"landscape":entry.kind,aim:clean(entry.aim,56),
      form:entry.kind==="verify"&&!survey?"":entry.form??""};
  });
}

const plantParts = ["root","trunk","branch","crown_light","crown_shadow","twig","ground"];

export async function readSceneSkill(reply) {
  const path = "tools/skills/paper-scene/SKILL.md";
  const data = await readFile(new URL("./skills/paper-scene/SKILL.md", import.meta.url));
  reply.scene_skill = { path, bytes:data.length, sha256:createHash("sha256").update(data).digest("hex") };
  const villagePath = "tools/skills/paper-scene/references/village-cluster.md";
  const village = await readFile(new URL("./skills/paper-scene/references/village-cluster.md", import.meta.url));
  reply.scene_skill.references = [{path:villagePath, bytes:village.length, sha256:createHash("sha256").update(village).digest("hex")}];
  return data.toString("utf8") + "\n\n" + village.toString("utf8");
}

function channelSections(view) {
  return view.scene_project?.channel_plan?.sections??[];
}

function channelFrontiers(view) {
  const grade=view.scene_water?.channel_survey?.planned_water_profile;
  const passage=view.scene_underpass;
  const brush=view.autonomy?.paper?.brush;
  if(!grade||!passage||!brush?.grounded||!grade.wet_clear.length) return [];
  const centre=(passage.footprint[0]+passage.footprint[1])*.5;
  const faceTowardCabinet=brush.feet[0]<centre ? 1 : -1;
  const reach=[];
  for(const a of grade.hand_at_keel)
    for(const b of grade.hand_at_crown)
      for(const c of grade.hand_at_waterline) {
        const low=Math.max(a[0],b[0],c[0]);
        const high=Math.min(a[1],b[1],c[1]);
        if(high-low>.12)reach.push([low,high]);
      }
  const options=[];
  for(const wet of grade.wet_clear){
    const edge=faceTowardCabinet>0 ? wet[1] : wet[0];
    for(const [low,high] of reach){
      const limits=faceTowardCabinet>0
        ? [Math.max(low,wet[0],edge-.24),Math.min(high,edge+2)]
        : [Math.max(low,edge-2),Math.min(high,wet[1],edge+.24)];
      limits[0]=Math.ceil((limits[0]+.012)*100)/100;
      limits[1]=Math.floor((limits[1]-.012)*100)/100;
      if(limits[0]>edge-.015||limits[1]<edge+.015||
        (faceTowardCabinet>0 ? limits[1]-edge : edge-limits[0])<.12)continue;
      options.push({wet_edge_x:edge,limits,level:grade.level,keel:grade.level-passage.requirement.draft,
        crown:grade.level+passage.requirement.headroom,direction:faceTowardCabinet>0?"east":"west"});
    }
  }
  return options.slice(0,4);
}

export function channelFrontierTurn(view) {
  return view.divine_chat?.project_id && view.scene_project?.current?.kind==="water" &&
    channelFrontiers(view).length>0;
}

function offerChannelSections(view,offer) {
  const scene=view.scene_project;
  if(!view.divine_chat || !["paused","working"].includes(scene?.stage) ||
    !["landscape","water","verify"].includes(scene.current?.kind)) return;
  const sections=channelSections(view);
  const row=record({kind:{type:"string",enum:["excavate","water"]},name:label,from:point,to:point,
    bed:{type:"array",minItems:2,maxItems:8,items:point},
    preserve:{type:"string",description:"本段施工要避开的原柱、岸、道路或需保留的其他实物。"}});
  row.properties.id={type:"string",enum:sections.filter(section=>!section.verified).map(section=>section.id),
    description:"修订某个已有未通过的小段才填写；新段省略。已完成的画笔和实测仍保留。"};
  if(!row.properties.id.enum.length) delete row.properties.id;
  row.properties.level={type:"number",description:"普通水段的计划水位，为已登记水位开配套干槽时用 grade_for_water。"};
  const grade=view.scene_water?.channel_survey?.planned_water_profile;
  const seams=(grade?.wet_seams??[]).map((seam,index)=>({...seam,index})).filter(seam=>seam.in_hand);
  if(scene.current.kind==="water"&&seams.length)
    offer("paint_channel_seam","在已量到的两笔同高真水之间接一小段原水。用同一水平水面，自己选左、右两端和整个床底；两端与现水略搭，床底留足实际吃水。若该处仍挡实土，选必要的开口顶部，保原柱和上路。",{
      seam:{type:"integer",enum:seams.map(row=>row.index),description:"当前 wet_seams 的零基编号"},
      bed:{type:"array",minItems:2,maxItems:8,items:point,description:"按横坐标从左往右的世界米床底，所有点都低于该缝 keel。"},
      cut_top:{type:"number",description:"若需先开土，填实际需开口的顶部高度，再随原水面进同一笔组；能直接接水时省略。"},
      title:label,message:label
    });
  const fronts=scene.current.kind==="water"?channelFrontiers(view):[];
  if(fronts.length&&view.divine_chat.project_id)
    offer("extend_channel_water","用原船道的同一水位向原柜下推进一小段。选当前实手可及的真湿端，自己决定下一段宽度、床底和上沿。自动用自由笔构成闭合槽和水平真水；保留原路和柱脚，由现场验通。可施工的端点范围："+JSON.stringify(fronts),{
      frontier:{type:"integer",enum:fronts.map((_,i)=>i),description:"这条工具说明中现场可施工端点的零基号。"},
      bed:{type:"array",minItems:2,maxItems:8,items:point,description:"从左往右的世界米床底；整条低于 keel，一端贴回当前真湿水，另一端朝柜方向开新地。"},
      cut_top:{type:"number",description:"水平开槽顶的世界高度，至少达到 crown，仅切当前所需空间。"},
      title:label,message:label
    });
  if(grade?.hand_at_keel?.length)
    offer("plan_channel_bed","给已登记的水道选一段实手可及的船底。目标水位 "+grade.level+
      " 米，吃水 "+view.scene_underpass.requirement.draft+" 米；使用 planned_water_profile.hand_at_keel 选择两端。保留高层已完成笔迹，此处只登记低层床图。",{
      bed:{type:"array",minItems:2,maxItems:8,items:point,description:"床底的绝对米坐标，横向从左向右。两端决定这一小段实挖范围，各点低过目标水位与吃水。"},
      title:label,preserve:label
    });
  offer("plan_channel_sections","为当前浅溪、船槽或灌渠登记分段施工稿。拟定每段实际起止、床底折线和已测水位，谈清保留什么；只存计划，不落笔。可改未通过段，已验段保留。",{
    sections:{type:"array",minItems:1,maxItems:8,items:row},
    start:{type:"boolean",description:"玩家明确要现在动工时用 true；只请规划用 false。"}
  });
  const incompleteCuts=sections.filter(section=>section.kind==="excavate"&&!section.verified&&
    section.measured_now?.current_hand_can_cut?.length);
  if(incompleteCuts.length&&["landscape","water"].includes(scene.current.kind))
    offer("excavate_channel_gap","补一处当前实手可及的同层缺口。自行选已登记挖槽段、实际床底点与水平上沿；由笔生成闭合槽壁。床线的起止横坐标就是左右壁，和原空口略搭即可。只挖槽，勿报通水。",{
      section:{type:"string",enum:incompleteCuts.map(section=>section.id)},
      open_top:{type:"number",description:"高于该段当前实测 best_measured_level 至少 0.015 米。"},
      bed:{type:"array",minItems:2,maxItems:8,items:point,description:"从左向右严格递增的实地床底米坐标。首尾两点皆要低过该实测标高至少 min_clear_depth_m。"},
      title:label,message:label
    });
  const built=sections.filter(section=>section.work_ids?.length && (
    (section.verified && !view.divine_chat.project_id) || (!section.verified && !section.measurement) ||
    (!section.verified && section.measured_now && section.measurement.clear_span_m!==section.measured_now.clear_span_m) ||
    (!section.verified && (section.measurement?.work_count??section.work_ids.length)!==section.work_ids.length)));
  if(built.length)offer("verify_channel_section","按现时地层验这一段。后来落笔改变地层时也可复验已验段。未达标会撤回该段通过并保留实际笔迹。",{id:{type:"string",enum:built.map(section=>section.id)}});
}

export function sceneTools(view, offer) {
  const scene = view.scene_project;
  const running = view.divine_chat?.project_id;
  offerChannelSections(view,offer);
  const ownedFrames=(view.scene_distant_frames??[]).filter(row=>row.in_range);
  if(view.divine_chat&&ownedFrames.length)
    offer("reframe_distant_sheet","挪动或缩放阿靛自己在本队已经画完的一张远景纸。原纸、笔号、作者和地形都沿用，原位不会再留一份。只在玩家要求或当前工序需要重摆已有远景时用。",{
      work_id:{type:"string",enum:ownedFrames.map(row=>row.work_id)},
      origin:{...point,description:"新画幅左下的世界米坐标，y向上。"},
      size:{...point,description:"新宽高，宽1–20米，高0.2–10米。"}
    });
  const washFrames=ownedFrames.filter(frame=>frame.wash_strokes?.length);
  if(view.divine_chat&&washFrames.length)
    offer("revise_distant_wash","在原远景纸上局部改淡墨，不重画、不挪画幅。以 wash_strokes 的原笔号选需要变化的闭合色面，mist 将山腰或雾的下缘渐隐进纸，wash 留完整平洗。留住未选笔、原位置与颜料。已经选择原纸且玩家明确请现在改淡时直接动笔。可改原纸和现用笔法："+JSON.stringify(washFrames.map(({work_id,name,wash_strokes})=>({work_id,name,wash_strokes}))),{
      work_id:{type:"string",enum:washFrames.map(frame=>frame.work_id)},
      edits:{type:"array",minItems:1,maxItems:16,items:record({
        index:{type:"integer",minimum:0,description:"同一远景原纸的原笔号，从0开始。"},
        brush:{type:"string",enum:["mist","wash"]}
      })}
    });
  const phase=record({kind:{type:"string",enum:kinds},aim:label});
  phase.properties.form={type:"string",enum:["tree","small_detail","distant","scenery","foundation"],
    description:"开工量地用 kind=landscape、form=foundation，verify 只填在最后走已经做好的门面。为待建建筑找干地或多批画承重基础用 foundation，验实地后才推进。纯远景用 distant，近处非承重标记用 scenery。同一株树用一个 tree 工序分批；芦草、苔藓等用 small_detail。"};
  if (!running) {
    if(view.scene_distant&&["working","paused"].includes(scene?.stage))
      offerDistantSheet(offer,(view.scene_study??view.scene_plant)?.study);
    const plan = {
      title:label, site:{type:"string",enum:["here",...(view.autonomy?.routes??[]).filter(s=>Number.isFinite(s.stand?.[1])).map(s=>s.id)]},
      phases:{type:"array",minItems:2,maxItems:6,items:phase},
      trade:{type:"boolean",description:"原话明确要求摊位成交或能做交易才为 true，计划须包含 building 和 verify。"}
    };
    const siting = view.scene_siting?.some(row => row.nearest_water !== undefined) ? "现场已量出门位的宽度。nearest_water 给到真水的横距和高差，水可能在桥下。adjacent_sites 列出分别可从当前脚点到达的独立门位；门间路线、柜和水能否相接，按实际落笔和走位复核。" : "";
    offer("plan_scene","为需要跨多个真实工序的场景建立长工程。可以围绕一件本队旧作品补绘，保留原地表、旧笔及原作者。" + siting,plan);
    const schema=view.scene_revisions?.map(work=>work.id)??[];
    plan.composition={...record({
      focus:label,width_m:{type:"number",minimum:.7,maximum:14},height_m:{type:"number",minimum:.25,maximum:4},
      foreground:label,middle:label,background:label
    }),description:"较大山水或聚落先构图。填地标实际宽高和三个深度层的用途，留白可写保留现有纸面。"};
    plan.subject={type:"string",enum:["",...schema],description:"明确改旧作时填写实际作品 ID；新作填空串。"};
    plan.water_access={type:"boolean",description:"要求玩家从实际旧路能涉水、下到水边时为 true。"};
    plan.water_body={...record({
      kind:{type:"string",enum:["pond","stream"]},purpose:label,
      left:{type:"number"},right:{type:"number"},level:{type:"number"}
    }),description:"自行开工的水景先定一段连续的世界米岸区、同一水位和真实用途。展示宽至少2.4米（常规镜头约144像素）。干路、实地入口和两岸可以分笔施工。无水景的工程省略。"};
    plan.boat={type:"boolean",description:"只在委托明确要求船能够从建筑下面或穿过一段通行时为 true。浅水、泊岸、系柱的普通要求填 false。"};
    if (!view.divine_chat) return;
    if (["paused","working"].includes(scene?.stage) && ["landscape","water","verify"].includes(scene.current?.kind))
      offerSceneBasinFill(offer,(view.scene_basins??[]).filter(basin=>waterLevels(basin).length));
    if(["paused","working"].includes(scene?.stage))
      offer("revise_scene_plan","接受玩家明确提出的原工程改法。只重排未通过的工序，已有地貌与图纸留在原工程。",{
        remaining:{type:"array",minItems:1,maxItems:6,items:phase},message:label});
    if (scene?.stage==="paused") offer("resume_scene","继续本队暂停的工程，保留已有地貌和图纸。",{});
    if(["paused","working","awaiting_trade"].includes(scene?.stage))
      offer("clarify_scene_checks","玩家明确要求改变现有工程的通水或步入水面条件时，只更新该工程的查验目标并从相关工序继续。原作全部保留。",{
        boat:{type:"boolean"},water_access:{type:"boolean"},phase:{type:"integer",minimum:0,maximum:scene.phases.length-1},message:label
      });
    const editable=(view.scene_components??[]).filter(item=>item.editable&&item.layers.some(layer=>!layer.protected));
    if(editable.length) {
      const replacement={brush:{type:"string",enum:brushes},pigment:{type:"string",enum:pigments},
        points:{type:"array",minItems:2,maxItems:32,items:point,description:"y 向上，统一使用 coordinate_space。plan 是母图原点的局部米，world 是读层给的世界米。"}};
      const mark=(address)=>{
        const schema=record({...address,...replacement});
        schema.properties.closed={type:"boolean",description:"这一笔明确要成为连续闭合轮廓时设 true，末点会接回首点。开放线填 false 或省略。"};
        return withCurveGeometry(schema).anyOf;
      };
      const books=buildingStudyCatalogue();
      const ids={type:"array",minItems:1,maxItems:8,items:{type:"integer",minimum:0},uniqueItems:true};
      const group=(selector)=>{
        const reference=record({study:{type:"string",enum:books.map(page=>page.study)},...selector,layer:label,origin:point});
        Object.assign(reference.properties,{scale:point,mirror_x:{type:"boolean"},pigment:{type:"string",enum:["source",...pigments]}});
        return record({indices:{...ids,description:"原屋要换的0基笔号，取件插在选中的第一笔。"},reference});
      };
      const revision={
        work_id:{type:"string",enum:editable.map(item=>item.work_id)},
        replace:{type:"array",minItems:1,maxItems:8,items:{anyOf:[
          ...mark({index:{type:"integer",minimum:0}}),
          ...mark({layer:{type:"string",description:"照录本屋完整且唯一的实际图层名，同名用原笔号。"}}),
          group({strokes:ids}), group({part:label})
        ]}}
      };
      offer("revise_scene_component","在当前实际建筑上改部分已有墨迹。先用 inspect_scene_layers 读原件与参照层，再按玩家所说用途选笔。原物编号、承重、实际台柜和站位保留，另存母图。可用 indices+reference 整组取代局部，保留出处；选建筑参考书原笔号或部件名，共用原点、倍率及镜像。最多换8笔、落8笔。书页部件和0基原笔号："+books.map(p=>p.study+" "+[...p.groups.map(g=>g.layer+g.first+"–"+g.last),...Object.keys(p.parts??{})].join("/")).join("；")+"。自由笔每个原笔号出一条笔线；同原笔号、同起点、同笔色的开放短枝可合成一条沿原枝返回的笔线。",revision);
      revision.coordinate_space={type:"string",enum:["plan","world"],description:"所有替换笔统一坐标系。沿 compare=display 给出的世界位置构图时填 world；使用母图局部点时填 plan，可省略。不得混用。"};
    }
    const spots=(view.scene_components??[]).filter(w=>w.editable)
      .flatMap(w=>(w.use_positions??[]).flatMap(s=>s.options.map(o=>o.id)));
    if(spots.length)offer("revise_scene_access","玩家要调整原建筑的等候或工作位置时，按 scene_components.use_positions 的旧位、实测新脚点、棚内或露天选择。阿靛会亲自试走，成功后另存母图并在同一实物更新这一处。原柜照常营业。保留遮雨若做不到，说明原因；玩家可另选露天等候。",{
      site:{type:"string",enum:spots}, use:{...label,description:"改后这处站位的用途，保留原来的工作内容。"}
    });
    const plans=view.scene_plans??[];
    if(plans.length){
      const plan={type:"integer",enum:plans.map(p=>p.id)};
      offer("reuse_scene_plan","在阿靛自己能施工的实地照录本队旧建筑图纸并实际施工。",{plan});
      offer("redraw_scene_plan","以本队指定母图另存局部改绘，保持母图与已经建成的建筑。",{plan});
    }
    return;
  }
  const plantReady=scene?.current?.kind==="vegetation"&&view.scene_plant?.ok;
  if(!plantReady)offer("pause_scene","只有当前地图确无可施工的脚点或显式暂停时使用；写清具体阻碍。工程仍保留。",{reason:label});
  switch (scene?.current?.kind) {
    case "water": {
      const fillable=(view.scene_basins??[]).filter(basin => basin.measured_sections===undefined ||
        waterLevels(basin).length>0);
      const fullWater=view.scene_water?.water_body?.target;
      if(!fullWater&&view.scene_water?.basins?.length&&!view.scene_water?.mouths?.length)
        offer("cut_scene_basin","在一个真实可握笔的岸段挖窄浅盆。自己选哪段、深度和谷底偏向，先开一处，下一回合再填水平水。",{
          site:{type:"string",enum:view.scene_water.basins.map(s=>s.id)},depth:{type:"number",minimum:.18,maximum:.52,description:"不超过所选区段的 max_depth；较深的中心给连续水面留实深。"},
          bottom_position:{type:"number",minimum:.35,maximum:.65},title:label,message:label
        });
      if(view.scene_water?.mouths?.length) {
        offer("open_scene_bank","已有真实浅水被旧地表盖住。按选中水段，从实测口岸高度向下去掉窄幅薄盖，保留既有盆底、水位和口外坡线。上一次窄口未能通行时，用视图中较宽的原湾并顺接缓口。",{
          mouth:{type:"string",enum:view.scene_water.mouths.map(m=>m.id)},
          message:label
        });
        if(!fullWater)break;
      }
      offerSceneBasinFill(offer,fillable);
      offer("paint_scene_channel","画一段真实池面或溪水。自己给下凹底部的绝对米制点列、水平水位和开挖线，原生合成闭合开槽与水笔。"+(fullWater?"这是同一水景的分段，贴着已开的 bed_spans / wet_spans 接着走，按预定岸区与水位落笔。整片水由实际连通的水面验收。":""),{
        title:label, level:{type:"number"}, open_top:{type:"number"},
        bed:{type:"array",minItems:3,maxItems:9,items:point},message:label
      });
      break;
    }
    case "landscape":
    case "vegetation": {
      const isPlant=scene.current.kind==="vegetation";
      const isFoundation=scene.current.form==="foundation";
      const channelWork=!isPlant&&view.scene_underpass&&channelSections(view).some(section=>!section.verified);
      const shoreSites=(view.scene_shore?.plan_id??-1)>=0?view.scene_shore.sites??[]:[];
      if(!channelWork&&scene.current.form==="foundation"&&scene.phases?.[scene.cursor+1]?.kind==="building"&&shoreSites.length)
        offer("reuse_shore_plan","沿用本工程已有母图。选择已核对全幅柱脚、来客站位和实路的岸脚。会用原图去现场施工一次，不会删除旧稿、原水或旧物。",{
          site:{type:"string",enum:shoreSites.map(site=>site.site_id)}
        });
      const foundations=(view.scene_foundation??[]).filter(site=>site.frontage?.level_site_clear);
      if(!channelWork&&scene.current.form==="foundation"&&foundations.length){
        offer("finish_scene_foundation","当前候选已经核实两米净空、干脚和通行。选择有实体支撑的站位，查验成功后进入建筑。",{
          site:{type:"string",enum:foundations.map(site=>site.id)}
        });
      }
      const onlyDistant=scene.current.form==="distant" && view.scene_distant;
      const prior=view.scene_plant;
      const kind={type:"string",enum:[prior?.kind||prior?.expected||"tree",...(!prior?.kind&&!prior?.expected?["small_detail"]:[])]};
      const role={type:"string",enum:plantParts};
      const row={brush:{type:"string",enum:brushes},pigment:{type:"string",enum:pigments},
        points:{type:"array",minItems:2,maxItems:24,items:point}};
      if(isPlant)row.part=role;
      const canMark=(prior?.batches??0)<(prior?.batch_limit??8);
      if(!onlyDistant&&(isPlant?canMark:Boolean(scene.subject)||scene.current.form==="scenery"))
        offer("paint_scene_detail","原创一批真实景物笔迹。可先画贴地根干和分枝，下一批再画同株冠团，落笔本身不会结束植被工序。",{
          title:label,marks:{type:"array",minItems:1,maxItems:16,items:record(row)},...(isPlant?{plant_kind:kind}:{})
        });
      if(prior?.ok)offer("finish_vegetation","用游戏实测已达到的接地、外轮廓和冠团证据结束当前植被。",{});
      if (isFoundation) break;
      const studies=view.scene_studies??[];
      const studyTurn=view.scene_study??prior;
      if (view.scene_study_index?.catalog_total) offer("search_scene_studies","在本世界公共笔谱按图名、作者、部件检索。空串表示不限；可填图页原编号单独列部件。翻页沿用检索条件，offset 用 next_offset，part_offset 用该图的 next_part_offset。结果在下一次现场观察里。",{
        name:{type:"string",maxLength:160,description:"图名片段或完整 work_id"},
        author:{type:"string",maxLength:80,description:"作者名字或 author_id"},
        part:{type:"string",maxLength:100,description:"部件名片段，如轮辐、垂枝；查全稿可填整页"},
        offset:{type:"integer",minimum:0},part_offset:{type:"integer",minimum:0}
      });
      if((studyTurn?.reads??0)<(studyTurn?.limit??5)&&studies.some(s=>s.parts.length))
        offer("read_scene_study","主动查看一个公共纸页部件。只读取选中的真实笔号和点列，未作画。",{
          work:{type:"string",enum:studies.map(r=>r.work_id)},part:{type:"string",enum:[...new Set(studies.flatMap(r=>r.parts.map(p=>p.id)))]},
          offset:{type:"integer",minimum:0,description:"首读填0；部件超过24笔时，通过 next_offset 看另批原笔。"}
        });
      const study=studyTurn?.study;
      if(view.scene_distant) {
        offerDistantSheet(offer,study);
        if(scene.current.form==="distant"&&scene.distant_ids?.length)
          offer("finish_distant_sheet","当前工序已经有实际远景原稿。若画幅与视野已达到本工序的用途，用此项核对既有投影并推进，不另花墨。");
      }
      if(!onlyDistant&&(!isPlant||canMark)&&study?.strokes?.length){
        const index={type:"integer",enum:study.strokes.map(s=>s.stroke)};
        const supports=studyStands(view);
        offer("compose_scene_study","将已读部件选笔、缩放/镜像/换色后重组。各笔仍由你在现场落笔，可在下一批补原创。",{
          title:label,site:{type:"string",enum:["manual",...supports.map(s=>s.id)],
            description:"ground 模式可选择已量过的实地 brush@ 脚点。其它支点类型仍使用明确给出的实际 origin。"},
          origin:{...point,description:"手选的世界米制落点。free 下填写选中的真正枝端或物件落点，保留实际高度。"},
          pivot_stroke:{type:"integer",enum:[-1,...study.strokes.map(s=>s.stroke)],
            description:"贴地可用所选原笔第一点做原稿基点。自由变形时填 -1 使用 pivot。"},
          pivot:{...point,description:"原页局部坐标。pivot_stroke 指定时使用那笔第一点，无需抄写。"},
          scale:point,mirror_x:{type:"boolean"},...(isPlant?{plant_kind:kind}:{}),
          support_kind:{type:"string",enum:["free","ground","wall","hanging"]},
          selection:{type:"array",minItems:1,maxItems:5,items:record({stroke:index,pigment:{type:"string",enum:pigments},...(isPlant?{part:role}:{})})}
        });
      }
      break;
    }
    case "verify":
      offer("verify_scene","请原生导航实际从连续旧路试走到工程使用位；移动和抵达由游戏判断。", {});
      if((scene.reworks??0)<2 && scene.outcomes?.at(-1)?.ok===false)
        offer("rework_scene","已有工程未通过实地查验，返回一个具体工序修复；已存作品和母图保留。",{
          phase:{type:"integer",minimum:0,maximum:scene.cursor-1}
        });
      break;
  }
  if (!plantReady && (scene?.moves??0)<2 && ["landscape","water","vegetation"].includes(scene?.current?.kind)) {
    const stations=(view.autonomy?.routes??[]).filter(s=>Number.isFinite(s.stand?.[1])&&s.distance>(s.id?.startsWith("underpass@")?.42:.8)&&s.distance<=(["shore@","counter@"].some(prefix=>s.id?.startsWith(prefix))?28:18));
    if(stations.length)offer("scene_reposition","先走去有实地支撑的另一脚位，当前工序和已落笔保留。找柜前干地时选空地的岸脚，别在曾失败或有箱、树及通道的同一小段反复换站。",{
      site:{type:"string",enum:stations.map(s=>s.id)}
    });
  }
}

function offerSceneBasinFill(offer, basins) {
  if (!basins.length) return;
  const levels=[...new Set(basins.flatMap(basin=>waterLevels(basin).map(row=>row.level)))];
  offer("fill_scene_basin","沿用本工程已挖好的盆，选该盆实测有连续开口的水平水位，保留原盆底和岸脚。",{
    basin:{type:"string",enum:basins.map(basin=>basin.id)},
    level:levels.length?{type:"number",enum:levels,description:"先选盆，再用该盆实际给出的某一水位。"}:{type:"number"},
    title:label,message:label
  });
}

function waterLevels(basin) {
  return (basin.measured_sections??[]).flatMap(row=>{
    const span=(row.spans??[]).filter(part=>part.right-part.left>=.38&&part.depth>=.085)
      .sort((a,b)=>(b.right-b.left)-(a.right-a.left))[0];
    return span&&Number.isFinite(row.level)?[{level:row.level,span}]:[];
  });
}

export function buildBasinWater(geometry,level,openSpan,need=(ok,message)=>{
  if(!ok)throw new RangeError(message);
}) {
  need(Array.isArray(geometry)&&geometry.length>=3&&geometry.every(p=>Array.isArray(p)&&p.length===2&&p.every(Number.isFinite))&&Number.isFinite(level), "浅盆的实际轮廓或水位无效。");
  const same=(a,b)=>Math.hypot(a[0]-b[0],a[1]-b[1])<1e-5;
  let ring=geometry.slice();
  if(same(ring[0],ring.at(-1)))ring.pop();
  const clip=(points,axis,edge,sign)=>{
    const out=[];
    for(let i=0;i<points.length;i++){
      const a=points[i], b=points[(i+1)%points.length];
      const outsideA=sign*(a[axis]-edge)>0, outsideB=sign*(b[axis]-edge)>0;
      if(!outsideA)out.push(a);
      if(outsideA!==outsideB){
        const t=(edge-a[axis])/(b[axis]-a[axis]);
        const p=[a[0]+(b[0]-a[0])*t,a[1]+(b[1]-a[1])*t];
        p[axis]=edge;
        out.push(p);
      }
    }
    const distinct=out.filter((point,i)=>i===0||!same(point,out[i-1]));
    if(distinct.length>1&&same(distinct[0],distinct.at(-1)))distinct.pop();
    return distinct;
  };
  ring=clip(ring,1,level,1);
  if(openSpan){
    ring=clip(ring,0,openSpan.left,-1);
    ring=clip(ring,0,openSpan.right,1);
  }
  const lineWidth=ring.reduce((max,a,i)=>{
    const b=ring[(i+1)%ring.length];
    return Math.abs(a[1]-level)<1e-5&&Math.abs(b[1]-level)<1e-5?Math.max(max,Math.abs(a[0]-b[0])):max;
  },0);
  const depth=level-Math.min(...ring.map(p=>p[1]));
  need(ring.length>=3&&lineWidth>=.30&&depth>=.075,
    `盆里这处水平开口只有 ${lineWidth.toFixed(2)} 米，深 ${Math.max(0,depth).toFixed(2)} 米。请用另一个测定水位或就近开真浅盆。`);
  return [...ring,ring[0]];
}

const distantBrushes = ["bold","fine","wash","mist"];

function offerDistantSheet(offer,study) {
  const unit={type:"array",minItems:2,maxItems:2,items:{type:"number",minimum:0,maximum:1}};
  const stroke=record({brush:{type:"string",enum:distantBrushes,description:"远山可用 mist，由峰顶到画幅底缘渐淡留纸。"},pigment:{type:"string",enum:pigments},
    points:{type:"array",minItems:2,maxItems:96,items:unit,description:"薄洗和雾色沿轮廓依次给顶点，末边自动接回首点，细线和浓线保持开放。"}});
  const source=study?.strokes?.length?{
    picked:{type:"array",maxItems:8,items:record({stroke:{type:"integer",enum:study.strokes.map(s=>s.stroke)},
      pigment:{type:"string",enum:pigments}})},
    box:{type:"array",minItems:4,maxItems:4,items:{type:"number",minimum:0,maximum:1},
      description:"已读部件投到小纸的左、下、宽、高。picked为空时不使用。"},
    mirror_x:{type:"boolean"}
  }:{};
  offer("paint_distant_sheet","在手边的小纸亲手构图，再以它的原稿比例投到不承重的远景。适合山影、天空、云线及远冠；可选已读原笔，再加原创。这里不会形成道路、水域、服务站或可触树干。",{
    title:label,origin:{...point,description:"预定远景左下角的实际世界米，y 向上。"},
    size:{...point,description:"投影宽1–20米、高0.2–10米。构图中点在本人16米内。"},
    original:{type:"array",maxItems:12,items:stroke},...source,
    finish:{type:"boolean",description:"只有当前明确是纯远景且本层最后一批时填true，真水和实体工序照原工具。"}
  });
}

function distantDraft(args,view,need,clean) {
  need(view.scene_distant&&["landscape","vegetation"].includes(view.scene_project?.current?.kind),
    "当前必须是可以铺远景的工程工序");
  const xy=p=>Array.isArray(p)&&p.length===2&&p.every(Number.isFinite);
  const inside=p=>xy(p)&&p.every(n=>n>=0&&n<=1);
  const {origin,size}=args;
  need(xy(origin)&&xy(size)&&size[0]>=1&&size[0]<=20&&size[1]>=.2&&size[1]<=10,
    "远景原点用实际世界米，宽1–20米、高0.2–10米");
  need(Math.hypot(origin[0]+size[0]/2-view.self[0],origin[1]+size[1]/2-view.self[1])<=16,
    "请移动到能看到该画面的地方，远景构图中点须在本人16米内");
  const strokes=[];
  const picked=args.picked??[];
  const original=args.original??[];
  need(Array.isArray(picked)&&Array.isArray(original)&&picked.length+original.length>=1&&picked.length+original.length<=12,
    "可把远景分成多批，一批需1至12笔");
  if(picked.length){
    const study=(view.scene_study??view.scene_plant)?.study;
    const box=args.box;
    need(study?.strokes?.length&&Array.isArray(box)&&box.length===4&&box.every(Number.isFinite)&&
      box[0]>=0&&box[1]>=0&&box[2]>0&&box[3]>0&&box[0]+box[2]<=1&&box[1]+box[3]<=1,
      "从已读部件选原笔，并给小纸内的局部框");
    const [left,bottom,width,height]=study.bounds;
    const seen=new Set();
    for(const row of picked){
      const source=study.strokes.find(s=>s.stroke===row.stroke);
      need(source&&!seen.has(row.stroke)&&pigments.includes(row.pigment),"使用已读的实际原笔号和公共颜料");
      const local=(v,base,range)=>range>1e-6?Math.min(1,Math.max(0,(v-base)/range)):.5;
      const points=source.points.map(([x,y])=>{
        const u=local(x,left,width),v=local(y,bottom,height);
        return [box[0]+box[2]*(args.mirror_x?1-u:u),box[1]+box[3]*v];
      });
      strokes.push({points,brush:source.brush,pigment:row.pigment,source_work_id:study.work,source_stroke:source.stroke});
      seen.add(row.stroke);
    }
  }
  for(const row of original){
    need(distantBrushes.includes(row.brush)&&pigments.includes(row.pigment)&&Array.isArray(row.points)&&
      row.points.length>=2&&row.points.length<=96&&row.points.every(inside),
      "原创远景的点在小纸0–1内，使用公共笔刷和色板");
    strokes.push({points:row.points,brush:row.brush,pigment:row.pigment});
  }
  for (const [index, stroke] of strokes.entries()) {
    if (!washes.includes(stroke.brush) && stroke.brush !== "mist") continue;
    const points = stroke.points;
    // Like the native sheet, include the last-to-first edge without changing the artist's UVs.
    const twiceArea = points.reduce((sum, [x, y], i) => {
      const [nextX, nextY] = points[(i + 1) % points.length];
      return sum + x * nextY - nextX * y;
    }, 0);
    need(points.length >= 3 && Math.abs(twiceArea) > Number.EPSILON * points.length,
      `远景第 ${index + 1} 笔铺色需要有面积的轮廓，沿边依次给点。`);
  }
  const direct=!view.divine_chat?.project_id;
  need(!direct||["working","paused"].includes(view.scene_project?.stage),"请先选本队要补远景的原工程。");
  return {name:clean(args.title,40),origin,size,strokes,finish:!direct&&args.finish===true,
    ...(direct?{project_id:view.scene_project.project_id}:{})};
}

function studyStands(view) {
  const brush=view.autonomy?.paper?.brush;
  return (brush?.stations??[]).map(row=>({
    id:row.current?"brush-current":`brush@${row.feet[0].toFixed(2)},${row.feet[1].toFixed(2)}`,
    feet:row.current&&brush.support?.length===2?brush.support:row.feet
  }));
}

export function sceneCommand(name,args,view,need,clean) {
  const scene=view.scene_project;
  switch (name) {
    case "plan_channel_bed": {
      const grade=view.scene_water?.channel_survey?.planned_water_profile;
      const bed=args.bed;
      need(grade&&Array.isArray(bed)&&bed.length>=2,"没有可核的计划水位和床线。");
      const same=channelSections(view).find(row=>row.grade_for_water===grade.section_id&&JSON.stringify(row.bed)===JSON.stringify(bed));
      need(!same,`同一水尺下这份床图已登记为 ${same?.id}，可继续落笔、验槽或填水。`);
      return sceneCommand("plan_channel_sections",{sections:[{kind:"excavate",name:args.title,
        from:bed[0],to:bed.at(-1),bed,preserve:args.preserve,grade_for_water:grade.section_id}],start:false},view,need,clean);
    }
    case "plan_channel_sections": {
      need(["paused","working"].includes(scene?.stage) && ["landscape","water","verify"].includes(scene.current?.kind) &&
        Array.isArray(args.sections) && args.sections.length>0 && args.sections.length<=8,"沿当前本队工程作一至八道局部计划");
      const pair=at=>Array.isArray(at)&&at.length===2&&at.every(Number.isFinite);
      const editing=new Set();
      const sections=args.sections.map(row=>{
        need(row && ["excavate","water"].includes(row.kind)&&pair(row.from)&&pair(row.to)&&Array.isArray(row.bed)&&
          row.bed.length>=2&&row.bed.length<=8&&row.bed.every(pair)&&typeof row.preserve==="string"&&
          (row.kind!=="water"||Number.isFinite(row.level)),"用世界米写两端、实际床形、保留物及水段水平水位");
        if(row.kind==="water") need(row.bed.every(([,y])=>y<=row.level-.055),
          `「${row.name}」有计划床底高于拟定水面。水笔须给每处至少 0.055 米深度；先按实测分段挖下、改水位或把待挖段登记为干槽。`);
        const grade=view.scene_water?.channel_survey?.planned_water_profile;
        const draft=view.scene_underpass?.requirement?.draft;
        const gradeLinked=row.grade_for_water!==undefined;
        if(gradeLinked){
          need(row.kind==="excavate"&&grade?.section_id===row.grade_for_water&&Number.isFinite(draft)&&Number.isFinite(grade.level),
            "只可为本工程已量过的水段开配套干槽。");
          need(row.bed.every(([,y])=>y<=grade.level-draft+1e-6),
            `这条床线须低过实测水位 ${grade.level} 米和吃水 ${draft} 米，勿沿用高层干槽的高度。`);
          need(grade.hand_at_keel.some(([a,b])=>row.bed.every(([x])=>x>=a&&x<=b)),
            "先到低处站稳，使全部床点都落在本手够得到的吃水线范围内。");
        }
        const id=row.id??"";
        need(!id || (!editing.has(id)&&channelSections(view).some(section=>section.id===id&&!section.verified)),
          "已通过的原段不能覆盖；只选一个正确的待改段。");
        if(id)editing.add(id);
        return {id,kind:row.kind,name:clean(row.name,40),from:row.from,to:row.to,bed:row.bed,preserve:row.preserve.slice(0,100),
          ...(gradeLinked?{level:grade.level,grade_for_water:row.grade_for_water}:
            Number.isFinite(row.level)?{level:row.level}:{})};
      });
      return {sections,start:args.start===true};
    }
    case "excavate_channel_gap": {
      const section=channelSections(view).find(row=>row.id===args.section&&row.kind==="excavate"&&!row.verified);
      const measured=section?.measured_now;
      const level=measured?.best_measured_level;
      const {bed,open_top:top}=args;
      need(["landscape","water"].includes(scene?.current?.kind)&&measured?.current_hand_can_cut?.length&&
        Number.isFinite(level)&&Number.isFinite(top)&&top>=level+.015,"选一段实手可补的缺口，上沿要在该段当前实测高度以上。");
      need(Array.isArray(bed)&&bed.length>=2&&bed.length<=8&&bed.every((p,i)=>
        Array.isArray(p)&&p.length===2&&p.every(Number.isFinite)&&
        (i===0||p[0]>bed[i-1][0])&&p[1]<=level-measured.min_clear_depth_m),
        "床点须严格从左向右，整条床沿包括两端都低过当前实测高度。");
      const left=bed[0][0],right=bed.at(-1)[0];
      need(measured.current_hand_can_cut.some(({span:[a,b]})=>Math.min(right,b)-Math.max(left,a)>=.015),
        "请让这笔与一处实手可补的缺口重合。");
      const start=[left,top];
      const points=[start,[right,top],...bed.slice().reverse(),start];
      return {name:clean(args.title,40),direction:"down",message:clean(args.message,56),segment_id:section.id,
        ...(view.divine_chat?.project_id ? {} : {project_id:scene.project_id}),
        strokes:[{mode:"carve",anchor:{kind:"free",at:start},points}]};
    }
    case "verify_channel_section":
      need(channelSections(view).some(row=>row.id===args.id&&row.work_ids?.length),"该段还没有已落地的有效笔迹");
      return {id:args.id};
    case "plan_scene": {
      const id=args.site;
      need(id==="here" || view.autonomy?.routes.some(row=>row.id===id && Number.isFinite(row.stand?.[1])),
        "工程选址必须使用当前观测中的站点");
      need(Array.isArray(args.phases) && args.phases.length>=2 && args.phases.length<=6 &&
        args.phases.every(p=>kinds.includes(p?.kind)) && args.phases.at(-1).kind==="verify",
        "工程需要2至6个工序，最后一项为 verify 实走复核");
      const trade=args.trade===true;
      need(!trade || args.phases.some(p=>p.kind==="building"),"实际交易需要先建有使用位的摊铺");
      const subject=args.subject??"";
      need(subject==="" || view.scene_revisions?.some(w=>w.id===subject),"改绘对象须来自本队现有作品");
      const boat=args.boat===true;
      need(!boat||["water","building"].every(k=>args.phases.some(p=>p.kind===k)),"给吊脚建筑留船道须先画真实水道并核下层净空");
      let waterBody;
      const hasWater=args.phases.some(phase=>phase.kind==="water");
      const selfDirected=Boolean(view.autonomy&&!view.divine_chat);
      if((hasWater&&selfDirected)||args.water_body!==undefined){
        const body=args.water_body;
        const at=id==="here"?view.autonomy?.paper?.brush?.feet??view.self:view.autonomy?.routes.find(row=>row.id===id)?.stand;
        need(hasWater&&body&&["pond","stream"].includes(body.kind)&&
          [body.left,body.right,body.level].every(Number.isFinite)&&body.right-body.left>=2.4&&
          body.right-body.left<=20&&at&&Math.abs((body.left+body.right)/2-at[0])<=10&&
          Math.abs(body.level-at[1])<=5,
          "自定水景先选一处近可信脚位的同岸范围、水平水位和用途，给主水体至少2.4米。干路、石坪和村落可按原计划走，不要混入零碎水坑。");
        waterBody={kind:body.kind,purpose:clean(body.purpose,56),left:body.left,right:body.right,level:body.level};
      }
      let composition;
      if(args.composition) {
        const {width_m:width,height_m:height}=args.composition;
        need(Number.isFinite(width)&&width>=.7&&width<=14&&Number.isFinite(height)&&height>=.25&&height<=4,
          "构图需写能在正常镜头复看的真实主体宽、高");
        composition={width_m:width,height_m:height};
        for(const layer of ["focus","foreground","middle","background"])composition[layer]=clean(args.composition[layer],56);
      }
      return {title:clean(args.title,40),site:id,trade,boat,water_access:args.water_access===true,subject,...(composition?{composition}:{}),...(waterBody?{water_body:waterBody}:{}),phases:finishPhases(args.phases,need,clean)};
    }
    case "revise_scene_plan": {
      need(!view.divine_chat?.project_id&&["working","paused"].includes(scene?.stage)&&Array.isArray(args.remaining)&&
        args.remaining.length>=1&&args.remaining.length+scene.cursor<=8&&args.remaining.every(p=>kinds.includes(p?.kind))&&args.remaining.at(-1).kind==="verify",
        "只修改在做的原工程，从当前未过工序起，最后保留实地查验");
      return {remaining:finishPhases(args.remaining,need,clean),message:clean(args.message,56)};
    }
    case "resume_scene":
    case "verify_scene":
    case "finish_vegetation":
    case "finish_distant_sheet":
      return {};
    case "search_scene_studies": {
      need(view.scene_study_index?.catalog_total>0,"当前没有本队可检索的图页");
      for (const [key,max] of [["name",160],["author",80],["part",100]])
        need(typeof args[key]==="string"&&args[key].length<=max,"检索条件需使用简短文字");
      for (const key of ["offset","part_offset"])
        need(Number.isSafeInteger(args[key])&&args[key]>=0&&args[key]<=2147483647,"请使用目录给出的页起点");
      return {name:args.name.trim(),author:args.author.trim(),part:args.part.trim(),offset:args.offset,part_offset:args.part_offset};
    }
    case "read_scene_study":
      need(view.scene_studies?.some(r=>r.work_id===args.work&&r.parts.some(p=>p.id===args.part)),"只可读取本世界公开的指定部件");
      need(args.offset===undefined||Number.isInteger(args.offset)&&args.offset>=0&&args.offset<(view.scene_studies.find(r=>r.work_id===args.work).parts.find(p=>p.id===args.part).count??Number.MAX_SAFE_INTEGER),"部件读页起点必须有效");
      const prior=(view.scene_study??view.scene_plant)?.study;
      need(!prior?.strokes?.length||args.work!==prior.work||args.part!==prior.part||(args.offset??0)!==(prior.offset??0),
        "当前部件和原笔已经可见。请从这批笔中调用 compose_scene_study 实际变形落笔，或选择确有用途的另一部件");
      return {work:args.work,part:args.part,offset:args.offset??0};
    case "compose_scene_study": {
      const study=(view.scene_study??view.scene_plant)?.study;
      const planted=scene?.current?.kind==="vegetation";
      need(study&&Array.isArray(args.selection)&&args.selection.length>=1&&args.selection.length<=5,"先读一件公开部件，再选原始笔号");
      const pointOk=p=>Array.isArray(p)&&p.length===2&&p.every(Number.isFinite);
      const stands=studyStands(view);
      const selectedSite=stands.find(row=>row.id===args.site);
      const origin=args.support_kind==="ground"?(selectedSite?.feet??args.origin):args.origin;
      const pivotChoice=study.strokes.find(row=>row.stroke===args.pivot_stroke);
      const pivot=pivotChoice?.points?.[0]??args.pivot;
      need(pointOk(origin)&&pointOk(pivot)&&pointOk(args.scale)&&args.scale.every(n=>n>0),
        "部件原点、局部支点和缩放须是现场可用值");
      if (args.support_kind==="ground"&&stands.length) {
        need(stands.some(row=>Math.hypot(origin[0]-row.feet[0],origin[1]-row.feet[1])<.8),
          `origin 是实际世界坐标。请选择实地脚点：${JSON.stringify(stands)}`);
      }
      const order=[], colors={}, roles=[];
      for(const row of args.selection){
        need(study.strokes.some(s=>s.stroke===row.stroke)&&!order.includes(row.stroke)&&pigments.includes(row.pigment)&&(!planted||plantParts.includes(row.part)),
          "所选的部件笔号、换色及实际用途须对应");
        order.push(row.stroke);colors[String(row.stroke)]=row.pigment;roles.push(row.part);
      }
      if (args.support_kind==="ground"||args.support_kind==="wall"||args.support_kind==="hanging") {
        const starts=study.strokes.filter(row=>order.includes(row.stroke)).map(row=>({stroke:row.stroke,start:row.points?.[0]}));
        need(starts.some(row=>row.start?.every((n,i)=>Math.abs(n-pivot[i])<.0001)),
          `贴合请以本批实际选中原笔第一点作为原稿基点，填 pivot_stroke。候选原点 ${JSON.stringify(starts)}`);
      }
      return {work:study.work,part:study.part,...(planted?{plant:{kind:args.plant_kind,roles}}:{}),
        spec:{name:clean(args.title,40),strokes:order,origin,pivot,scale:args.scale,mirror_x:args.mirror_x===true,pigments:colors,
          support_kind:args.support_kind??"free"}};
    }
    case "clarify_scene_checks":
      need(!view.divine_chat?.project_id&&["paused","working","awaiting_trade"].includes(scene?.stage)&&
        Number.isInteger(args.phase)&&["water","verify"].includes(scene.phases[args.phase]?.kind),
        "只有玩家新说明能调整现工程，续作工序须为原浅水或实际复核");
      need(typeof args.boat==="boolean"&&typeof args.water_access==="boolean",
        "明确玩家这次要求的通船与下水查验");
      return {phase:args.phase,boat:args.boat,water_access:args.water_access,message:clean(args.message,56)};
    case "cut_scene_basin": {
      const chosen=view.scene_water?.basins?.find(row=>row.id===args.site);
      need(scene?.current?.kind==="water"&&chosen,"请选现场给出的短盆区段");
      need(Number.isFinite(args.depth)&&args.depth>=(chosen.bed_reference===undefined?.12:.18)&&args.depth<=chosen.max_depth,
        `该可握笔段深度最多 ${chosen.max_depth} 米`);
      const position=args.bottom_position;
      need(Number.isFinite(position)&&position>=.35&&position<=.65,"谷底偏向以共同区段的 0.35–0.65 为范围");
      const [left,,right]=chosen.samples, open=chosen.open_top;
      const low=(chosen.bed_reference??Math.min(...chosen.samples.map(p=>p[1])))-args.depth;
      const x=left[0]+(right[0]-left[0])*position;
      const points=[[left[0],open],[right[0],open],[right[0],right[1]-.04],[x,low],[left[0],left[1]-.04],[left[0],open]];
      return {name:clean(args.title,40),direction:"down",cut_basin:true,message:clean(args.message,56),
        strokes:[{mode:"carve",anchor:{kind:"free",at:points[0]},points}]};
    }
    case "open_scene_bank": {
      const mouth=view.scene_water?.mouths?.find(row=>row.id===args.mouth);
      need(scene?.current?.kind==="water"&&mouth,"应选已测出被岸盖住且可动笔的浅水段");
      const [left,right]=mouth.span;
      const ramp=mouth.ramp_mouth?0.23:0.02;
      const lip=mouth.cover[0]-.015;
      const points=[[left-ramp,mouth.cut_top],[right+ramp,mouth.cut_top],[right+ramp,lip],
        [right,mouth.cut_bottom],[left,mouth.cut_bottom],[left-ramp,lip],[left-ramp,mouth.cut_top]];
      return {name:"浅湾岸口",direction:"down",opened_bank:true,message:clean(args.message,56),strokes:[{mode:"carve",anchor:{kind:"free",at:points[0]},points}]};
    }
    case "pause_scene":
      return {reason:clean(args.reason,56)};
    case "extend_channel_water": {
      const frontier=channelFrontiers(view)[args.frontier];
      need(scene?.current?.kind==="water"&&Number.isInteger(args.frontier)&&frontier,
        "请先选当前实手够到、确实连着原水的岸口。");
      const {bed,cut_top:top}=args;
      const {level,keel,crown,wet_edge_x:edge,limits:[a,b],direction}=frontier;
      need(Array.isArray(bed)&&bed.length>=2&&bed.length<=8&&bed.every((p,i)=>
        Array.isArray(p)&&p.length===2&&p.every(Number.isFinite)&&p[0]>=a&&p[0]<=b&&
        p[1]<=keel-.002&&p[1]>=keel-.22&&(i===0||bed[i-1][0]<p[0])),
        `床点须自西向东，横坐标 [${a.toFixed(3)},${b.toFixed(3)}]，高度在艇底 ${keel.toFixed(3)} 稍下方。`);
      // Allow the wet endpoint to be given as the measured edge rounded to centimetres.
      // Extend only that endpoint onto already wet ground to avoid a dry seam at the joint.
      const joined=bed.map(p=>p.slice());
      const end=direction==="east" ? joined[0] : joined.at(-1);
      if(Math.abs(end[0]-edge)<=.01)
        end[0]=direction==="east" ? Math.max(a,edge-.022) : Math.min(b,edge+.022);
      const left=joined[0][0],right=joined.at(-1)[0];
      need(direction==="east"?left<=edge-.015&&right>=edge+.12:right>=edge+.015&&left<=edge-.12,
        `从现有水边 ${edge.toFixed(3)} 米略搭旧水，再沿 ${direction==="east"?"东":"西"} 至少向实地推进0.12米。`);
      need(Number.isFinite(top)&&top>=crown-1e-5&&top<=crown+.08,
        `净空顶至少 ${crown.toFixed(3)} 米，只切所需的上沿。`);
      const loop=y=>[[left,y],[right,y],...joined.slice().reverse(),[left,y]];
      return {name:clean(args.title,40),direction,message:clean(args.message,56),measured_channel:true,
        strokes:[{mode:"carve",anchor:{kind:"free",at:[left,top]},points:loop(top)},
          {mode:"water",anchor:{kind:"free",at:[left,level]},points:loop(level)}],
        ...(view.divine_chat?.project_id?{}:{project_id:scene.project_id})};
    }
    case "paint_channel_seam": {
      const seam=view.scene_water?.channel_survey?.planned_water_profile?.wet_seams?.[args.seam];
      need(scene?.current?.kind==="water"&&Number.isInteger(args.seam)&&seam?.in_hand,
        "请从当前实手够得到的两个真湿段之间选接缝。");
      const {bed,cut_top:top}=args;
      need(Array.isArray(bed)&&bed.length>=2&&bed.length<=8&&bed.every((p,i)=>
        Array.isArray(p)&&p.length===2&&p.every(Number.isFinite)&&p[1]<=seam.keel&&
        (i===0||bed[i-1][0]<p[0])),
        `床底从左到右，并且每点都要低于艇底 ${seam.keel.toFixed(3)} 米。`);
      const [left,right]=[bed[0][0],bed.at(-1)[0]];
      const [a,b]=seam.span;
      need(left<=a-.005&&left>=a-.34&&right>=b+.005&&right<=b+.34,
        "床底两端需略盖过真正缝隙的左右边缘，借原湿边搭接，别重画整盆。");
      need(top===undefined?!seam.obstructions?.length:Number.isFinite(top)&&top>=seam.level+.015&&top<=seam.level+1.5,
        "这里有实土时先开一小段，顶部需高于目标水位；已有实空即可只接水。");
      const loop=y=>[[left,y],[right,y],...bed.slice().reverse(),[left,y]];
      const strokes=[];
      if(top!==undefined)strokes.push({mode:"carve",anchor:{kind:"free",at:[left,top]},points:loop(top)});
      strokes.push({mode:"water",anchor:{kind:"free",at:[left,seam.level]},points:loop(seam.level)});
      return {name:clean(args.title,40),direction:"down",strokes,message:clean(args.message,56),measured_channel:true,
        ...(view.divine_chat?.project_id?{}:{project_id:scene.project_id})};
    }
    case "fill_scene_basin":{
      const basin=view.scene_basins?.find(b=>b.id===args.basin);
      const level=args.level;
      need(basin && Number.isFinite(level),"从已挖好的真实盆选一个实际水位");
      const section=waterLevels(basin).find(row=>Math.abs(row.level-level)<=.002);
      need(basin.measured_sections===undefined||section,
        `所选水位没有可连续填水的开口。这个盆测出的可用水位是 ${waterLevels(basin).map(row=>row.level).join("、")||"无"}。`);
      const profile=view.scene_water?.channel_survey?.planned_water_profile;
      if(section&&profile&&Math.abs(profile.level-level)<=.002){
        const [left,right]=section.span;
        need(!profile.wet_clear.some(([a,b])=>a<=left+.002&&b>=right-.002),
          `这盆在 ${level} 米已有实水覆盖 [${left.toFixed(3)}, ${right.toFixed(3)}]。再次注满盆不会接缝，请看 wet_seams 和两端实土，选尚缺的一小段。`);
      }
      const points=buildBasinWater(basin.points,section?.level??level,section?.span,need);
      return {name:clean(args.title,40),direction:"down",message:clean(args.message,56),
        ...(view.divine_chat?.project_id ? {} : {project_id:scene.project_id}),
        strokes:[{mode:"water",anchor:{kind:"free",at:points[0]},points}]};
    }
    case "paint_scene_channel": {
      const {bed,level,open_top:top}=args;
      const grade=view.scene_water?.channel_survey?.planned_water_profile;
      const gauge=view.scene_underpass?.requirement;
      const draft=grade&&gauge ? gauge.draft : .1;
      const maxTop=grade&&gauge ? gauge.headroom+.08 : 1.25;
      need(scene?.current?.kind==="water"&&Array.isArray(bed)&&bed.length>=3&&bed.length<=9&&Number.isFinite(level)&&
        Number.isFinite(top)&&top>=level+.08&&top<=level+maxTop,"浅溪需明确一个水平水位和开口线");
      if(grade&&gauge)need(Math.abs(grade.level-level)<=.002,
        `原船道需接到实测水位 ${grade.level.toFixed(3)} 米。`);
      let last=-Infinity;
      for(const p of bed){
        need(Array.isArray(p)&&p.length===2&&p.every(Number.isFinite)&&p[0]>last&&p[1]<=level-draft+1e-6&&p[1]>=level-2,
          "床底点从左向右排，全部在真实水面以下");
        last=p[0];
      }
      const left=bed[0][0],right=bed.at(-1)[0];
      need(right-left>=(grade&&gauge ? .32 : .6)&&right-left<=3.5,
        grade&&gauge?"单次施工宽 0.32 至 3.5 米，必须在实地笔程内。":"单次只挖 0.6 至 3.5 米，可分段");
      const loop=y=>[[left,y],[right,y],...bed.slice().reverse(),[left,y]];
      return {name:clean(args.title,40),direction:"down",message:clean(args.message,56),
        strokes:[{mode:"carve",anchor:{kind:"free",at:[left,top]},points:loop(top)},
          {mode:"water",anchor:{kind:"free",at:[left,level]},points:loop(level)}]};
    }
    case "rework_scene":
      need(Number.isInteger(args.phase)&&args.phase>=0&&args.phase<scene.cursor&&(scene.reworks??0)<2,"须选一个已施工且可修订的工序");
      return {phase:args.phase};
    case "reuse_shore_plan": {
      const site=(view.scene_shore?.plan_id??-1)>=0?view.scene_shore?.sites?.find(site=>site.site_id===args.site):null;
      need(scene?.current?.form==="foundation" && site,
        "原图复用必须选实测确实能立柱、可站立且能到的岸位");
      return {stand:site.stand};
    }
    case "finish_scene_foundation":
      need(scene?.current?.form==="foundation" &&
        view.scene_foundation?.some(site=>site.id===args.site&&site.frontage?.level_site_clear),
        "必须选择当前真地形上已量过的干地脚点");
      return {site:args.site};
    case "scene_reposition": {
      need(view.divine_chat?.project_id && view.autonomy?.routes.some(s=>s.id===args.site&&Number.isFinite(s.stand?.[1])&&s.distance>(s.id?.startsWith("underpass@")?.42:.8)&&s.distance<=(["shore@","counter@"].some(prefix=>s.id?.startsWith(prefix))?28:18)),
        "换站须选当前观测中可到的近处脚面");
      return {site:args.site};
    }
    case "revise_scene_access": {
      for(const work of view.scene_components??[]) {
        if(!work.editable)continue;
        for(const station of work.use_positions??[]) {
          if(station.options.some(option=>option.id===args.site))return {work_id:work.work_id,site:args.site,use:clean(args.use,48)};
        }
      }
      need(false,"请选择本次实勘的原建筑和使用位。");
      break;
    }
    case "revise_scene_component": {
      const work=view.scene_components?.find(item=>item.editable&&item.work_id===args.work_id);
      need(work && Array.isArray(args.replace) && args.replace.length>0 && args.replace.length<=8,
        "请先选本次实际可改的建筑，再改1至8笔已有墨迹");
      const space=args.coordinate_space??"plan";
      need(["plan","world"].includes(space) &&
        (space==="plan" || (Array.isArray(work.origin_world) && work.origin_world.length===2 && work.origin_world.every(Number.isFinite))),
        "请声明用原母图局部米 plan 或当前现场的世界米 world。");
      const desired=new Map();
      const reserved=new Set();
      const groups=[];
      let groupCount=0;
      const samePoint=(a,b)=>a[0]===b[0] && a[1]===b[1];
      for(const input of args.replace){
        if(input?.reference){
          need(Object.keys(input).every(key=>key==="indices"||key==="reference"),
            "同一替换项须选择组笔或自由画，不能同时交原图引用和自画点列。可在一次修稿的不同项各用一种。");
          need(Array.isArray(input.indices)&&input.indices.length>0&&input.indices.length<=8,"请用实际原笔号选要更换的墨迹");
          for(const i of input.indices){
            need(Number.isInteger(i)&&work.layers.some(m=>m.index===i&&!m.protected)&&!reserved.has(i)&&!desired.has(i),"原笔不存在、重复或承担支撑/设施");
            reserved.add(i);
          }
          const reference={...input.reference};
          const selected=expandBuildingStudyGroup(reference);
          groupCount+=selected.length;
          if(space==="world")reference.origin=reference.origin.map((v,i)=>v-work.origin_world[i]);
          groups.push({indices:input.indices,reference});
          continue;
        }
        const row=expandCurveMark(input);
        const candidates=work.layers.filter(mark=>Number.isInteger(row?.index)?mark.index===row.index:typeof row?.layer==="string"&&mark.name===row.layer);
        need(candidates.length===1,"这笔找不到唯一对应的原层，同名请用实际原笔号");
        const mark=candidates[0];
        need(!reserved.has(mark.index),"原笔已被这次的另一组取件选中");
        need(!mark.protected,`第 ${mark.index} 笔承担保留构件，不能替换`);
        need(brushes.includes(row.brush) && pigments.includes(row.pigment) && Array.isArray(row.points) &&
          row.points.length>=2 && row.points.length<=32 && row.points.every(p=>Array.isArray(p) && p.length===2 && p.every(Number.isFinite)),
          "每个替换笔用真实色板和2至32个原图局部米坐标");
        need(row.closed===undefined || typeof row.closed==="boolean","closed 是可选布尔值");
        const points=space==="world" ? row.points.map(([x,y])=>[x-work.origin_world[0],y-work.origin_world[1]]) : row.points.slice();
        if (row.closed && !samePoint(points[0],points.at(-1))) points.push(points[0]);
        const open=!samePoint(points[0],points.at(-1)) && !washes.includes(row.brush);
        const prior=desired.get(mark.index);
        if (prior) {
          const compatible=open && prior.open && row.brush===prior.brush && row.pigment===prior.pigment &&
            samePoint(points[0],prior.branch[0]);
          need(compatible,`第 ${mark.index} 笔有重复替换。请写成一笔，或给同笔色、同起点的开放短枝。`);
          prior.points.push(...prior.branch.slice(0,-1).reverse(),...points.slice(1));
          prior.branch=points;
        } else {
          desired.set(mark.index,{index:mark.index,brush:row.brush,pigment:row.pigment,points:points.slice(),branch:points,open});
        }
      }
      const replace=[...desired.values()].map(({index,brush,pigment,points})=>{
        need(points.length<=32,"整理成连续笔后最多32点，请合并重复点");
        return {index,brush,pigment,points};
      });
      need(reserved.size+replace.length<=8 && groupCount+replace.length<=8,"每次最多取代8笔、落8笔，请减少选笔");
      return {work_id:work.work_id,replace:[...replace,...groups]};
    }
    case "reuse_scene_plan":
    case "redraw_scene_plan":
      need(Number.isInteger(args.plan) && view.scene_plans?.some(p=>p.id===args.plan),"图纸必须来自本队实际目录");
      return {plan:args.plan};
    case "revise_distant_wash": {
      const frame=view.scene_distant_frames?.find(row=>row.work_id===args.work_id&&row.in_range);
      need(view.divine_chat&&frame?.wash_strokes?.length,"请选择当前可及的本人远景原纸。");
      const {edits}=args;
      need(Array.isArray(edits)&&edits.length>=1&&edits.length<=16,"每次改1至16笔远景闭合色面。");
      const seen=new Set();
      const replacements=edits.map(edit=>{
        const previous=frame.wash_strokes.find(mark=>mark.index===edit?.index);
        need(previous&&!seen.has(edit.index)&&["mist","wash"].includes(edit.brush),
          "请选择 wash_strokes 中未重复的原笔号，改作渐隐 mist 或完整淡洗 wash。");
        seen.add(edit.index);
        return {index:edit.index,brush:edit.brush,previous:previous.brush};
      });
      const changed=replacements.filter(row=>row.brush!==row.previous).map(({index,brush})=>({index,brush}));
      need(changed.length>0,"这些原笔已用所选笔法；请选择真正要改的一笔。");
      return {team_id:frame.team_id,world_id:frame.world_id,work_id:frame.work_id,
        expected_revision:frame.revision,edits:changed};
    }
    case "reframe_distant_sheet": {
      const frame=view.scene_distant_frames?.find(row=>row.work_id===args.work_id&&row.in_range);
      const {origin,size}=args;
      const pair=value=>Array.isArray(value)&&value.length===2&&value.every(Number.isFinite);
      need(view.divine_chat&&frame,"只能重摆本队实际可及的本人远景原纸。");
      need(pair(origin)&&pair(size)&&size[0]>=1&&size[0]<=20&&size[1]>=.2&&size[1]<=10,
        "重摆宽1–20米、高0.2–10米，以世界米给新画幅左下。");
      need(Math.hypot(origin[0]+size[0]/2-view.self[0],origin[1]+size[1]/2-view.self[1])<=16,
        "新画心距实际站位不能超过16米，请先步行到可以掌笔的位置。");
      return {team_id:frame.team_id,world_id:frame.world_id,work_id:frame.work_id,
        expected_revision:frame.revision,origin,size};
    }
    case "paint_distant_sheet":
      return distantDraft(args,view,need,clean);
    case "paint_scene_detail": {
      const {marks}=args;
      const single=scene?.current?.kind==="landscape"&&(scene.subject||scene.current.form==="scenery");
      need((scene?.current?.kind==="vegetation" || single) &&
        Array.isArray(marks) && marks.length>=1 && marks.length<=16,"使用1到16段可执行的本批笔迹");
      if(!single)need(["tree","small_detail"].includes(args.plant_kind)&&marks.every(m=>plantParts.includes(m.part)),"请对本株植被分批标明根、树干、分枝或冠团。");
      for (const mark of marks) {
        need(brushes.includes(mark.brush)&&pigments.includes(mark.pigment)&&Array.isArray(mark.points)&&mark.points.length>=2&&
          mark.points.length<=24&&mark.points.every(p=>Array.isArray(p)&&p.length===2&&p.every(Number.isFinite)&&
            Math.hypot(p[0]-view.self[0],p[1]-view.self[1])<=5.5),"每笔须从现场实际可及的位置使用公共色板");
        if(washes.includes(mark.brush))need(mark.points.length>=4 &&
          mark.points[0].every((n,i)=>n===mark.points.at(-1)[i]),"淡彩薄洗须沿同一轮廓闭合");
      }
      return {command:{tool:"draw_scenery",name:clean(args.title,40),style:"ink",
        strokes:marks.map(m=>m.points),brushes:marks.map(m=>m.brush),pigments:marks.map(m=>m.pigment)},
        ...(!single?{plant:{kind:args.plant_kind,roles:marks.map(m=>m.part)}}:{})};
    }
  }
}
