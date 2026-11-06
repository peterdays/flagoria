extends Inventory
## Test stub for #380 item 3: reports a wood count but spend always fails.
## BuildCosts.buy spends before it writes, so with this stub buy returns
## spend failed and never calls the writer.


func spend(_resource: StringName, _amount: int) -> bool:
	return false
