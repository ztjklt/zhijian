extends RefCounted
## Room-only lending. It never changes authorship or enters a world save.
const MAX_SHARED:=128
var room
var shared:Dictionary={}
var version:=0
var previous:Dictionary={}
func _init(owner_room)->void:room=owner_room
func can_use(actor,object:Dictionary)->bool:
	var author:String=object.get("author","")
	if author==actor.player_id:return true
	return shared.has(object.get("id","")) and room.actors.has(author) and room.actors[author].connected and room.actors[author].ready_to_play
func apply(actor,msg:Dictionary)->Dictionary:
	if not msg.get("enabled") is bool:return room._failure("请选择开放或撤回协作")
	var index:int=room._object_index(str(msg.get("id","")))
	if index<0:return room._failure("部件已经不存在")
	var object:Dictionary=room.world.objects[index]
	if object.author!=actor.player_id:return room._failure("只能由作者开放或撤回自己的部件")
	if msg.get("version",-1)!=object.version:return room._failure("部件状态已变化，请重新选择")
	var enabled:bool=msg.enabled
	if enabled and Vector2(object.x,object.y).distance_to(actor.player.position)>12:return room._failure("走近12米内再开放协作")
	if enabled and not shared.has(object.id) and shared.size()>=MAX_SHARED:return room._failure("当前房间最多开放128件部件")
	if shared.has(object.id)==enabled:return room._success()
	if enabled:shared[object.id]=true
	else:shared.erase(object.id)
	room.locks.erase(object.id)
	object.version+=1
	return room._success()
func clear()->void:
	for id in shared.keys():
		var index:int=room._object_index(id)
		if index>=0:room.world.objects[index].version+=1
		room.locks.erase(id)
	shared.clear()
func remove(id:String)->void:shared.erase(id)
func touch(keys:Array)->Dictionary:
	var versions:Dictionary={}
	for key in keys:
		var object:Dictionary=room.world.structure_links.object(key)
		if not object.is_empty():object.version+=1;versions[object.id]=object.version
	return versions
func snapshot()->Dictionary:
	for id in shared.keys():
		if room._object_index(id)<0:shared.erase(id)
	var editing:Dictionary={}
	for id in room.locks:editing[id]=room.locks[id].player
	var state:Dictionary={"shared":shared.keys(),"locks":editing}
	if state!=previous:version+=1;previous=state.duplicate(true)
	state.version=version
	return state
