import Foundation
import CoreGraphics

struct RenderedAthlete {
    let id = UUID()
    let position: CGPoint
}

func squaredDistance(from p1: CGPoint, to p2: CGPoint) -> CGFloat {
    let dx = p1.x - p2.x
    let dy = p1.y - p2.y
    return dx * dx + dy * dy
}

func collisionSummaryOriginal(
    in athletes: [RenderedAthlete],
    minDistance: CGFloat = 2.0
) -> (count: Int, ids: Set<UUID>) {
    guard athletes.count > 1 else { return (0, []) }

    let minDistanceSquared = minDistance * minDistance
    var count = 0
    var ids = Set<UUID>()

    for firstIndex in 0..<athletes.count {
        for secondIndex in (firstIndex + 1)..<athletes.count {
            if squaredDistance(from: athletes[firstIndex].position, to: athletes[secondIndex].position)
                < minDistanceSquared
            {
                count += 1
                ids.insert(athletes[firstIndex].id)
                ids.insert(athletes[secondIndex].id)
            }
        }
    }

    return (count, ids)
}

func collisionSummaryOptimized(
    in athletes: [RenderedAthlete],
    minDistance: CGFloat = 2.0
) -> (count: Int, ids: Set<UUID>) {
    guard athletes.count > 1 else { return (0, []) }

    let minDistanceSquared = minDistance * minDistance
    let cellSize = max(minDistance, 0.1) // Ensure we don't divide by zero

    struct GridCell: Hashable {
        let x: Int
        let y: Int
    }

    var grid: [GridCell: [Int]] = [:]
    for (index, athlete) in athletes.enumerated() {
        let cellX = Int(floor(athlete.position.x / cellSize))
        let cellY = Int(floor(athlete.position.y / cellSize))
        let cell = GridCell(x: cellX, y: cellY)
        grid[cell, default: []].append(index)
    }

    var count = 0
    var ids = Set<UUID>()

    // To deduplicate pairs efficiently, we can use a Set of Int64 representing the pair of indices.
    var seenPairs = Set<Int64>()

    for (index, athlete) in athletes.enumerated() {
        let cellX = Int(floor(athlete.position.x / cellSize))
        let cellY = Int(floor(athlete.position.y / cellSize))

        for cx in (cellX - 1)...(cellX + 1) {
            for cy in (cellY - 1)...(cellY + 1) {
                let cell = GridCell(x: cx, y: cy)
                if let cellIndices = grid[cell] {
                    for otherIndex in cellIndices {
                        if otherIndex > index {
                            let aPos = athlete.position
                            let bPos = athletes[otherIndex].position
                            if squaredDistance(from: aPos, to: bPos) < minDistanceSquared {
                                count += 1
                                ids.insert(athlete.id)
                                ids.insert(athletes[otherIndex].id)
                            }
                        }
                    }
                }
            }
        }
    }

    return (count, ids)
}

// Performance Test
let count = 1000
var athletes = [RenderedAthlete]()
for _ in 0..<count {
    athletes.append(RenderedAthlete(position: CGPoint(x: CGFloat.random(in: 0...100), y: CGFloat.random(in: 0...100))))
}

let start1 = CFAbsoluteTimeGetCurrent()
let res1 = collisionSummaryOriginal(in: athletes)
let end1 = CFAbsoluteTimeGetCurrent()
print("Original time: \(end1 - start1)")
print("Original result: \(res1.count), \(res1.ids.count)")

let start2 = CFAbsoluteTimeGetCurrent()
let res2 = collisionSummaryOptimized(in: athletes)
let end2 = CFAbsoluteTimeGetCurrent()
print("Optimized time: \(end2 - start2)")
print("Optimized result: \(res2.count), \(res2.ids.count)")
