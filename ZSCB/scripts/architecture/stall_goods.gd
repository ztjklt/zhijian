extends RefCounted
## Immutable terms live on the blueprint. Stock and cash belong to one built counter.
const GOODS := "res://assets/medieval/stall_goods.json"
const LAMP_INK := 8
const LAMP_SLOT := -3
const LIMIT := 999
const CASH_LIMIT := 9999
const BUY := "buy_from_customer"
const SELL := "sell_to_customer"
const LEGACY := {"item":"fruit","direction":BUY,"unit_price":1,"source":"customer_bag"}
static var catalog := {}

static func items() -> Dictionary:
	if catalog.is_empty(): catalog=JSON.parse_string(FileAccess.get_file_as_string(GOODS))
	return catalog

static func whole(n,low:int,high:int) -> bool:
	return typeof(n) in [TYPE_INT,TYPE_FLOAT] and is_finite(n) and n==floor(n) and n>=low and n<=high

static func valid(q) -> bool:
	return q is Dictionary and q.size()==4 and items().has(q.get("item","")) and whole(q.get("unit_price"),1,99) and (q.get("direction")==BUY and q.get("source")=="customer_bag" or q.get("direction")==SELL and q.get("source")=="stall_stock")

static func is_counter(station:Dictionary) -> bool:
	return station.get("service")=="fruit_market" or station.get("service")=="market_counter" and valid(station.get("offer"))

static func valid_accounts(value,stations:Array) -> bool:
	if not value is Dictionary or value.size()>stations.size():return false
	for key in value:
		if not key is String or not key.is_valid_int() or str(int(key))!=key:return false
		var i:=int(key)
		if i<0 or i>=stations.size() or stations[i].get("service")!="market_counter":return false
		var account=value[key]
		if not account is Dictionary or account.size()!=2 or not whole(account.get("stock"),0,LIMIT) or not whole(account.get("coins"),0,CASH_LIMIT):return false
	return true

static func label(q:Dictionary) -> String:
	return "%s%s · %d 金" % ["收" if q.direction==BUY else "售",items()[q.item].name,int(q.unit_price)]

static func _account(obj:Dictionary,slot:int) -> Dictionary:
	return obj.get("stall_accounts",{}).get(str(slot),{"stock":0,"coins":0}).duplicate()

static func _commit(service,obj:Dictionary,slot:int,account:Dictionary) -> void:
	if not obj.has("stall_accounts"):obj.stall_accounts={}
	obj.stall_accounts[str(slot)]=account
	# Artwork undo keeps live actor inventories. A prior drawing of this same
	# building must therefore keep the live till as well.
	var game=service.world.game
	for stack:Array in [game.undo_stack,game.redo_stack]:
		for snapshot in stack:
			for painted in snapshot.objects:
				if painted.get("structure_id")==obj.structure_id:
					painted.stall_accounts=obj.stall_accounts.duplicate(true)
					break

static func capacity(service,item:String) -> int:
	return service.Forage.LIMIT if item=="forage" else LIMIT

static func change_item(service,bag:Dictionary,item:String,change:int) -> void:
	bag[item]=int(bag.get(item,0))+change
	if bag[item]==0 and (item=="paper_lantern" and bag.held==LAMP_SLOT or item=="fruit" and bag.held==service.FRUIT):
		bag.held=service.EMPTY
		if item=="fruit":bag.meal=0.0
		if item=="paper_lantern":bag.lamp_lit=false

## A built shop receives only what the builder can actually supply. A paper lamp
## can alternatively be manufactured from the builder's remaining real ink.
static func open_accounts(service,obj:Dictionary,builder:String) -> void:
	if not obj.has("built_plan") or obj.has("stall_accounts"):return
	var stations:Array=obj.built_plan.layout.get("stations",[])
	for i in stations.size():
		var station:Dictionary=stations[i]
		if station.get("service")!="market_counter":continue
		var q:Dictionary=station.offer
		var account:={"stock":0,"coins":0}
		var bag:Dictionary=service.inventory(builder)
		if q.direction==BUY:
			var budget:=mini(int(bag.economy.coins),int(q.unit_price))
			account.coins=budget
			bag.economy.coins-=budget
		elif int(bag.get(q.item,0))>0:
			change_item(service,bag,q.item,-1)
			account.stock=1
		elif q.item=="paper_lantern" and service._reserve(builder).can_spend(LAMP_INK):
			service._reserve(builder).spend(LAMP_INK)
			account.stock=1
		service.actors[builder]=bag
		_commit(service,obj,i,account)

static func public_quote(hit:Dictionary) -> Dictionary:
	if hit.is_empty():return {}
	var q:Dictionary=hit.offer.duplicate(true)
	q.station=hit.station
	q.slot=int(hit.get("slot",-1))
	q.name=items()[q.item].name
	q.label=label(q)
	if hit.has("object"):
		var account:=_account(hit.object,hit.slot)
		q.stock=account.stock
		q.coins=account.coins
	return q

static func quote_matches(hit:Dictionary,requested:Dictionary) -> bool:
	if hit.is_empty():return false
	var q:=public_quote(hit)
	for key in ["station","slot","item","unit_price","source","direction"]:
		if requested.get(key)!=q[key]:return false
	return true

static func trade(service,id:String,args:Dictionary) -> Dictionary:
	var hit:Dictionary=service.counter_hit(id)
	if not quote_matches(hit,args) or not hit.has("object"):return {"error":"这张报价与脚下的柜位不符，请走到原柜重新看价。"}
	var q:Dictionary=hit.offer
	var account:=_account(hit.object,hit.slot)
	var bag:Dictionary=service.inventory(id)
	var price:=int(q.unit_price)
	var item:String=q.item
	var buying:bool=q.direction==SELL
	var old_quantity:=int(bag.get(item,0))
	var old_money:=int(bag.economy.coins)
	var old_stock:=int(account.stock)
	var old_till:=int(account.coins)
	if buying:
		if account.stock<=0:return {"error":"柜里已经没有%s。"%items()[item].name}
		if old_money<price:return {"error":"需 %d 金，你有 %d 金。"%[price,old_money]}
		if old_quantity>=capacity(service,item) or old_till+price>CASH_LIMIT:return {"error":"背包或柜台钱匣已满。"}
	else:
		if old_quantity<=0:return {"error":"背包里没有%s。"%items()[item].name}
		if old_till<price:return {"error":"柜台钱匣只有 %d 金，暂不能收货。"%old_till}
		if old_stock>=LIMIT or old_money+price>CASH_LIMIT:return {"error":"柜位已满或钱袋装不下。"}
	var n:=1 if buying else -1
	change_item(service,bag,item,n)
	bag.economy.coins=old_money-n*price
	account.stock=old_stock-n
	account.coins=old_till+n*price
	service.actors[id]=bag
	_commit(service,hit.object,hit.slot,account)
	var title:String=service.contracts.market_title(hit.station)
	var detail:String="%s · %s一份%s，%d 金。"%[title,"买入" if buying else "交出",items()[item].name,price]
	service.contracts.goods_trade(id,hit.station,service._position(id),detail,q,hit.slot,[old_money,int(bag.economy.coins)],[old_quantity,int(bag[item])],[old_stock,int(account.stock)],[old_till,int(account.coins)])
	return {"ok":true,"message":detail}

static func provision(service,id:String,args:Dictionary) -> Dictionary:
	var hit:Dictionary=service.counter_hit(id)
	if not quote_matches(hit,args) or not hit.has("object"):return {"error":"请走回原柜再补货。"}
	var account:=_account(hit.object,hit.slot)
	var bag:Dictionary=service.inventory(id)
	var q:Dictionary=hit.offer
	var action:String=str(args.get("action",""))
	var description:=""
	match action:
		"make_lamp":
			if q.item!="paper_lantern" or q.direction!=SELL or account.stock>=LIMIT:return {"error":"这处柜位不能制灯入库。"}
			var reserve=service._reserve(id)
			if not reserve.can_spend(LAMP_INK):return {"error":"制一盏纸灯需 %d 墨。"%LAMP_INK}
			reserve.spend(LAMP_INK)
			account.stock+=1
			description="花 %d 墨做一盏纸灯，柜内 %d 盏。"%[LAMP_INK,account.stock]
		"stock":
			if q.direction!=SELL or bag.get(q.item,0)<=0 or account.stock>=LIMIT:return {"error":"这件货无法存进柜台。"}
			change_item(service,bag,q.item,-1)
			account.stock+=1
			description="已从随身背包补入一份%s。"%items()[q.item].name
		"fund":
			if q.direction!=BUY or bag.economy.coins<q.unit_price or account.coins+q.unit_price>CASH_LIMIT:return {"error":"补足一单收购金所需金币不足或钱匣已满。"}
			account.coins+=int(q.unit_price)
			bag.economy.coins-=int(q.unit_price)
			description="已从自己钱袋存入 %d 金收购款。"%q.unit_price
		"collect":
			if hit.object.built_plan.owner!=id or account.coins<=0 or bag.economy.coins+account.coins>CASH_LIMIT:return {"error":"需要在自己的柜前结取可容纳的柜款。"}
			description="收取本柜 %d 金。"%account.coins
			bag.economy.coins+=account.coins
			account.coins=0
		"retrieve":
			if hit.object.built_plan.owner!=id or account.stock<=0 or bag.get(q.item,0)>=capacity(service,q.item):return {"error":"只能取回自己柜中现有的货。"}
			change_item(service,bag,q.item,1)
			account.stock-=1
			description="从自己柜中收回一份%s。"%items()[q.item].name
		_:return {"error":"柜台操作无效。"}
	service.actors[id]=bag
	_commit(service,hit.object,hit.slot,account)
	return {"ok":true,"message":description}
