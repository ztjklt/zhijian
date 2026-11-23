extends RefCounted
## Page zero keeps the original save field. Later leaves have consecutive integer
## addresses. Revisions and work IDs stay global across every physical join.
const SIZE := 64

static func page_of(revision:int) -> int:
	return revision / SIZE

static func split(chain:Array) -> Dictionary:
	if chain.is_empty():return {}
	var state:={"east_segments":chain.slice(0,SIZE)}
	var pages:=[]
	for first in range(SIZE,chain.size(),SIZE):
		var leaf:=chain.slice(first,first+SIZE)
		pages.append({"index":page_of(first),"first_revision":first,"origin":leaf[0].points[0].duplicate(),"segments":leaf})
	if not pages.is_empty():state.east_pages={"version":1,"leaves":pages}
	return state

static func joined(state:Dictionary) -> Variant:
	var first=state.get("east_segments",[])
	if not first is Array:return null
	if not state.has("east_pages"):return first
	var archive=state.east_pages
	if first.size()!=SIZE or not archive is Dictionary or archive.get("version")!=1 or not archive.get("leaves") is Array or archive.leaves.is_empty():return null
	var chain:Array=first.duplicate()
	for page in archive.leaves:
		if not page is Dictionary or page.get("index")!=page_of(chain.size()) or page.get("first_revision")!=chain.size() or chain.size()%SIZE!=0:return null
		var segments=page.get("segments")
		if not segments is Array or segments.is_empty() or segments.size()>SIZE:return null
		if not segments[0] is Dictionary or not segments[0].get("points") is Array or segments[0].points.is_empty() or page.get("origin")!=segments[0].points[0]:return null
		chain.append_array(segments)
	return chain

## Requiring a resolvable short nib movement protects the actor from an
## accepted stroke which cannot advance in this native physics coordinate frame.
static func usable(edge:Vector2) -> bool:
	return edge.is_finite() and edge.x+.04!=edge.x and (Vector2(edge.x+.04,edge.y)-edge).length()>=.02 and (Vector2(edge.x+.04,edge.y)-edge).length()<=.06

