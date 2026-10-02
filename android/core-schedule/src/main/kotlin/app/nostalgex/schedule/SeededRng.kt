package app.nostalgex.schedule

/** splitmix64 mixer. Mirrors `splitmix64` in SchedulePoolOrdering.swift (wrapping arithmetic). */
fun splitmix64(x: ULong): ULong {
    var z = x + 0x9E3779B97F4A7C15UL
    z = (z xor (z shr 30)) * 0xBF58476D1CE4E5B9UL
    z = (z xor (z shr 27)) * 0x94D049BB133111EBUL
    return z xor (z shr 31)
}

/** High 64 bits of the unsigned 128-bit product a*b (portable: no Math.multiplyHigh on old Android). */
internal fun unsignedMultiplyHigh(a: ULong, b: ULong): ULong {
    val mask = 0xFFFFFFFFUL
    val aLo = a and mask; val aHi = a shr 32
    val bLo = b and mask; val bHi = b shr 32
    val ll = aLo * bLo
    val lh = aLo * bHi
    val hl = aHi * bLo
    val hh = aHi * bHi
    val mid = (ll shr 32) + (lh and mask) + (hl and mask)
    return hh + (lh shr 32) + (hl shr 32) + (mid shr 32)
}

/**
 * Mirrors Swift `SeededRNG`: splitmix64-seeded xorshift64, plus the Swift stdlib's
 * bounded draw (Lemire nearly-divisionless) used by `shuffle(using:)`. Bit-identical
 * output to tvOS and the web tuner is what keeps all three airing the same program.
 */
class SeededRng(seed: ULong) {
    private var state: ULong = splitmix64(seed).let { if (it == 0UL) 1UL else it }

    fun next(): ULong {
        state = state xor (state shl 13)
        state = state xor (state shr 7)
        state = state xor (state shl 17)
        return state
    }

    /** Uniform value in `0 until upperBound`. */
    fun nextBounded(upperBound: Int): Int {
        require(upperBound > 0)
        val u = upperBound.toULong()
        var x = next()
        var high = unsignedMultiplyHigh(x, u)
        var low = x * u
        if (low < u) {
            val t = (0UL - u) % u
            while (low < t) {
                x = next()
                high = unsignedMultiplyHigh(x, u)
                low = x * u
            }
        }
        return high.toInt()
    }
}

/** Mirrors Swift `MutableCollection.shuffle(using:)`. Returns a new list. */
fun <T> List<T>.swiftShuffled(rng: SeededRng): List<T> {
    val arr = toMutableList()
    var amount = arr.size
    var current = 0
    while (amount > 1) {
        val random = rng.nextBounded(amount)
        amount -= 1
        val j = current + random
        val tmp = arr[current]; arr[current] = arr[j]; arr[j] = tmp
        current += 1
    }
    return arr
}
