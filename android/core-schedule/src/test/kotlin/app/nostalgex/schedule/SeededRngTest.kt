package app.nostalgex.schedule

import kotlin.test.Test
import kotlin.test.assertEquals

/** Expected values were produced by the JS port in scripts/nostalgex-daily-manifest.js, which is verified against Swift. */
class SeededRngTest {
    @Test fun `splitmix64 matches reference`() {
        assertEquals(16294208416658607535UL, splitmix64(0UL))
        assertEquals(10451216379200822465UL, splitmix64(1UL))
    }

    @Test fun `next stream matches reference`() {
        val r = SeededRng(1UL)
        assertEquals(listOf(8247328468710148152UL, 15170175812956362920UL, 5131574324960119705UL), List(3) { r.next() })
        val r2 = SeededRng(20001UL)
        assertEquals(listOf(15181763998978288762UL, 16850243645888505506UL, 9079970191903007087UL), List(3) { r2.next() })
        val r3 = SeededRng(123456789012UL)
        assertEquals(listOf(9728476311485551245UL, 13318364420974108136UL, 1984844282022469203UL), List(3) { r3.next() })
    }

    @Test fun `bounded draw matches reference`() {
        assertEquals(listOf(4, 8, 2, 9, 2, 3, 7, 5), SeededRng(1UL).let { r -> List(8) { r.nextBounded(10) } })
        assertEquals(listOf(8, 9, 4, 3, 2, 2, 9, 2), SeededRng(20001UL).let { r -> List(8) { r.nextBounded(10) } })
        assertEquals(listOf(5, 7, 1, 1, 4, 3, 9, 4), SeededRng(123456789012UL).let { r -> List(8) { r.nextBounded(10) } })
    }

    @Test fun `swift shuffle matches reference`() {
        val ids = (0..9).toList()
        assertEquals(listOf(4, 8, 0, 9, 5, 6, 1, 2, 3, 7), ids.swiftShuffled(SeededRng(1UL)))
        assertEquals(listOf(8, 9, 5, 2, 3, 6, 1, 7, 4, 0), ids.swiftShuffled(SeededRng(20001UL)))
        assertEquals(listOf(5, 7, 2, 4, 6, 3, 9, 8, 1, 0), ids.swiftShuffled(SeededRng(123456789012UL)))
    }

    @Test fun `shuffle does not mutate input and handles tiny lists`() {
        val src = listOf(1, 2, 3)
        src.swiftShuffled(SeededRng(5UL))
        assertEquals(listOf(1, 2, 3), src)
        assertEquals(emptyList(), emptyList<Int>().swiftShuffled(SeededRng(5UL)))
        assertEquals(listOf(9), listOf(9).swiftShuffled(SeededRng(5UL)))
    }
}
