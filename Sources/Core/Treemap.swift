// La disposizione della mappa a rettangoli: algoritmo "squarified" (Bruls, Huizing, van Wijk), lo stesso di
// GrandPerspective. Rettangoli il più possibile quadrati, così le dimensioni si confrontano a occhio.
// Solo geometria: chi disegna sta nell'app.

import CoreGraphics

enum Treemap {
    /// I rettangoli per `sizes` (già dal più grande, tutti > 0) dentro `rect`, nello stesso ordine.
    static func layout(_ sizes: [Double], in rect: CGRect) -> [CGRect] {
        var result = [CGRect](repeating: .zero, count: sizes.count)
        let total = sizes.reduce(0, +)
        guard total > 0, rect.width > 0, rect.height > 0 else { return result }
        let scale = Double(rect.width * rect.height) / total
        let areas = sizes.map { max(0, $0) * scale }

        var remaining = rect
        var i = 0
        while i < areas.count {
            let short = Double(min(remaining.width, remaining.height))
            guard short > 0 else { break }
            var sum = areas[i], smallest = areas[i], largest = areas[i]
            var worst = ratio(sum: sum, smallest: smallest, largest: largest, side: short)
            var j = i + 1
            while j < areas.count {
                let a = areas[j]
                let next = ratio(sum: sum + a, smallest: min(smallest, a), largest: max(largest, a), side: short)
                if next > worst { break }
                sum += a
                smallest = min(smallest, a)
                largest = max(largest, a)
                worst = next
                j += 1
            }
            guard sum > 0 else { break }
            if remaining.width >= remaining.height {
                // una colonna a sinistra, alta quanto lo spazio che resta
                let w = sum / Double(remaining.height)
                var y = Double(remaining.minY)
                for k in i..<j {
                    let h = areas[k] / w
                    result[k] = CGRect(x: Double(remaining.minX), y: y, width: w, height: h)
                    y += h
                }
                remaining = CGRect(x: remaining.minX + w, y: remaining.minY,
                                   width: max(0, remaining.width - w), height: remaining.height)
            } else {
                // una riga in alto, larga quanto lo spazio che resta
                let h = sum / Double(remaining.width)
                var x = Double(remaining.minX)
                for k in i..<j {
                    let w = areas[k] / h
                    result[k] = CGRect(x: x, y: Double(remaining.minY), width: w, height: h)
                    x += w
                }
                remaining = CGRect(x: remaining.minX, y: remaining.minY + h,
                                   width: remaining.width, height: max(0, remaining.height - h))
            }
            i = j
        }
        return result
    }

    /// Il rapporto peggiore tra i lati dei rettangoli di una fila: più vicino a 1, più quadrati.
    private static func ratio(sum: Double, smallest: Double, largest: Double, side: Double) -> Double {
        guard sum > 0, smallest > 0 else { return .infinity }
        let s2 = sum * sum, w2 = side * side
        return max(w2 * largest / s2, s2 / (w2 * smallest))
    }
}
