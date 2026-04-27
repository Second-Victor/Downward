import Foundation

nonisolated struct TextLineMetrics: Equatable, Sendable {
    let lineStartLocations: [Int]

    init(text: String) {
        let nsText = text as NSString
        let length = nsText.length

        guard length > 0 else {
            lineStartLocations = [0]
            return
        }

        var starts = [0]
        var location = 0

        while location < length {
            let scalar = nsText.character(at: location)
            if scalar == 0x0D {
                location += 1
                if location < length, nsText.character(at: location) == 0x0A {
                    location += 1
                }
                starts.append(location)
                continue
            }

            if scalar == 0x0A {
                location += 1
                starts.append(location)
                continue
            }

            location += 1
        }

        lineStartLocations = starts
    }

    var lineCount: Int {
        lineStartLocations.count
    }

    func lineNumber(at location: Int) -> Int {
        guard lineStartLocations.isEmpty == false else {
            return 1
        }

        var lowerBound = 0
        var upperBound = lineStartLocations.count - 1
        var resolvedIndex = 0

        while lowerBound <= upperBound {
            let midpoint = (lowerBound + upperBound) / 2
            if lineStartLocations[midpoint] <= location {
                resolvedIndex = midpoint
                lowerBound = midpoint + 1
            } else {
                upperBound = midpoint - 1
            }
        }

        return resolvedIndex + 1
    }
}
