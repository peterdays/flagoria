class_name WorldSeeder

var alt_seed: int
var moist_seed: int
var temp_seed: int
var items_chance: int

func _init():
	self.alt_seed = randi()
	self.moist_seed = randi()
	self.temp_seed = randi()
	self.items_chance = randi()
