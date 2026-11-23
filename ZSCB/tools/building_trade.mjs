import {readFileSync} from "node:fs";

const goods=JSON.parse(readFileSync(new URL("../assets/medieval/stall_goods.json",import.meta.url),"utf8"));
const labels=Object.entries(goods).map(([id,g])=>id+"="+g.name+"（参考"+g.price+"金）").join("、");
export const tradeSchema={type:"object",additionalProperties:false,
  description:"一处实际柜位的报价。"+labels+"。direction 从柜台看，sell_to_customer 售给来客，buy_from_customer 收来客的货。",
  properties:{visitor_use:{type:"string"},direction:{type:"string",enum:["sell_to_customer","buy_from_customer"]},
    item:{type:"string",enum:Object.keys(goods)},unit_price:{type:"integer",minimum:1,maximum:99}},required:["visitor_use","direction","item","unit_price"]};

const wantedNames={paper_lantern:/纸灯|纸紮灯|纸扎灯|灯笼|售灯|买灯|卖灯/u,reed_leaf:/苇叶|芦叶|芦苇叶/u,fruit:/朱果|红果|果铺|果摊|果棚|交果|售果|卖果|收果/u,forage:/牧草/u,red:/朱红颜料/u};
export function assignTrade(stations,input,legacyUse,brief,required,parentStations=[]) {
  const expects=Object.keys(wantedNames).filter(k=>wantedNames[k].test(brief));
  // Only unambiguous operating instructions constrain an offer. A lantern
  // hanging in a painted window can still be decoration on any shop.
  const tradeWords=/收购|收取|出售|售卖|卖给|向.{0,6}售|(?:收|售|交)(?:一份|一盏|一枚|几枚)?(?:朱果|纸灯|灯笼|灯|苇叶|芦苇叶|牧草|朱红颜料)/u;
  const requiredHere=required||(expects.length>0&&tradeWords.test(brief));
  const requestedDirection=/收购|收取|收(?:苇叶|朱果|牧草|纸灯)|交(?:苇叶|朱果|牧草)/u.test(brief)?"buy_from_customer":
    /出售|售卖|卖给|售(?:纸灯|灯|朱果|苇叶)|让(?:我|玩家|客人)买/u.test(brief)?"sell_to_customer":null;
  const oldFruit=parentStations.some(s=>s.service==="fruit_market");
  if(!expects.length && /修船|修舟|补船|船体维修/u.test(brief) && (input||legacyUse||required)){
    throw new RangeError("现有柜台只办理货物。修船需要独立的船体、材料与修理动作。");
  }
  if(!input){
    if(legacyUse&&(expects.includes("fruit")||oldFruit)&&requestedDirection!=="sell_to_customer"&&expects.every(k=>k==="fruit")&&/交.*果|卖.*果|收.*果/u.test(legacyUse)){
      const station=stations.find(s=>s.use===legacyUse);
      if(!station)throw new RangeError("原稿的交果使用位未通过净空校验");
      station.service="fruit_market"; return;
    }
    for(const s of stations){
      const old=parentStations.find(p=>p.use===s.use&&p.service);
      if(!old||expects.some(k=>k!==(old.offer?.item??"fruit"))||requestedDirection&&requestedDirection!==(old.offer?.direction??"buy_from_customer"))continue;
      s.service=old.service;
      if(old.offer)s.offer=structuredClone(old.offer);
    }
    if(requiredHere&&!stations.some(s=>s.service))throw new RangeError("请填写 counter_offer 的实际货物、收售方向、单价与通过检查的来客 use；尚无交易的货物请在回复中说明。");
    return;
  }
  if(!Object.hasOwn(goods,input.item)||!["buy_from_customer","sell_to_customer"].includes(input.direction)||
     !Number.isInteger(input.unit_price)||input.unit_price<1||input.unit_price>99)throw new RangeError("柜台需要可经营的真实货物、收售方向和 1 至 99 的整数单价");
  if(expects.length&&!expects.includes(input.item))throw new RangeError("报价货物与委托点名的"+expects.map(k=>goods[k].name).join("、")+"不符");
  if(requestedDirection&&requestedDirection!==input.direction)throw new RangeError("报价收售方向与委托要求不符");
  const target=stations.filter(s=>s.use===input.visitor_use);
  if(target.length!==1)throw new RangeError("请在 counter_offer.visitor_use 填写唯一且已验净空的客位");
  for(const s of stations){
    if(s===target[0])continue;
    const old=parentStations.find(p=>p.use===s.use&&p.service);
    if(!old)continue;
    s.service=old.service;
    if(old.offer)s.offer=structuredClone(old.offer);
  }
  target[0].service="market_counter";
  target[0].offer={direction:input.direction,item:input.item,unit_price:input.unit_price,source:input.direction==="sell_to_customer"?"stall_stock":"customer_bag"};
}
