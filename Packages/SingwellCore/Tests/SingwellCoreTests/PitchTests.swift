import XCTest
@testable import SingwellCore

final class PitchTests: XCTestCase {
    func signal(_ hz: Double, _ sr: Double, harmonic: Bool = false) -> [Float] {
        let n = sr > 48000 ? 8192 : 4096
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let a: Double = 2 * Double.pi * hz * Double(i) / sr
            var v: Double = 0.3 * sin(a)
            if harmonic {
                let h1: Double = 0.1 * sin(a)
                let h2: Double = 0.3 * sin(2 * a)
                let h3: Double = 0.15 * sin(3 * a)
                v = h1 + h2 + h3
            }
            out[i] = Float(v)
        }
        return out
    }

    func testCorrectNotesAcrossRangeAndSampleRates() {
        for sr in [44100.0, 48000.0, 96000.0] {
            for midi in [24, 28, 36, 41, 48, 57, 59, 60, 61, 62, 63, 64, 65, 67, 69, 72, 84, 96] {
                for harmonic in [false, true] {
                    let result = Pitch.detect(signal(Pitch.midiToFrequency(Double(midi)), sr, harmonic: harmonic), sampleRate: sr)
                    XCTAssertNotNil(result, "\(midi)/\(sr)/\(harmonic)")
                    if let result {
                        XCTAssertLessThan(abs(Pitch.frequencyToMidi(result.frequency) - Double(midi)) * 100, 8, "\(midi)/\(sr)/\(harmonic): \(result.frequency)")
                    }
                }
            }
        }
    }

    func testChartBoundsExpand() {
        XCTAssertEqual(Pitch.chartBounds([]).low, 35); XCTAssertEqual(Pitch.chartBounds([]).high, 85)
        let wide = Pitch.chartBounds([24, 63, 96])
        XCTAssertEqual(wide.low, 23); XCTAssertEqual(wide.high, 97)
        for note in [24.0, 41, 63, 85, 96] {
            let b = Pitch.chartBounds([note])
            XCTAssertTrue(Double(b.low) <= note && Double(b.high) >= note)
            XCTAssertTrue(b.low < 63 && b.high > 63)
        }
        let junk = Pitch.chartBounds([.nan, .infinity])
        XCTAssertEqual(junk.low, 35); XCTAssertEqual(junk.high, 85)
    }

    func testRejectsSilenceDCQuietAndNoise() {
        XCTAssertNil(Pitch.detect([Float](repeating: 0, count: 4096), sampleRate: 48000))
        XCTAssertNil(Pitch.detect([Float](repeating: 0.4, count: 4096), sampleRate: 48000))
        XCTAssertNil(Pitch.detect(signal(311.13, 48000).map { $0 * 0.001 }, sampleRate: 48000))
        var seed: UInt32 = 34
        let noise: [Float] = (0..<4096).map { _ in
            seed = seed &* 1664525 &+ 1013904223
            return Float((Double(seed) / 4294967296.0 - 0.5) * 0.5)
        }
        XCTAssertNil(Pitch.detect(noise, sampleRate: 48000))
    }

    func testNamesAndCents() {
        XCTAssertEqual(Pitch.noteName(63), "D♯4")
        XCTAssertEqual(Pitch.noteName(57), "A3")
        XCTAssertEqual(Pitch.noteName(69), "A4")
        XCTAssertEqual(Pitch.noteName(24), "C1")
        XCTAssertLessThan(abs((Pitch.frequencyToMidi(Pitch.midiToFrequency(63) * pow(2, 0.3 / 12)) - 63) * 100 - 30), 0.0001)
        XCTAssertLessThan(abs(Pitch.frequencyToMidi(440) - Pitch.frequencyToMidi(220) - 12), 0.0001)
        XCTAssertEqual(Pitch.cents(60.3), 30)
        XCTAssertEqual(Pitch.cents(59.8), -20)
        XCTAssertNil(Pitch.cents(nil))
        XCTAssertTrue(Pitch.isBlackKey(61)); XCTAssertFalse(Pitch.isBlackKey(60))
    }

    func testDetectionIsFastEnoughForLiveUse() {
        let s = signal(220, 48000, harmonic: true)
        measure { _ = Pitch.detect(s, sampleRate: 48000) }
    }
}
