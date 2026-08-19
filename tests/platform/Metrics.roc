## Test-only measurement controls supplied by the fixture host.
Metrics := [].{

	## Exclude case transport decoding from the declared fixture measurement
	## boundary. Family apps call this after typed JSON decoding and immediately
	## before dispatching into their Fixture module.
	reset_allocations! : () => {}
}
