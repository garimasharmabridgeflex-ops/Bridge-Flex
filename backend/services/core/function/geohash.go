package function

// geohashPrefix computes a standard geohash string truncated to `precision`
// characters — coarse enough to hide exact coordinates while still being a
// queryable/range-able string field. Implemented locally (no dependency) since
// it's ~30 lines of well-known bit-interleaving, not worth a module for.
func geohashPrefix(lat, lng float64, precision int) string {
	const base32 = "0123456789bcdefghjkmnpqrstuvwxyz"
	latRange := [2]float64{-90, 90}
	lngRange := [2]float64{-180, 180}

	buf := make([]byte, 0, precision)
	bitIdx := 0
	bitVal := 0
	evenBit := true

	for len(buf) < precision {
		if evenBit {
			mid := (lngRange[0] + lngRange[1]) / 2
			if lng >= mid {
				bitVal = bitVal<<1 | 1
				lngRange[0] = mid
			} else {
				bitVal = bitVal << 1
				lngRange[1] = mid
			}
		} else {
			mid := (latRange[0] + latRange[1]) / 2
			if lat >= mid {
				bitVal = bitVal<<1 | 1
				latRange[0] = mid
			} else {
				bitVal = bitVal << 1
				latRange[1] = mid
			}
		}
		evenBit = !evenBit
		bitIdx++
		if bitIdx == 5 {
			buf = append(buf, base32[bitVal])
			bitIdx = 0
			bitVal = 0
		}
	}
	return string(buf)
}
