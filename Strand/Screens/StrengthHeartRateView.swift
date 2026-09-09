import SwiftUI
import StrandDesign

struct StrengthHeartRateView: View {
    let bpm: Int?
    let scale: StrengthZoneScale
    let elapsed: String
    var compact = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("HEART RATE").tracking(1.5)
                Spacer()
                Text("\(elapsed) elapsed").monospacedDigit()
            }.font(.caption).foregroundStyle(StrandPalette.textSecondary)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 20) { reading; Spacer(minLength: 0); zone }
                VStack(alignment: .leading, spacing: 8) { reading; zone }
            }
            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .topLeading) {
                    ZStack(alignment: .leading) {
                        ForEach(scale.bands()) { band in
                            Rectangle().fill(strengthZoneColor(band.id))
                                .frame(width: width * (scale.fraction(band.upper) - scale.fraction(band.lower)))
                                .offset(x: width * scale.fraction(band.lower))
                        }
                    }.frame(width: width, height: 16, alignment: .leading).clipShape(Capsule())
                    if let bpm {
                        Capsule().fill(.white).frame(width: 3, height: 23)
                            .overlay(alignment: .top) { Circle().fill(.white).frame(width: 7, height: 7) }
                            .offset(x: max(0, min(width - 3, width * scale.fraction(Double(bpm)) - 1.5)), y: -4)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: bpm)
                    }
                    ForEach(scale.visibleTicks(width: width), id: \.self) { tick in
                        Text("\(Int(tick))").font(.caption2).monospacedDigit()
                            .foregroundStyle(StrandPalette.textSecondary)
                            .position(x: max(14, min(width - 14, width * scale.fraction(tick))), y: 30)
                    }
                }
            }.frame(height: 40).accessibilityHidden(true)
            if let bpm {
                Text(scale.nextBoundary(for: bpm)).font(.caption).foregroundStyle(StrandPalette.textSecondary)
            }
        }.padding(compact ? 12 : 16)
            .background(StrandPalette.surfaceRaised, in: RoundedRectangle(cornerRadius: 16))
    }
    private var reading: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(bpm.map(String.init) ?? "—").font(.system(size: compact ? 40 : 52, weight: .bold, design: .rounded)).monospacedDigit()
            Text("bpm").font(.subheadline).foregroundStyle(StrandPalette.textSecondary)
        }.fixedSize(horizontal: true, vertical: false)
    }
    private var zone: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let bpm {
                Text(StrengthZoneScale.name(scale.number(for: bpm))).font(.title3.bold()).foregroundStyle(StrandPalette.accent)
                Text(scale.range(scale.number(for: bpm))).font(.caption).foregroundStyle(StrandPalette.textSecondary)
            } else {
                Text("Waiting for live heart rate").font(.subheadline).foregroundStyle(StrandPalette.textSecondary)
            }
        }.fixedSize(horizontal: false, vertical: true)
    }
}

func strengthZoneColor(_ number: Int) -> Color {
    number == 0 ? .gray : StrandPalette.hrZones[number]
}
