extends Inventory
## Test stub for #380 item 3: reports a wood count but spend always fails, so
## BuildCosts.buy can hit SPEND_FAILED after the writer has already run.


func spend(_resource: StringName, _amount: int) -> bool:
	return false
