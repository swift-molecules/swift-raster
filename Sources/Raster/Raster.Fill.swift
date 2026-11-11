#if Geometry
    public import Direction

    extension Raster {
        /// The area a polygon covers of each pixel, one pixel row at a time.
        ///
        /// A row is cut into bands at every height where a side ends or two sides cross, so inside a band the
        /// sides keep their order from left to right. Walking them in that order gives the winding number
        /// between each pair of neighbours; where the rule turns from outside to inside, or back, the side is a
        /// boundary of the filled region, and the area to its right is added or taken away.
        @usableFromInline
        internal struct Fill<Scalar: BinaryFloatingPoint> {
            @usableFromInline
            internal let rule: Winding.Rule
            /// The pixel column that working column 0 stands for.
            @usableFromInline
            internal let origin: Int
            /// Per working column: the area of the pixel right of the boundaries that pass through it.
            @usableFromInline
            internal var area: [Scalar]
            /// Per working column: the band heights that start (or stop) covering every pixel from here on.
            @usableFromInline
            internal var cover: [Scalar]
            /// As `cover`, counting bands instead of adding their heights.
            @usableFromInline
            internal var full: [Int]
            /// Per working column: whether a boundary passes through the pixel in this row.
            @usableFromInline
            internal var touched: [Bool]
            @usableFromInline
            internal var bands = 0
            @usableFromInline
            internal var active: [Side] = []
            @usableFromInline
            internal var entries: [(above: Scalar, below: Scalar, turn: Int)] = []

            @inlinable
            internal init(rule: Winding.Rule, origin: Int, span: Int) {
                self.rule = rule
                self.origin = origin
                self.area = [Scalar](repeating: 0, count: span)
                self.cover = [Scalar](repeating: 0, count: span + 1)
                self.full = [Int](repeating: 0, count: span + 1)
                self.touched = [Bool](repeating: false, count: span)
            }
        }
    }

    extension Raster.Fill {
        /// Adds the area right of a boundary that runs from `above` to `below` across a band of `height`.
        /// `sign` is +1 where the filled region begins at the boundary and −1 where it ends there.
        @inlinable
        internal mutating func add(above: Scalar, below: Scalar, height: Scalar, sign: Int) {
            let span = area.count
            let base = Scalar(origin)
            let low = Swift.min(above, below) - base
            let high = Swift.max(above, below) - base
            let signed = sign > 0 ? height : -height
            guard high > 0 else {
                cover[0] += signed
                full[0] += sign
                return
            }
            guard low < Scalar(span) else { return }
            let first = low > 0 ? Int(low.rounded(.down)) : 0
            let end = high < Scalar(span) ? Int(high.rounded(.up)) : span
            if end > first {
                let rate = height / (high - low)
                if high > low, rate.isFinite {
                    var column = first
                    while column < end {
                        let left = Swift.max(low, Scalar(column))
                        let right = Swift.min(high, Scalar(column + 1))
                        let entered = (left - low) * rate
                        let departed = right == high ? height : (right - low) * rate
                        let inside = entered + (departed - entered) * (Scalar(column + 1) - (left + right) / 2)
                        area[column] += sign > 0 ? inside : -inside
                        touched[column] = true
                        column += 1
                    }
                } else {
                    area[first] += signed * (Scalar(first + 1) - low)
                    touched[first] = true
                }
            }
            cover[end] += signed
            full[end] += sign
        }

        /// Fills the band between two heights. With `splitting`, a band in which sides cross is first cut at
        /// the crossings; the pieces are then filled as they are.
        @inlinable
        internal mutating func band(from upper: Scalar, to lower: Scalar, splitting: Bool) {
            entries.removeAll(keepingCapacity: true)
            for side in active where side.top.y <= upper && side.bottom.y >= lower {
                entries.append((side.x(at: upper), side.x(at: lower), side.turn))
            }
            if splitting, entries.count > 1 {
                entries.sort { ($0.above, $0.below) < ($1.above, $1.below) }
                var crossed = false
                for index in entries.indices.dropFirst() where entries[index - 1].below > entries[index].below {
                    crossed = true
                    break
                }
                if crossed {
                    var cuts: [Scalar] = []
                    var order = entries
                    for index in order.indices.dropFirst() {
                        var position = index
                        while position > 0, order[position - 1].below > order[position].below {
                            let left = order[position - 1]
                            let right = order[position]
                            let apart = right.above - left.above
                            let cut = upper + (lower - upper) * apart / (apart + (left.below - right.below))
                            if cut > upper, cut < lower { cuts.append(cut) }
                            order.swapAt(position - 1, position)
                            position -= 1
                        }
                    }
                    if !cuts.isEmpty {
                        cuts.sort()
                        var previous = upper
                        for cut in cuts where cut > previous {
                            band(from: previous, to: cut, splitting: false)
                            previous = cut
                        }
                        band(from: previous, to: lower, splitting: false)
                        return
                    }
                }
            }
            if !splitting || entries.count > 1 {
                entries.sort { ($0.above + $0.below, $0.above) < ($1.above + $1.below, $1.above) }
            }
            let height = lower - upper
            var winding = 0
            var inside = false
            var index = 0
            while index < entries.count {
                let entry = entries[index]
                winding += entry.turn
                index += 1
                while index < entries.count, entries[index].above == entry.above, entries[index].below == entry.below {
                    winding += entries[index].turn
                    index += 1
                }
                let within = rule.contains(Winding.Number(winding))
                if within != inside {
                    add(above: entry.above, below: entry.below, height: height, sign: within ? 1 : -1)
                    inside = within
                }
            }
            bands += 1
        }

        /// Fills pixel row `row` from the active sides.
        @inlinable
        internal mutating func sweep(_ row: Int) {
            let upper = Scalar(row)
            let lower = Scalar(row + 1)
            var levels: [Scalar] = []
            for side in active {
                if side.top.y > upper, side.top.y < lower { levels.append(side.top.y) }
                if side.bottom.y > upper, side.bottom.y < lower { levels.append(side.bottom.y) }
            }
            levels.sort()
            levels.append(lower)
            bands = 0
            var previous = upper
            for level in levels where level > previous {
                band(from: previous, to: level, splitting: true)
                previous = level
            }
        }
    }

    extension Raster.Fill where Pixel: BinaryFloatingPoint {
        /// Writes the row's coverage to `output` from `offset` on, and clears the row.
        ///
        /// A pixel no boundary passes through is covered over whole bands only: all of them is exactly 1 and
        /// none exactly 0, whatever the rounding of their heights.
        @inlinable
        internal mutating func write(into output: inout [Pixel], at offset: Int) {
            var run: Scalar = 0
            var count = 0
            for column in area.indices {
                run += cover[column]
                count += full[column]
                var value = run
                if touched[column] {
                    value += area[column]
                } else if count == bands {
                    value = 1
                } else if count == 0 {
                    value = 0
                }
                if value > 0 { output[offset + column] = value < 1 ? Pixel(value) : 1 }
                area[column] = 0
                cover[column] = 0
                full[column] = 0
                touched[column] = false
            }
            cover[area.count] = 0
            full[area.count] = 0
        }

        /// The coverage of the pixels `columns` wide and `rows` tall from (`left`, `top`), row by row.
        @inlinable
        internal static func coverage(
            of sides: [Side],
            rule: Winding.Rule,
            left: Int,
            top: Int,
            columns: Int,
            rows: Int
        ) -> [Pixel] {
            var output = [Pixel](repeating: 0, count: columns * rows)
            let ceiling = Scalar(top)
            let ground = Scalar(top + rows)
            let wall = Scalar(left + columns)
            var kept = sides.filter { $0.bottom.y > ceiling && $0.top.y < ground }
            guard var lowest = kept.first?.low, var highest = kept.first?.high, var deepest = kept.first?.bottom.y else {
                return output
            }
            for side in kept {
                lowest = Swift.min(lowest, side.low)
                highest = Swift.max(highest, side.high)
                deepest = Swift.max(deepest, side.bottom.y)
            }
            kept.removeAll { $0.low >= wall }
            guard !kept.isEmpty else { return output }
            kept.sort { $0.top.y < $1.top.y }
            let firstColumn = Raster.whole(lowest, .down, from: left, to: left + columns)
            let endColumn = Raster.whole(highest, .up, from: left, to: left + columns)
            let firstRow = Raster.whole(kept[0].top.y, .down, from: top, to: top + rows)
            let endRow = Raster.whole(deepest, .up, from: top, to: top + rows)
            guard firstColumn < endColumn else { return output }

            var fill = Self(rule: rule, origin: firstColumn, span: endColumn - firstColumn)
            var next = 0
            var row = firstRow
            while row < endRow {
                let upper = Scalar(row)
                let lower = Scalar(row + 1)
                fill.active.removeAll { $0.bottom.y <= upper }
                while next < kept.count, kept[next].top.y < lower {
                    if kept[next].bottom.y > upper { fill.active.append(kept[next]) }
                    next += 1
                }
                if !fill.active.isEmpty {
                    fill.sweep(row)
                    fill.write(into: &output, at: (row - top) * columns + (firstColumn - left))
                }
                row += 1
            }
            return output
        }
    }
#endif
