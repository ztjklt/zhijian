extends RefCounted
## Reading a catalog window exposes identifiers and counts. Exact stroke
## coordinates are read separately through the world's scoped atlas.
const PAGE_SIZE := 8
const PARTS_PER_SHEET := 6
const Atlas := preload("res://scripts/team_atlas.gd")

static func valid_filters(value: Dictionary) -> bool:
	for field in ["name","author","part"]:
		if not value.get(field) is String or value[field].length()>160:
			return false
	for field in ["offset","part_offset"]:
		var n = value.get(field)
		if not (n is int or n is float) or not is_finite(n) or n<0 or n>2147483647 or n!=floorf(n):
			return false
	return true

static func _matches(field: String, needle: String) -> bool:
	return needle.is_empty() or field.to_lower().contains(needle.to_lower())

static func window(catalog: Array, filters: Dictionary) -> Dictionary:
	var rows := []
	var matched := 0
	var offset := int(filters.get("offset",0))
	var part_offset := int(filters.get("part_offset",0))
	for sheet: Dictionary in catalog:
		var author: String = sheet.ref.author_id
		var author_name: String = Atlas.AUTHORS.get(author,author)
		if not _matches(sheet.name+" "+sheet.work_id,filters.get("name","")) or not _matches(author+" "+author_name,filters.get("author","")):
			continue
		var parts: Array = sheet.parts.filter(func(p): return _matches(p.id+" "+p.label,filters.get("part","")))
		if parts.is_empty(): continue
		matched += 1
		if matched<=offset or rows.size()>=PAGE_SIZE:continue
		var visible_parts := []
		for part: Dictionary in parts.slice(part_offset,part_offset+PARTS_PER_SHEET):
			visible_parts.append({"id":part.id,"label":part.label,"count":part.strokes.size()})
		rows.append({"work_id":sheet.work_id,"name":sheet.name,"author_id":author,"author":author_name,
			"parts":visible_parts,"part_total":parts.size(),"next_part_offset":part_offset+PARTS_PER_SHEET if part_offset+PARTS_PER_SHEET<parts.size() else null})
	return {"rows":rows,"catalog_total":catalog.size(),"matched":matched,"offset":offset,"part_offset":part_offset,
		"filters":filters,"next_offset":offset+PAGE_SIZE if offset+PAGE_SIZE<matched else null}
