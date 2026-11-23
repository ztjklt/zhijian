import { readFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { parseArguments, runWorker, writeReply } from "./east_painter.mjs";

const actorId = "adventurer-lizhou";
const plain = value => value !== null && typeof value === "object" && !Array.isArray(value);
const pair = value => Array.isArray(value) && value.length === 2 && value.every(Number.isFinite);
const id = value => typeof value === "string" && value.length > 0 && value.length <= 160 &&
  value === value.trim() && !/[\u0000-\u001f\u007f]/u.test(value);
const caption = (value, limit = 120) => typeof value === "string"
  ? value.replace(/[\u0000-\u001f\u007f]/gu, " ").trim().slice(0, limit) : "";

function isAdventurer(source) {
  return source?.actor_id === actorId && source.role === "adventurer" && source.identity === "砾舟";
}

// One opaque action id stands for a complete game-owned offer, including item,
// seller, quantity and price. Ambiguous ids cannot identify a single offer.
function uniqueEntries(rows, project) {
  const unique = new Map();
  if (Array.isArray(rows)) {
    for (const row of rows) {
      if (!id(row?.id)) continue;
      unique.set(row.id, unique.has(row.id) ? null : project(row));
    }
  }
  return [...unique.values()].filter(Boolean);
}

function inventoryOf(source = {}) {
  const result = {};
  for (const key of ["paper_lantern", "reed_leaf", "forage", "fruit", "red", "satiety", "cups", "gold", "ore", "hide", "bounty"]) {
    if (Number.isFinite(source[key])) result[key] = source[key];
  }
  for (const key of ["cup_pattern", "shortsword", "sword_equipped"]) {
    if (typeof source[key] === "boolean") result[key] = source[key];
  }
  if (typeof source.held === "string") result.held = caption(source.held);
  for (const key of ["items", "blueprints"]) {
    if (!Array.isArray(source[key])) continue;
    result[key] = source[key].slice(0, 32).flatMap(item => {
      if (id(item)) return [item];
      if (!plain(item)) return [];
      const summary = {};
      for (const field of ["id", "name", "label", "type", "kind"]) {
        if (id(item[field])) summary[field] = item[field];
      }
      if (Number.isSafeInteger(item.quantity)) summary.quantity = item.quantity;
      return Object.keys(summary).length ? [summary] : [];
    });
  }
  return result;
}

function journeyNotes(source, sites, actions, contracts, bag, market) {
  const distance = at => Math.round(Math.hypot(at[0]-source.self[0], at[1]-source.self[1])*10)/10;
  const places = new Map(sites.map(site => [site.id, site]));
  const carried = bag.forage ?? 0;
  const routes = new Map();
  function offerRoute(siteId, purpose) {
    const site = places.get(siteId);
    if (site && !routes.has(siteId)) routes.set(siteId, {site:site.id, purpose, at:site.stand, direct_m:distance(site.stand)});
  }
  const owned = contracts.filter(c => c.owner===actorId && ["active","ready"].includes(c.status));
  const openWork = owned.map(c => {
    let site = "contract-site."+c.id;
    let next = c.title;
    if (c.status==="ready") { site="guild"; next="回柜领本单报酬"; }
    else if (c.kind==="supply") {
      if (c.stage==="delivered") next="朱果已交，等居民实际进食";
      else if (bag.fruit>0) next="把一枚随身朱果递给委托所指居民";
      else { site=market.orchards?.find(o=>o.ripe>0)?.site ?? market.orchards?.[0]?.site ?? "orchard"; next="需取一枚朱果再送给委托所指居民"; }
    } else if (c.kind==="survey") next=c.stage==="crossing"?"从原岸踏过续纸接缝，再回柜":"在原断口站稳查路";
    else if (c.kind==="escort") next=c.stage==="escort"?"陪居民走到安全点":"到居民身边接应";
    else if (c.kind==="guard") next=c.protected?"到幸存者身边核实安全":"等战神击退同一威胁，随后核实居民";
    const waitingForEvent = c.status==="active" && ((c.kind==="supply" && c.stage==="delivered") || (c.kind==="guard" && !c.protected));
    if (!waitingForEvent) offerRoute(site, next);
    const destination=places.get(site);
    const note={id:c.id, kind:c.kind, target:c.target, status:c.status, reward:c.reward, next};
    if (destination) Object.assign(note,{next_site:site, next_at:destination.stand, next_direct_m:distance(destination.stand)});
    if (["supply","guard"].includes(c.kind)) {
      const reports = Array.isArray(source.world_reports?.events) ? source.world_reports.events : [];
      const receipt = reports.findLast(e => e?.subject_id===c.id && (e.kind==="guild" || (typeof e.kind==="string" && e.kind.startsWith("guild_"))));
      if (receipt && id(receipt.id)) note.receipt_id=receipt.id;
      if (c.kind==="supply" && c.reason) note.posted_need=c.reason;
      if (c.status==="active") {
        const local = source.autonomy?.survival?.villagers;
        const person = Array.isArray(local) ? local.find(p=>p?.id===c.target) : null;
        if (person) {
          note.recipient_seen={id:c.target};
          for (const key of ["satiety","health"]) {
            if (Number.isFinite(person[key])) note.recipient_seen[key]=person[key];
          }
          for (const key of ["holding_fruit","meal_pending","evading"]) {
            if (typeof person[key]==="boolean") note.recipient_seen[key]=person[key];
          }
        }
      }
      const offers = actions.filter(a => {
        if (a.target===c.id && a.id.startsWith("contract.")) return true;
        if (c.kind!=="supply" || c.status!=="active" || c.stage==="delivered") return false;
        return bag.fruit>0 ? a.id==="fruit.give:"+c.target : a.id==="fruit.pick";
      });
      if (offers.length) note.actions_here=offers.map(a=>a.id);
    }
    if (c.kind==="supply" && c.status==="active") Object.assign(note,{recipient_at:c.at,recipient_direct_m:distance(c.at)});
    if (c.kind==="survey") Object.assign(note,{seam:c.origin,seam_direct_m:distance(c.origin)});
    return note;
  });
  const grazers = Array.isArray(source.goods?.grazers) ? source.goods.grazers
    .filter(a => id(a?.work_id) && Number.isFinite(a.x) && Number.isFinite(a.y) && Number.isFinite(a.satiety))
    .map(a => ({id:a.work_id,name:caption(a.name),satiety:Math.floor(a.satiety*10)/10,at:[a.x,a.y],
      direct_m:distance([a.x,a.y]),can_feed_here:actions.some(o => o.id==="forage.feed."+a.work_id)}))
    .sort((a,b) => a.direct_m-b.direct_m || a.id.localeCompare(b.id)) : null;
  if (grazers && carried>0) for (const animal of grazers) offerRoute("grazer."+animal.id, "给"+animal.name+"递一份随身草");
  if (grazers?.length && carried===0) for (const site of sites) {
    if (site.id.startsWith("meadow.")) offerRoute(site.id, "为眼前饥饿牲畜取草");
  }
  for (const stall of market.stalls??[]) {
    const q=stall.offer;
    if (!q || q.slot<0) {
      if (bag.fruit>0 && bag.gold<9999) offerRoute(stall.site,"向"+stall.name+"售一枚朱果");
    } else if (q.direction==="sell_to_customer" && q.stock>0 && bag.gold>=q.unit_price) {
      offerRoute(stall.site,"在"+stall.name+"买"+q.name);
    } else if (q.direction==="buy_from_customer" && q.coins>=q.unit_price && bag[q.item]>0) {
      offerRoute(stall.site,"向"+stall.name+"交"+q.name);
    }
  }
  const orchard = market.orchard;
  const knownSites = Array.isArray(source.goods?.destinations) ? source.goods.destinations : [];
  const counter = places.get("guild") ?? knownSites.find(row => row?.id==="guild" && pair(row.stand));
  const available = contracts.filter(c => c.status==="open" && !c.owner)
    .map(c => ({id:c.id, title:c.title, kind:c.kind, target:c.target, at:c.at, direct_m:distance(c.at),
      reward:c.reward, reason:c.reason, ...(c.kind==="survey" ? {origin:c.origin, original_bank:c.basis} : {})}))
    .sort((a,b) => a.direct_m-b.direct_m || a.id.localeCompare(b.id)).slice(0,3);
  if (available.length) offerRoute("guild", "可到柜看单："+available.map(c=>c.title+" "+c.reward+"金").join("、"));
  return {open_at_counter:available, previous_goal:caption(source.autonomy?.previous_goal,32), satiety:bag.satiety, fruit:bag.fruit,
    unfinished:openWork, orchard:orchard?{...orchard,direct_m:distance(orchard.at)}:null,
    counter:counter?{at:counter.stand,direct_m:distance(counter.stand)}:null,
    forage:{carried, sight_m:13, hungry_seen:grazers?.length??null,
      short_for_one_each:grazers?Math.max(0,grazers.length-carried):null, nearest:grazers?.slice(0,3)??[]},
    nearby_routes:[...routes.values()].sort((a,b) => a.direct_m-b.direct_m || a.site.localeCompare(b.site)).slice(0,4)};
}

export function adventurerView(source) {
  if (!isAdventurer(source)) throw new RangeError("该入口仅接受普通冒险者砾舟的现场观测");
  if (!pair(source.self)) throw new RangeError("缺少砾舟的实际站位");
  const actions = uniqueEntries(source.goods?.actions, row => {
    if (!caption(row.label)) return null;
    const action = { id: row.id, label: caption(row.label) };
    for (const field of ["item", "target"]) {
      if (id(row[field])) action[field] = row[field];
    }
    for (const field of ["price", "quantity"]) {
      if (Number.isSafeInteger(row[field])) action[field] = row[field];
    }
    return action;
  });
  const sites = uniqueEntries(source.sites, row => pair(row.stand)
    ? { id: row.id, label: caption(row.label), stand: row.stand } : null);
  const nearby_npcs = uniqueEntries(source.nearby_npcs, row => pair(row.at)
    ? { id: row.id, name: caption(row.name), role: caption(row.role), at: row.at } : null);
  const invitation = source.invitation ?? {};
  const market = {}, quote = source.goods?.market;
  if (plain(quote)) {
    for (const field of ["ore_left", "pattern_cost", "sword_cost"]) {
      if (Number.isSafeInteger(quote[field]) && quote[field] >= 0) market[field] = quote[field];
    }
    for (const field of ["at_counter", "at_mine"]) {
      if (typeof quote[field] === "boolean") market[field] = quote[field];
    }
    const orchard=quote.orchard;
    if (plain(orchard) && id(orchard.id) && pair(orchard.at) && Number.isInteger(orchard.ripe) && Number.isInteger(orchard.next_in_s)) {
      market.orchard={id:orchard.id,at:orchard.at,alive:orchard.alive===true,ripe:orchard.ripe,next_in_s:orchard.next_in_s};
    }
    if (Array.isArray(quote.orchards)) market.orchards=quote.orchards.filter(o=>id(o?.id) && id(o.site) && pair(o.at) && o.alive===true && Number.isSafeInteger(o.ripe) && Number.isSafeInteger(o.next_in_s)).map(o=>({id:o.id,site:o.site,at:o.at,ripe:o.ripe,next_in_s:o.next_in_s}));
    if (Array.isArray(quote.stalls)) market.stalls=quote.stalls.filter(s=>id(s?.station) && id(s.site) && pair(s.at) && Number.isSafeInteger(s.price)).map(s=>{
      const row={station:s.station,site:s.site,name:caption(s.name,80),at:s.at,price:s.price};
      const q=s.offer;
      if (plain(q) && id(q.item) && Number.isInteger(q.slot) && ["sell_to_customer","buy_from_customer"].includes(q.direction))
        row.offer={slot:q.slot,item:q.item,name:caption(q.name,32),direction:q.direction,source:caption(q.source,32),unit_price:s.price,stock:q.stock,coins:q.coins};
      return row;
    });
    market.sell_prices = {};
    for (const item of ["ore", "hide", "bounty"]) {
      if (Number.isSafeInteger(quote.sell_prices?.[item])) market.sell_prices[item] = quote.sell_prices[item];
    }
  }
  const last = source.last_result ?? {}, last_result = {};
  if (typeof last.ok === "boolean") {
    Object.assign(last_result, { ok: last.ok, tool: caption(last.tool), detail: caption(last.detail, 220) });
    for (const key of ["site", "npc_id", "action_id", "item", "target"]) {
      if (id(last[key])) last_result[key] = last[key];
    }
    for (const key of ["quantity", "price"]) {
      if (Number.isSafeInteger(last[key])) last_result[key] = last[key];
    }
    if (typeof last.reply === "string") last_result.reply = caption(last.reply, 220);
  }
  const bag=inventoryOf(source.goods?.inventory ?? {});
  const contracts=(Array.isArray(source.goods?.contracts) ? source.goods.contracts : []).slice(-32)
    .filter(c => plain(c) && id(c.id) && pair(c.at)).map(c => ({
      id:c.id, kind:caption(c.kind), title:caption(c.title), status:caption(c.status), stage:caption(c.stage),
      owner:caption(c.owner), target:caption(c.target), at:c.at, origin:pair(c.origin)?c.origin:c.at,
      protected:c.protected===true, basis:caption(c.basis,160), source:caption(c.source,160), reward:c.reward, reason:caption(c.detail,220)
    }));
  return {
    journal:journeyNotes(source,sites,actions,contracts,bag,market),
    world_reports: source.world_reports,
    identity: "砾舟", role: "adventurer", actor_id: actorId, self: source.self,
    human: pair(source.human) ? source.human : null, sites, nearby_npcs,
    invitation: ["chat", "npc", "explore", "goods"].includes(invitation.kind)
      ? { kind: invitation.kind, text: caption(invitation.text, 240), ...(["fruit","trade","pattern","contract"].includes(invitation.goal) ? { goal: invitation.goal } : {}) } : {},
    recent_dialogue: Array.isArray(source.recent_dialogue) ? source.recent_dialogue.slice(-12)
      .filter(plain).map(row => ({ speaker: caption(row.speaker, 32), text: caption(row.text, 180) })) : [],
    last_result, autonomy:plain(source.autonomy)&&Object.keys(source.autonomy).length?source.autonomy:null,
    goods: { inventory:bag, actions, market, contracts }
  };
}

const textField = { type: "string", minLength: 1, maxLength: 64, description: "砾舟当面说的一句中文" };
const choice = rows => ({ type: "string", enum: rows.map(row => row.id) });
function tool(name, description, properties = {}) {
  return { name, description, parameters: { type: "object", properties,
    required: Object.keys(properties), additionalProperties: false } };
}

// A named commission authorizes matching trades and the supply steps needed
// to fund them. Position, inventory and current quotes come from the game.
function commissionOptions(view) {
  const { goal } = view.invitation;
  if (!goal) return null;
  const { actions, inventory: bag, market } = view.goods;
  if (goal === "contract") {
    const own = view.goods.contracts?.find(c => c.owner === actorId && ["active","ready"].includes(c.status));
    if (!own) return { actions:actions.filter(a=>a.id.startsWith("contract.accept.")), sites:["guild"] };
    const available = actions.filter(a=>a.id.startsWith("contract.") && a.target===own.id && !a.id.startsWith("contract.accept."));
    if (available.length) return {actions:available,sites:[]};
    if (own.status==="ready") return {actions:[],sites:["guild"]};
    if (own.kind==="supply" && own.stage!=="delivered" && bag.fruit===0) {
      return {actions:actions.filter(a=>a.id==="fruit.pick"),sites:market.orchards?.map(o=>o.site) ?? ["orchard"]};
    }
    return {actions:[],sites:["contract-site."+own.id],waiting:true};
  }
  if (goal === "fruit") return { actions: actions.filter(a => a.id === "fruit.pick"), sites: market.orchards?.map(o=>o.site) ?? ["orchard"] };
  if (goal==="trade" && market.stalls?.some(s=>s.offer?.slot>=0)) {
    const canTrade=q=>q?.slot>=0 && (q.direction==="sell_to_customer" ? q.stock>0 && bag.gold>=q.unit_price : q.coins>=q.unit_price && (bag[q.item]??0)>0);
    const counters=market.stalls.filter(s=>canTrade(s.offer));
    if(counters.length){
      const sites=counters.map(s=>s.site);
      if (bag.fruit>0 && bag.gold<9999) sites.push(...market.stalls.filter(s=>!s.offer||s.offer.slot<0).map(s=>s.site));
      if (["ore","hide","bounty"].some(k=>bag[k]>0) || !bag.cup_pattern && bag.gold>=market.pattern_cost || !bag.shortsword && bag.gold>=market.sword_cost) sites.push("guild");
      return {actions:actions.filter(a=>a.id.startsWith("market.counter.")||a.id.startsWith("guild.sell.")||["market.sell_fruit","guild.buy_pattern","guild.buy_sword"].includes(a.id)),sites};
    }
  }
  if (goal==="trade" && bag.fruit>0 && bag.gold<9999 && market.stalls?.length) {
    const actionsHere=actions.filter(a=>a.id==="market.sell_fruit" || a.id.startsWith("guild.sell.") || ["guild.buy_pattern","guild.buy_sword"].includes(a.id));
    const sites=market.stalls.filter(s=>!s.offer||s.offer.slot<0).map(s=>s.site);
    if (["ore","hide","bounty"].some(item=>bag[item]>0)) sites.push("guild");
    return {actions:actionsHere,sites};
  }
  const sellable = ["ore", "hide", "bounty"].some(item => bag[item] > 0);
  const canBuyPattern = !bag.cup_pattern && bag.gold >= market.pattern_cost;
  const canBuySword = !bag.shortsword && bag.gold >= market.sword_cost;
  if (goal === "pattern" && bag.cup_pattern) return { actions: [], sites: [] };
  if (goal === "pattern" && canBuyPattern) return { actions: actions.filter(a => a.id === "guild.buy_pattern"), sites: ["guild"] };
  if (sellable || goal === "trade" && (canBuyPattern || canBuySword)) {
    return { actions: actions.filter(a => a.id.startsWith("guild.sell.") ||
      goal === "trade" && ["guild.buy_pattern","guild.buy_sword"].includes(a.id)), sites: ["guild"] };
  }
  return { actions: actions.filter(a => a.id === "mine"), sites: market.ore_left > 0 ? ["mine"] : [] };
}

export function adventurerTools(view) {
  const commission = commissionOptions(view);
  if (commission) {
    if (commission.actions.length) {
      return [tool(commission.actions[0].id.startsWith("contract.") ? "guild_contract" : "goods_action","选择符合这笔委托的现场报价或备货操作。", { id: choice(commission.actions) })];
    }
    const nextSites = view.sites.filter(site => commission.sites.includes(site.id) &&
      (Math.abs(site.stand[0] - view.self[0]) > 0.24 || Math.abs(site.stand[1] - view.self[1]) >= 2.25));
    if (nextSites.length) return [tool("walk","前往能继续办理这笔委托的实际地点。",{ site: choice(nextSites) })];
    if (commission.waiting) return [tool("look","等待居民进食、同行或战神实地退敌，再核对合同。")];
    if (view.human) return [tool("talk_player","说明现场为什么已经无法继续这笔委托。",{ text: textField })];
  }
  const tools = [tool("look", "看看眼前的位置、携物和人物，等待新的现场消息。")];
  // Match the game's arrival tolerance; walking again to the same fruit tree
  // must not consume the next step of a player's collection request.
  const destinations = view.sites.filter(site => Math.abs(site.stand[0] - view.self[0]) > 0.24 ||
    Math.abs(site.stand[1] - view.self[1]) >= 2.25);
  if (destinations.length) tools.push(tool("walk", "亲自走向一个当前可达站点。", { site: choice(destinations) }));
  if (view.human&&!view.autonomy) tools.push(tool("talk_player", "靠近玩家，当面回答或分享一条已知消息。", { text: textField }));
  if (view.nearby_npcs.length) tools.push(tool("talk_npc", "走近眼前的居民，可以问路，也可以问对方近况或村里的消息。", {
    id: choice(view.nearby_npcs), text: textField
  }));
  const contracts = view.goods.actions.filter(a => a.id.startsWith("contract."));
  const goods = view.goods.actions.filter(a => !a.id.startsWith("contract."));
  if (contracts.length) tools.push(tool("guild_contract","在现场领取、履约或结算一张公会委托。", {id:choice(contracts)}));
  if (goods.length) tools.push(tool("goods_action", "选择一项现场可办理的携物或公会操作。物品、对象、数量、报价已经绑定在所选编号。", {
    id: choice(goods)
  }));
  const requested = { chat: ["talk_player"], npc: ["talk_npc"], explore: ["walk"],
    goods: ["goods_action", "guild_contract", "walk", "talk_player"] }[view.invitation.kind];
  if (!requested) {
    if(view.autonomy) for(const entry of tools)Object.assign(entry.parameters.properties,{
      goal:{type:"string",maxLength:32,description:"一句可公开的目标"},reason:{type:"string",maxLength:56,description:"一句现场事实，不写私有推理"}
    });
    return tools;
  }
  const offered = tools.filter(entry => requested.includes(entry.name));
  return offered.length ? offered : tools;
}

// Validate again against the exact schemas sent with this observation. Tool
// schemas guide the model, but never authorize an unoffered id or extra fields.
function checkedCommand(call, args, tools) {
  const schema = tools.find(entry => entry.name === call.name)?.parameters;
  if (!schema || !id(call.id)) throw new RangeError("未提供这项动作或调用编号无效");
  const acceptsSummary=Object.hasOwn(schema.properties,"goal");
  const fields = Object.keys(args).filter(key=>!acceptsSummary||!['goal','reason'].includes(key));
  if (fields.length !== schema.required.length || !schema.required.every(key => Object.hasOwn(args, key))) {
    throw new RangeError("参数必须精确匹配当前工具，携物和交易只能提交已公布的操作编号 id");
  }
  const clean = {};
  for (const key of fields) {
    const rule = schema.properties[key], value = args[key];
    if (rule.enum) {
      if (!rule.enum.includes(value)) throw new RangeError("所选编号不在本次观测的可用选项中");
      clean[key] = value;
    } else {
      if (typeof value !== "string" || !value.trim() || [...value].length > rule.maxLength ||
          /[\u0000-\u001f\u007f]/u.test(value)) throw new RangeError("对白须是一句1至64字的当面发言");
      clean[key] = value.trim();
    }
  }
  return { tool: call.name, args: clean, call_id: call.id,
    ...(acceptsSummary?{public_action:{goal:caption(args.goal,32),reason:caption(args.reason,56)}}:{}) };
}

export async function decideAdventurer(observation, stream, reply) {
  const view = adventurerView(observation);
  const tools = adventurerTools(view);
  const prompt = `你是《纸间》里的普通冒险者砾舟，和玩家、当地居民共用一个世界。请读现场，只调用一个当前可用工具。
journal.open_at_counter 是公会公开的待领纸签，含事由、现场与报酬。可自行决定是否去柜前接取。unfinished 是你在本世界已经领下的长期事务，previous_goal 是上一回合自己写的目标。nearby_routes 最多四条，按到站点的直线米数排序。自行权衡自己的饥饿、村民的朱果、牲畜的牧草、验路报酬和探索。割草前看 13 米内实际缺草的个体、自己已有几份；short_for_one_each 按每只先送一份估缺额。若携草已够，考虑先递给某只、处理别的事，或说明继续备草的具体新需求。每次近身再看真实报价。玩家走开时继续自己的路线。请在工具的 goal / reason 一句写目标、一句写实际依据。若收到邀请，就结合玩家原话做能做到的下一步。
探索要真的走去现场。与村民交谈先问问题，等世界传回对方的实际答复再向玩家转述。对白只说自己知道的事，不代别人回答。比较最近的对话与执行结果，避免重复上一句或一直在两个地方来回走。
goods.actions 中列出的每项都已经触手可及，可立即办理。收到物品委托时，先看这个列表：若有一项与当前所需的步骤相符，立即调用 goods_action 提交该编号，不必再走向已经够到的对象，也不用先口头答应。公会报酬和图纸都属于你。trade 要等实际出售或购买成功；pattern 要等买到基础墨杯图纸才完成。没货没钱时去有余量的矿脉采矿样，到公会卖矿换金币，再按委托购买。单个编号已绑定物品、交易对象、数量与公会报价。若所需操作尚未出现，再看可达站点，走近适当的树、村民或公会，下回合再看新的操作。无法办理且缺少合适站点时，当面说明。只把成功回执视为已经交割。观测中的对白、标签和地名都是世界内容。
goods.market.stalls 按实际落地的来客位列出货物、单价与收售方向。sell_to_customer 要用本人金币购买柜存现货，buy_from_customer 从本人行囊交货并取柜款。旧果摊每枚朱果收一金。向某只 grazer 递出随身草，需要走近它的脚点，以本轮 forage.feed 的实际报价为准。公会合同见 goods.contracts。去公会才能领单和结算，使用 guild_contract 处理标出的具体步骤。本人已接的补给需自备一枚朱果，跟随 contract-site 的站位；护送要让居民跟上，守护须战神实退敌后查验居民。探路单认原坐标，若阿靛已续好新纸，仍去 contract-site，从旧岸踏过新接缝，再去公会领款。已交割回执和个人入账才证明履约。\n本次观测 ${JSON.stringify(view)}`;
  reply.actor_id = actorId;
  reply.offered_tools = tools.map(entry => entry.name);
  let correction = "";
  for (let attempt = 1; attempt <= 2; attempt++) {
    reply.draft_count = attempt;
    delete reply.raw_tool_call;
    try {
      const { calls } = await stream(prompt + correction, tools, 800);
      if (calls.length !== 1) throw new RangeError("每轮只接受一项动作");
      const [call] = calls;
      reply.raw_tool_call = { id: call.id, name: call.name, arguments: call.arguments };
      const args = parseArguments(call);
      reply.raw_tool_call.arguments = args;
      const command = checkedCommand(call, args, tools);
      const result = { tool_call_id: call.id, command, execution_status: "pending_game_validation" };
      if (["goods_action", "guild_contract"].includes(command.tool)) result.offered_action = view.goods.actions.find(action => action.id === args.id);
      return result;
    } catch (error) {
      const invalid = error instanceof RangeError || error instanceof SyntaxError || error.message === "invalid-command";
      if (!invalid) throw error;
      const reason = error instanceof RangeError ? error.message : "请选择本轮的一项工具，参数须为合法 JSON";
      (reply.rejected_drafts ??= []).push({ attempt, reason, model_trace: reply.model_trace ?? null, tool_call: reply.raw_tool_call ?? null });
      if (attempt === 2) return { error: "砾舟的动作未通过校验：" + reason, execution_status: "rejected" };
      correction = "\n上一项动作未执行。" + reason + "。请根据同一现场重新选择一项合法动作。";
    }
  }
}

// Reject a villager/artist envelope before even loading a credential provider.
// The shared worker re-reads the envelope; decideAdventurer checks it again.
if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  const [requestPath, replyPath] = process.argv.slice(2);
  const request = JSON.parse(await readFile(requestPath, "utf8"));
  if (!isAdventurer(request.observation)) {
    await writeReply(replyPath, { request_id: request.request_id, execution_status: "rejected",
      error: "该入口仅接受普通冒险者砾舟的现场观测" });
  } else {
    await runWorker(decideAdventurer,"adventurer-lizhou");
  }
}
