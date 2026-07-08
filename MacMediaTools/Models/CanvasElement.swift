import Foundation
import CoreGraphics
import SwiftUI

// MARK: - CanvasMediaType

enum CanvasMediaType: String, Codable, Sendable, CaseIterable {
	case image = "图片"
	case video = "视频"
	case gif  = "GIF"

	var id: String { rawValue }
}

// MARK: - HandlePosition

enum HandlePosition: String, CaseIterable, Sendable {
	case topLeft, top, topRight
	case centerLeft, centerRight
	case bottomLeft, bottom, bottomRight

	var anchor: UnitPoint {
		switch self {
		case .topLeft:      return .topLeading
		case .top:          return .top
		case .topRight:     return .topTrailing
		case .centerLeft:   return .leading
		case .centerRight:  return .trailing
		case .bottomLeft:   return .bottomLeading
		case .bottom:       return .bottom
		case .bottomRight:  return .bottomTrailing
		}
	}

	var isCorner: Bool {
		switch self {
		case .topLeft, .topRight, .bottomLeft, .bottomRight: return true
		default: return false
		}
	}

	var isHorizontalEdge: Bool {
		switch self {
		case .centerLeft, .centerRight: return true
		default: return false
		}
	}

	var isVerticalEdge: Bool {
		switch self {
		case .top, .bottom: return true
		default: return false
		}
	}
}

// MARK: - CanvasElement

struct CanvasElement: Identifiable, Codable, Sendable {
	let id = UUID()
	let sourceURL: URL
	let mediaType: CanvasMediaType
	let displaySize: CGSize
	let duration: Double

	var position: CGPoint
	var size: CGSize
	var scale: CGFloat
	var nonUniformScale: CGSize?
	var cropRect: CGRect?
	var volume: Double
	var zIndex: Int

	init(
		sourceURL: URL,
		mediaType: CanvasMediaType,
		displaySize: CGSize,
		duration: Double = 0,
		position: CGPoint = .zero,
		scale: CGFloat = 1.0,
		nonUniformScale: CGSize? = nil,
		cropRect: CGRect? = nil,
		volume: Double = 1.0,
		zIndex: Int = 0
	) {
		self.sourceURL = sourceURL
		self.mediaType = mediaType
		self.displaySize = displaySize
		self.duration = duration
		self.position = position
		self.size = displaySize
		self.scale = scale
		self.nonUniformScale = nonUniformScale
		self.cropRect = cropRect
		self.volume = volume
		self.zIndex = zIndex
	}

	var effectiveSize: CGSize {
		if let nonUniform = nonUniformScale {
			return CGSize(
				width:  displaySize.width  * nonUniform.width,
				height: displaySize.height * nonUniform.height
			)
		}
		return CGSize(
			width:  displaySize.width  * scale,
			height: displaySize.height * scale
		)
	}

	var canvasFrame: CGRect {
		CGRect(origin: position, size: effectiveSize)
	}
}

// MARK: - CanvasSettings

struct CanvasSettings: Codable, Sendable {
	var canvasSize: CGSize = CGSize(width: 1920, height: 1080)
	var backgroundColorName: String = "black"
	var outputQuality: String = "high"
	var frameRate: Int = 30
}
