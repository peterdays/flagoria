class_name ResourceHud
extends HBoxContainer
## The local player's wood count, centred at the top of the screen: the wood
## icon and the count. It uses the sibling HeartsHud's pixel scale and top
## margin, so it stays crisp and lined up with the hearts on any screen.

const ICON := preload("res://art/ui/ui_wood_icon.png")

var label: Label
var _inventory: Inventory


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_theme_constant_override("separation", 2)
	var icon := TextureRect.new()
	icon.texture = ICON
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(icon)
	label = Label.new()
	label.text = "0"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)


func _process(_delta: float) -> void:
	follow_hearts()


func follow_hearts() -> void:
	var hearts := get_node_or_null("../HeartsHud") as Control
	if hearts == null:
		return
	reset_size()
	scale = hearts.scale
	position = Vector2(roundf((get_viewport_rect().size.x - size.x * scale.x) / 2.0), hearts.position.y)


func bind(inventory: Inventory) -> void:
	## Follow the wood count in `inventory` and show the counter.
	_inventory = inventory
	if not inventory.changed.is_connected(_on_changed):
		inventory.changed.connect(_on_changed)
	label.text = str(inventory.count_of(Inventory.WOOD))
	follow_hearts()
	show()


func _on_changed(resource: StringName, count: int) -> void:
	if resource == Inventory.WOOD:
		label.text = str(count)
