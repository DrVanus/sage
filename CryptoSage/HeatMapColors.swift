import Foundation

public enum HeatMapColors {
    public struct Tuning {
        public let neg: (Double, Double, Double)
        public let neu: (Double, Double, Double)
        public let pos: (Double, Double, Double)
        public let deadband: Double
        public let gamma: Double
        public let satMin: Double
        public let satMax: Double
        public let darkBase: Double
        public let darkCap: Double

        public init(
            neg: (Double, Double, Double),
            neu: (Double, Double, Double),
            pos: (Double, Double, Double),
            deadband: Double,
            gamma: Double,
            satMin: Double,
            satMax: Double,
            darkBase: Double,
            darkCap: Double
        ) {
            self.neg = neg
            self.neu = neu
            self.pos = pos
            self.deadband = deadband
            self.gamma = gamma
            self.satMin = satMin
            self.satMax = satMax
            self.darkBase = darkBase
            self.darkCap = darkCap
        }
    }

    public static func tuning(for palette: ColorPalette, grayNeutral: Bool) -> Tuning {
        switch palette {
        case .warm:
            let neg = (0.88, 0.22, 0.12)
            let neu = grayNeutral ? (0.46, 0.46, 0.46) : (1.00, 0.74, 0.12)
            let pos = (0.02, 0.66, 0.38)
            let deadband = grayNeutral ? 0.03 : 0.00
            let gamma = grayNeutral ? 1.12 * 1.02 : 1.12
            let satMin = 0.80
            let satMax = 1.15
            let darkBase = 0.06
            let darkCap = 0.30
            return Tuning(
                neg: neg,
                neu: neu,
                pos: pos,
                deadband: deadband,
                gamma: gamma,
                satMin: satMin,
                satMax: satMax,
                darkBase: darkBase,
                darkCap: darkCap
            )
        case .classic:
            let neg = (0.839, 0.306, 0.306)
            let neu = grayNeutral ? (0.65, 0.65, 0.65) : (1.000, 0.827, 0.000)
            let pos = (0.307, 0.788, 0.416)
            let deadband = 0.03
            let gamma = 0.85
            let satMin = 0.80
            let satMax = 1.12
            let darkBase = 0.06
            let darkCap = 0.30
            return Tuning(
                neg: neg,
                neu: neu,
                pos: pos,
                deadband: deadband,
                gamma: gamma,
                satMin: satMin,
                satMax: satMax,
                darkBase: darkBase,
                darkCap: darkCap
            )
        case .cool:
            let neg = (0.16, 0.36, 0.72)
            let neu = (0.64, 0.64, 0.66)
            let pos = (0.98, 0.72, 0.12)
            let deadband = 0.03
            let gamma = 0.90
            let satMin = 0.78
            let satMax = 1.08
            let darkBase = 0.05
            let darkCap = 0.28
            return Tuning(
                neg: neg,
                neu: neu,
                pos: pos,
                deadband: deadband,
                gamma: gamma,
                satMin: satMin,
                satMax: satMax,
                darkBase: darkBase,
                darkCap: darkCap
            )
        }
    }
}
