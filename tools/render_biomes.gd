extends SceneTree
## Headless biome render: a wide biome map next to a terrain map and a plant
## map, plus a legend with each biome's coverage, land mix (sand / swamp /
## grass) and plant mix (tree / bush / flower / stones).
##
## Samples one cell every `step` tiles over a `size` x `size` tile square
## centred on the origin, so the area spans several biome noise wavelengths.
## Prints per-biome coverage and exits 1 when any biome covers 0 % of the
## area, so a render that shows a single biome cannot pass silently. Also
## exits 1 when a biome's land grows no trees or bushes (BiomeCatalog.PLANTS)
## across the wide samples and its full-resolution close-up, so an emptied
## plant row cannot pass silently either.
##
## Usage:
##   godot --headless --path . --script res://tools/render_biomes.gd -- \
##     [--seed=42] [--freq=0.003] [--size=4096] [--step=8] [--out=res://artifacts/out/biomes]

const BIOME_NAMES := {
	BiomeCatalog.OCEANIC: "OCEANIC",
	BiomeCatalog.TEMPERATE: "TEMPERATE",
	BiomeCatalog.CONTINENTAL: "CONTINENTAL",
	BiomeCatalog.ARCHIPELAGO_DENSE: "ARCHIPELAGO_DENSE",
}
const BIOME_COLORS := {
	BiomeCatalog.OCEANIC: Color("1d4e89"),
	BiomeCatalog.TEMPERATE: Color("6dbf4b"),
	BiomeCatalog.CONTINENTAL: Color("b5853f"),
	BiomeCatalog.ARCHIPELAGO_DENSE: Color("e05aa8"),
}
const WATER := Color("2f6fb5")
const SAND := Color("e3d08a")
const SWAMP := Color("7b4f2a")
const GRASS := Color("58a64a")
const HILL := Color("2f6b33")
## Plant map: bare land, trees, bushes, flowers, stones (water uses WATER).
const PLANT_LAND := Color("cfc9b0")
const TREE := Color("0b2e12")
const BUSH := Color("d9a521")
const FLOWER := Color("ff4fd8")
const STONES := Color("6e6a80")
const LEGEND_W := 24
## Side, in tiles, of each per-biome close-up (drawn at 1 tile per pixel).
const CLOSE_UP := 256
const PAD := 4


func _initialize() -> void:
	call_deferred("_run")


func _args() -> Dictionary:
	var a := {"seed": "42", "freq": "0.003", "size": "4096", "step": "8", "out": "res://artifacts/out/biomes"}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var kv: PackedStringArray = arg.substr(2).split("=", true, 1)
			a[kv[0]] = kv[1]
	return a


func _run() -> void:
	var a := _args()
	var seed_v := int(a["seed"])
	var freq := float(a["freq"])
	var size := int(a["size"])
	var step := maxi(1, int(a["step"]))
	var out_prefix: String = a["out"]
	if freq <= 0.0:
		printerr("error: --freq must be > 0 (biome_frequency 0 turns biomes off)")
		quit(2)
		return

	var scene = load("res://flagoria_main.tscn").instantiate()
	root.add_child(scene)
	var world = scene.get_node("World/worldMap")

	var p := MapGenParams.make_defaults()
	p.altitude_seed = seed_v
	p.moisture_seed = seed_v + 1
	p.temperature_seed = seed_v + 2
	p.items_seed = seed_v + 3
	p.biome_seed = seed_v + 7
	p.biome_frequency = freq
	p.archipelago_spacing = 64
	p.archipelago_island_radius = 22
	p.archipelago_jitter = 0.35
	p.island_falloff = 1.5
	world.apply_map_params(p)

	var n := size / step
	var biome_img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var terrain_img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var plant_img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var counts := {}
	# Per biome: land samples and how many are sand / swamp (rest is grass).
	var land := {}
	for b in BIOME_NAMES:
		counts[b] = 0
		land[b] = {"land": 0, "sand": 0, "swamp": 0, "tree": 0, "bush": 0, "flower": 0, "stones": 0}
	for ix in range(n):
		for iy in range(n):
			var cell := Vector2i(ix * step - size / 2, iy * step - size / 2)
			var b: int = world.biome_at(cell)
			counts[b] += 1
			biome_img.set_pixel(ix, iy, BIOME_COLORS[b])
			var c := _terrain_color(world, p, cell, b)
			var pc := WATER
			if c != WATER:
				land[b]["land"] += 1
				if c == SAND:
					land[b]["sand"] += 1
				elif c == SWAMP:
					land[b]["swamp"] += 1
				pc = _plant_color(world, cell, b, c)
				if pc == TREE:
					land[b]["tree"] += 1
				elif pc == BUSH:
					land[b]["bush"] += 1
				elif pc == FLOWER:
					land[b]["flower"] += 1
				elif pc == STONES:
					land[b]["stones"] += 1
				else:
					pc = PLANT_LAND
			terrain_img.set_pixel(ix, iy, c)
			plant_img.set_pixel(ix, iy, pc)
	var close_centre := _close_up_centres(biome_img, terrain_img, CLOSE_UP / 2 / step, n, step, size)

	# Close-ups: one CLOSE_UP-tile window per biome at 1 tile per pixel, cells of
	# other biomes dimmed, so the per-biome ground mix is readable on islands.
	var row_w := BIOME_NAMES.size() * (CLOSE_UP + PAD)
	var close_img := Image.create(row_w, CLOSE_UP, false, Image.FORMAT_RGB8)
	close_img.fill(Color.BLACK)
	var k := 0
	# Per biome: land cells of that biome in its close-up, and trees + bushes on them.
	var close_land := {}
	var close_plants := {}
	for b in BIOME_NAMES:
		close_land[b] = 0
		close_plants[b] = 0
	for b in BIOME_NAMES:
		var origin: Vector2i = close_centre.get(b, Vector2i.ZERO) - Vector2i(CLOSE_UP / 2, CLOSE_UP / 2)
		for x in range(CLOSE_UP):
			for y in range(CLOSE_UP):
				var cell := origin + Vector2i(x, y)
				var cb: int = world.biome_at(cell)
				var c := _terrain_color(world, p, cell, cb)
				if c != WATER:
					c = _plant_color(world, cell, cb, c)
					if cb == b:
						close_land[b] += 1
						if c == TREE or c == BUSH:
							close_plants[b] += 1
				if cb != b:
					c = c.lerp(Color.BLACK, 0.65)
				close_img.set_pixel(k * (CLOSE_UP + PAD) + x, y, c)
		k += 1

	# Biome map | terrain | plants | legend swatches (top to bottom in id order),
	# and the close-up row below in the same order.
	var legend_h := BIOME_NAMES.size() * (LEGEND_W + PAD)
	var top_h := maxi(n, legend_h)
	var combo := Image.create(maxi(n * 3 + PAD * 3 + LEGEND_W, row_w), top_h + PAD + CLOSE_UP, false, Image.FORMAT_RGB8)
	combo.fill(Color.BLACK)
	combo.blit_rect(biome_img, Rect2i(0, 0, n, n), Vector2i(0, 0))
	combo.blit_rect(terrain_img, Rect2i(0, 0, n, n), Vector2i(n + PAD, 0))
	combo.blit_rect(plant_img, Rect2i(0, 0, n, n), Vector2i((n + PAD) * 2, 0))
	combo.blit_rect(close_img, Rect2i(0, 0, row_w, CLOSE_UP), Vector2i(0, top_h + PAD))
	var i := 0
	for b in BIOME_NAMES:
		combo.fill_rect(Rect2i(n * 3 + PAD * 3, i * (LEGEND_W + PAD), LEGEND_W, LEGEND_W), BIOME_COLORS[b])
		i += 1

	DirAccess.make_dir_recursive_absolute(out_prefix.get_base_dir())
	var png := "%s_seed_%d.png" % [out_prefix, seed_v]
	var legend_path := "%s_seed_%d_legend.txt" % [out_prefix, seed_v]
	combo.save_png(png)

	var total := n * n
	var legend := "seed=%d biome_frequency=%s area=%dx%d tiles step=%d\n" % [seed_v, str(freq), size, size, step]
	legend += "left to right: biome map, terrain (water/sand/swamp/grass/hills), plants (tree #%s, bush #%s, flower #%s, stones #%s, bare land #%s), swatches top to bottom\n" % [
		TREE.to_html(false), BUSH.to_html(false), FLOWER.to_html(false), STONES.to_html(false), PLANT_LAND.to_html(false)]
	legend += "bottom row: %d-tile close-up per biome with plants drawn, left to right in swatch order (other biomes dimmed)\n" % CLOSE_UP
	var missing: Array[String] = []
	for b in BIOME_NAMES:
		var pct: float = 100.0 * counts[b] / total
		legend += "%-18s #%s %6.2f%%\n" % [BIOME_NAMES[b], BIOME_COLORS[b].to_html(false), pct]
		if counts[b] == 0:
			missing.append(BIOME_NAMES[b])
	legend += "land mix per biome (share of that biome's land samples):\n"
	for b in BIOME_NAMES:
		var l: Dictionary = land[b]
		var n_land := maxi(1, l["land"])
		legend += "%-18s land=%6.2f%% sand=%5.1f%% swamp=%5.1f%% grass=%5.1f%%\n" % [
			BIOME_NAMES[b], 100.0 * l["land"] / maxi(1, counts[b]),
			100.0 * l["sand"] / n_land, 100.0 * l["swamp"] / n_land,
			100.0 * (l["land"] - l["sand"] - l["swamp"]) / n_land]
	legend += "plant mix per biome (share of that biome's land samples):\n"
	for b in BIOME_NAMES:
		var l: Dictionary = land[b]
		var n_land := maxi(1, l["land"])
		legend += "%-18s tree=%5.1f%% bush=%5.1f%% flower=%5.1f%% stones=%5.1f%%\n" % [
			BIOME_NAMES[b], 100.0 * l["tree"] / n_land,
			100.0 * l["bush"] / n_land, 100.0 * l["flower"] / n_land, 100.0 * l["stones"] / n_land]
	legend += "trees + bushes per biome (wide samples + close-up land cells):\n"
	var bare: Array[String] = []
	for b in BIOME_NAMES:
		var wide: int = land[b]["tree"] + land[b]["bush"]
		legend += "%-18s wide=%d of %d land  close_up=%d of %d land\n" % [
			BIOME_NAMES[b], wide, land[b]["land"], close_plants[b], close_land[b]]
		if wide + close_plants[b] == 0:
			bare.append(BIOME_NAMES[b])
	var f := FileAccess.open(legend_path, FileAccess.WRITE)
	f.store_string(legend)
	f.close()
	print(legend)
	print("saved ", ProjectSettings.globalize_path(png))
	print("saved ", ProjectSettings.globalize_path(legend_path))
	if not missing.is_empty():
		printerr("FAIL: biomes with 0%% coverage: %s (widen --size or raise --freq)" % ", ".join(missing))
		quit(1)
		return
	if not bare.is_empty():
		printerr("FAIL: biomes with land but no trees or bushes: %s (check BiomeCatalog.PLANTS)" % ", ".join(bare))
		quit(1)
		return
	print("BIOME_COVERAGE_OK")
	quit(0)


func _terrain_color(world, p: MapGenParams, cell: Vector2i, b: int) -> Color:
	## Same altitude and ground tile as generate_chunk, without filling the TileMap.
	var alt: float = world.cell_altitude(cell, b)
	var moist: float = world.moisture.get_noise_2d(cell.x, cell.y)
	var chance: float = world.items_chance.get_noise_2d(cell.x, cell.y)
	var tile: Vector2i = world.ground_tile(alt, moist, chance, b)
	if tile == TileCatalog.WATER:
		return WATER
	if tile == TileCatalog.SAND:
		return SAND
	if tile == TileCatalog.SWAMP or tile == TileCatalog.SWAMP_SPECIAL:
		return SWAMP
	if alt >= p.tree_min_alt:
		return HILL
	return GRASS


func _plant_color(world, cell: Vector2i, b: int, ground: Color) -> Color:
	## Same decoration as set_tile_type_z1 on a land cell: TREE, BUSH, FLOWER or
	## STONES, or `ground` when there is none. Beaches get no plants with biomes
	## on, only stones (BiomeCatalog.STRUCTURES).
	var chance: float = world.items_chance.get_noise_2d(cell.x, cell.y)
	var plant: Vector2i = world.NO_PLANT
	if ground != SAND:
		plant = world.plant_tile(world.cell_altitude(cell, b),
			world.moisture.get_noise_2d(cell.x, cell.y), chance, b)
	if plant == world.NO_PLANT:
		plant = world.structure_tile(chance, b)
	if plant == TileCatalog.TREE:
		return TREE
	if plant == TileCatalog.BUSH:
		return BUSH
	if plant == TileCatalog.FLOWER:
		return FLOWER
	if plant == TileCatalog.STONES:
		return STONES
	return ground


func _close_up_centres(biome_img: Image, terrain_img: Image, r: int, n: int, step: int, size: int) -> Dictionary:
	## Per biome, the sample cell whose (2r+1)-pixel window holds the most
	## samples of that biome, with its land counted four times, so close-ups of
	## small biomes still sit inside them and show islands. Uses summed-area tables.
	var centres := {}
	for b in BIOME_NAMES:
		var sat := PackedInt32Array()
		sat.resize((n + 1) * (n + 1))
		for iy in range(n):
			var row := 0
			for ix in range(n):
				if biome_img.get_pixel(ix, iy) == BIOME_COLORS[b]:
					row += 1 if terrain_img.get_pixel(ix, iy) == WATER else 5
				sat[(iy + 1) * (n + 1) + ix + 1] = sat[iy * (n + 1) + ix + 1] + row
		var best := -1
		for iy in range(n):
			for ix in range(n):
				var x0 := maxi(0, ix - r)
				var y0 := maxi(0, iy - r)
				var x1 := mini(n, ix + r + 1)
				var y1 := mini(n, iy + r + 1)
				var score := sat[y1 * (n + 1) + x1] - sat[y0 * (n + 1) + x1] - sat[y1 * (n + 1) + x0] + sat[y0 * (n + 1) + x0]
				if score > best:
					best = score
					centres[b] = Vector2i(ix * step - size / 2, iy * step - size / 2)
	return centres
