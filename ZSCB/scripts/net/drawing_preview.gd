extends RefCounted
## Display-only sampling. Never change the full draft used for generation/save.
const MAX_PATHS := 128
const MAX_POINTS := 500
const MAX_PER_PATH := 40

static func sample(paths: Array) -> Array:
	var sources: Array = []
	var counts: Array[int] = []
	var remaining := MAX_POINTS
	for path in paths:
		if sources.size() >= MAX_PATHS: break
		if not path is Dictionary or not path.get("points") is Array or path.points.is_empty(): continue
		var points: Array = path.points
		var count := mini(2,points.size())
		sources.append(points); counts.append(count); remaining -= count
	# Reserve the ends of every stroke before fairly distributing extra detail.
	while remaining > 0:
		var allocated := false
		for i in sources.size():
			if counts[i] >= mini(MAX_PER_PATH,sources[i].size()): continue
			counts[i] += 1; remaining -= 1; allocated = true
			if remaining == 0: break
		if not allocated: break
	var result: Array = []
	for i in sources.size():
		var points: Array = sources[i]
		var sampled: Array = []
		for j in counts[i]:
			var index := roundi(float(j)*float(points.size()-1)/float(counts[i]-1)) if counts[i]>1 else 0
			sampled.append(points[index])
		result.append({"points":sampled})
	return result
