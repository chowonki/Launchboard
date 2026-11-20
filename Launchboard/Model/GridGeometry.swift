//
//  GridGeometry.swift
//  Launchboard
//

import SwiftUI

// MARK: - 격자 계산

struct GridMetrics: Equatable {
    var size: CGSize
    var insets: EdgeInsets
    let cols = Config.columns
    let rows = Config.rows

    init(size: CGSize = CGSize(width: 1440, height: 900), insets: EdgeInsets = EdgeInsets()) {
        self.size = size
        self.insets = insets
    }

    var perPage: Int { cols * rows }

    var gridRect: CGRect {
        let top = insets.top + 100
        let bottom = insets.bottom + 70
        let side = max(insets.leading, insets.trailing) + max(50, size.width * 0.09)
        return CGRect(x: side, y: top,
                      width: max(300, size.width - side * 2),
                      height: max(250, size.height - top - bottom))
    }

    var cellW: CGFloat { gridRect.width / CGFloat(cols) }
    var cellH: CGFloat { gridRect.height / CGFloat(rows) }
    var iconSize: CGFloat { min(min(cellW * 0.66, cellH * 0.64), 128) }

    func center(index: Int, currentPage: Int, offset: CGFloat) -> CGPoint {
        let page = index / perPage
        let slot = index % perPage
        let col = slot % cols
        let row = slot / cols
        let x = gridRect.minX + (CGFloat(col) + 0.5) * cellW + CGFloat(page - currentPage) * size.width + offset
        let y = gridRect.minY + (CGFloat(row) + 0.5) * cellH
        return CGPoint(x: x, y: y)
    }

    func slot(at p: CGPoint) -> Int? {
        guard gridRect.contains(p) else { return nil }
        let col = min(cols - 1, max(0, Int((p.x - gridRect.minX) / cellW)))
        let row = min(rows - 1, max(0, Int((p.y - gridRect.minY) / cellH)))
        return row * cols + col
    }
}

struct FolderGeometry {
    static let header: CGFloat = 76
    static let pad: CGFloat = 24
    let rect: CGRect
    let cols: Int
    let cellW: CGFloat
    let cellH: CGFloat
    let iconSize: CGFloat

    init(count: Int, metrics m: GridMetrics) {
        cols = m.cols
        cellW = m.cellW
        let rows = max(1, (count + m.cols - 1) / m.cols)
        let available = m.size.height - m.insets.top - m.insets.bottom - 120
        cellH = max(60, min(m.cellH, (available - FolderGeometry.header - FolderGeometry.pad) / CGFloat(rows)))
        iconSize = min(m.iconSize, cellH * 0.64)
        let w = m.cellW * CGFloat(m.cols) + FolderGeometry.pad * 2
        let h = FolderGeometry.header + cellH * CGFloat(rows) + FolderGeometry.pad
        rect = CGRect(x: (m.size.width - w) / 2,
                      y: max(m.insets.top + 40, (m.size.height - h) / 2),
                      width: w, height: h)
    }

    func center(_ i: Int) -> CGPoint {
        let col = i % cols
        let row = i / cols
        return CGPoint(x: rect.minX + FolderGeometry.pad + (CGFloat(col) + 0.5) * cellW,
                       y: rect.minY + FolderGeometry.header + (CGFloat(row) + 0.5) * cellH)
    }

    func slot(at p: CGPoint) -> Int? {
        let inner = CGRect(x: rect.minX + FolderGeometry.pad,
                           y: rect.minY + FolderGeometry.header,
                           width: cellW * CGFloat(cols),
                           height: rect.height - FolderGeometry.header - FolderGeometry.pad)
        guard inner.contains(p) else { return nil }
        let col = min(cols - 1, max(0, Int((p.x - inner.minX) / cellW)))
        let row = max(0, Int((p.y - inner.minY) / cellH))
        return row * cols + col
    }
}
