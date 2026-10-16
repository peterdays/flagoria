extends SceneTree
## Headless biome render: a wide biome map next to a terrain map, plus a legend.
##
## Samples one cell every `step` tiles over a `size` x `size` tile square
## centred on the origin, so the area spans several biome noise wavelengths.
## Prints per-biome coverage and exits 1 when any biome covers 0 % of the
## area, so a render that shows a single biome cannot pass silently.
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
const GRASS := Color("58a64a")
const HILL := Color("2f6b33")
const LEGEND_W := 24
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
	var counts := {}
	for b in BIOME_NAMES:
		counts[b] = 0
	for ix in range(n):
		for iy in range(n):
			var cell := Vector2i(ix * step - size / 2, iy * step - size / 2)
			var b: int = world.biome_at(cell)
			counts[b] += 1
			biome_img.set_pixel(ix, iy, BIOME_COLORS[b])
			# Same altitude chain as generate_chunk, without filling the TileMap.
			var alt: float = world.altitude.get_noise_2d(cell.x, cell.y) + BiomeCatalog.altitude_bias(b)
			alt = world.archipelago_altitude(cell, world.island_altitude(cell, alt))
			var c := GRASS
			if alt < p.water_max_alt:
				c = WATER
			elif alt < p.sand_max_alt:
				c = SAND
			elif alt >= p.tree_min_alt:
				c = HILL
			terrain_img.set_pixel(ix, iy, c)

	# Side by side: biome map | terrain | legend swatches (top to bottom in id order).
	var legend_h := BIOME_NAMES.size() * (LEGEND_W + PAD)
	var combo := Image.create(n * 2 + PAD * 2 + LEGEND_W, maxi(n, legend_h), false, Image.FORMAT_RGB8)
	combo.fill(Color.BLACK)
	combo.blit_rect(biome_img, Rect2i(0, 0, n, n), Vector2i(0, 0))
	combo.blit_rect(terrain_img, Rect2i(0, 0, n, n), Vector2i(n + PAD, 0))
	var i := 0
	for b in BIOME_NAMES:
		combo.fill_rect(Rect2i(n * 2 + PAD * 2, i * (LEGEND_W + PAD), LEGEND_W, LEGEND_W), BIOME_COLORS[b])
		i += 1

	DirAccess.make_dir_recursive_absolute(out_prefix.get_base_dir())
	var png := "%s_seed_%d.png" % [out_prefix, seed_v]
	var legend_path := "%s_seed_%d_legend.txt" % [out_prefix, seed_v]
	combo.save_png(png)

	var total := n * n
	var legend := "seed=%d biome_frequency=%s area=%dx%d tiles step=%d\n" % [seed_v, str(freq), size, size, step]
	legend += "left: biome map, middle: terrain (water/sand/grass/hills), right: swatches top to bottom\n"
	var missing: Array[String] = []
	for b in BIOME_NAMES:
		var pct: float = 100.0 * counts[b] / total
		legend += "%-18s #%s %6.2f%%\n" % [BIOME_NAMES[b], BIOME_COLORS[b].to_html(false), pct]
		if counts[b] == 0:
			missing.append(BIOME_NAMES[b])
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
	print("BIOME_COVERAGE_OK")
	quit(0)
