import SwiftUI
import Combine

// MARK: - AsyncAction 封装

/// 统一封装异步操作：Loading、Error、Result 状态管理
/// 使用方式：
/// @StateObject var action = AsyncAction<String> { await doSomething() }
/// action.execute()
/// if action.isLoading { ProgressView() }
/// if let error = action.error { Text(error) }
/// if let result = action.result { Text(result) }
@MainActor
public final class AsyncAction<Output>: ObservableObject {
	public typealias AsyncOperation = @Sendable () async throws -> Output
	
	@Published public private(set) var result: Output?
	@Published public var error: Error?
	@Published public private(set) var isLoading = false
	@Published public private(set) var progress: Double = 0
	@Published public private(set) var statusMessage: String = ""
	
	private var operation: AsyncOperation?
	private var task: Task<Void, Never>?
	private var progressContinuation: AsyncStream<Double>.Continuation?
	private var progressStream: AsyncStream<Double>?
	
	public init(_ operation: @escaping AsyncOperation) {
		self.operation = operation
	}
	
	/// 执行异步操作
	/// - Parameter onSuccess: 成功回调（可选）
	/// - Parameter onError: 错误回调（可选）
	public func execute(
		onSuccess: ((Output) -> Void)? = nil,
		onError: ((Error) -> Void)? = nil
	) {
		guard !isLoading else { return }
		guard let operation else { return }
		
		// 创建进度流
		let (stream, continuation) = AsyncStream<Double>.makeStream()
		progressStream = stream
		progressContinuation = continuation
		
		reset()
		isLoading = true
		error = nil
		result = nil
		progress = 0
		statusMessage = "准备中…"
		
		task = Task { @MainActor in
			do {
				// 启动进度监听
				let progressTask = Task {
					for await p in stream {
						if Task.isCancelled { break }
						await MainActor.run {
							self.progress = p
						}
					}
				}
				
				let output = try await operation()
				
				progressTask.cancel()
				continuation.finish()
				
				guard !Task.isCancelled else { return }
				
				await MainActor.run {
					self.result = output
					self.isLoading = false
					self.progress = 1.0
					self.statusMessage = "完成"
				}
				onSuccess?(output)
			} catch is CancellationError {
				continuation.finish()
				await MainActor.run {
					self.isLoading = false
					self.statusMessage = "已取消"
				}
			} catch {
				continuation.finish()
				await MainActor.run {
					self.error = error
					self.isLoading = false
					self.statusMessage = "失败: \(error.localizedDescription)"
				}
				onError?(error)
			}
		}
	}
	
	/// 取消当前操作
	public func cancel() {
		task?.cancel()
		progressContinuation?.finish()
		isLoading = false
		statusMessage = "已取消"
	}
	
	/// 重置状态
	public func reset() {
		result = nil
		error = nil
		progress = 0
		statusMessage = ""
	}
	
	/// 更新进度（供外部调用）
	public func updateProgress(_ value: Double, message: String? = nil) {
		progress = value
		if let message { statusMessage = message }
	}
	
	/// 便利：直接在闭包中处理结果
	public func executeAndHandle(
		onSuccess: @escaping (Output) -> Void,
		onError: @escaping (Error) -> Void
	) {
		execute(onSuccess: onSuccess, onError: onError)
	}
}

// MARK: - 进度条件 AsyncAction

/// 支持暂停/继续的异步操作
@MainActor
public final class PausableAsyncAction<Output>: ObservableObject {
	public typealias AsyncOperation = @Sendable (PausableAsyncAction<Output>.PauseToken) async throws -> Output
	
	@Published public private(set) var result: Output?
	@Published public var error: Error?
	@Published public private(set) var isLoading = false
	@Published public private(set) var isPaused = false
	@Published public private(set) var progress: Double = 0
	@Published public private(set) var statusMessage: String = ""
	
	public struct PauseToken: Sendable {
		let isPaused: @Sendable () async -> Bool
		let waitWhilePaused: @Sendable () async -> Void
	}
	
	private var operation: AsyncOperation?
	private var task: Task<Void, Never>?
	private var pauseContinuation: CheckedContinuation<Void, Never>?
	
	public init(_ operation: @escaping AsyncOperation) {
		self.operation = operation
	}
	
	public func execute() {
		guard !isLoading else { return }
		guard let operation else { return }
		
		reset()
		isLoading = true
		isPaused = false
		error = nil
		result = nil
		progress = 0
		statusMessage = "准备中…"
		
		task = Task { @MainActor in
			let pauseToken = PauseToken(
				isPaused: { [weak self] in
					await MainActor.run { self?.isPaused ?? false }
				},
				waitWhilePaused: { [weak self] in
					await self?.waitWhilePaused() ?? ()
				}
			)
			
			do {
				let output = try await operation(pauseToken)
				guard !Task.isCancelled else { return }
				
				await MainActor.run {
					self.result = output
					self.isLoading = false
					self.progress = 1.0
					self.statusMessage = "完成"
				}
			} catch is CancellationError {
				await MainActor.run {
					self.isLoading = false
					self.statusMessage = "已取消"
				}
			} catch {
				await MainActor.run {
					self.error = error
					self.isLoading = false
					self.statusMessage = "失败: \(error.localizedDescription)"
				}
			}
		}
	}
	
	private func waitWhilePaused() async {
		await withCheckedContinuation { continuation in
			self.pauseContinuation = continuation
		}
	}
	
	public func pause() {
		guard isLoading, !isPaused else { return }
		isPaused = true
		statusMessage = "已暂停"
	}
	
	public func resume() {
		guard isPaused else { return }
		isPaused = false
		pauseContinuation?.resume()
		pauseContinuation = nil
		statusMessage = "继续中…"
	}
	
	public func cancel() {
		if isPaused { resume() }
		task?.cancel()
		isLoading = false
		statusMessage = "已取消"
	}
	
	public func reset() {
		if isPaused { resume() }
		result = nil
		error = nil
		progress = 0
		statusMessage = ""
	}
}

// MARK: - View 扩展：便捷绑定

@MainActor
public extension View {
	/// 绑定 AsyncAction 的加载状态
	func asyncActionLoading<Output>(
		_ action: AsyncAction<Output>,
		@ViewBuilder loading: @escaping () -> some View
	) -> some View {
		overlay {
			if action.isLoading {
				loading()
					.frame(maxWidth: .infinity, maxHeight: .infinity)
					.background(Color.black.opacity(0.1))
			}
		}
	}
	
	/// 绑定 AsyncAction 的错误状态
	func asyncActionError<Output>(
		_ action: AsyncAction<Output>,
		@ViewBuilder errorView: @escaping (Error) -> some View
	) -> some View {
		alert(
			action.error?.localizedDescription ?? "错误",
			isPresented: Binding(
				get: { action.error != nil },
				set: { if !$0 { action.error = nil } }
			)
		) {
			Button("确定") { action.error = nil }
		} message: {
			if let error = action.error {
				Text(error.localizedDescription)
			}
		}
	}
	
	/// 绑定 PausableAsyncAction 的暂停/继续按钮
	func pausableActionControls<Output>(
		_ action: PausableAsyncAction<Output>
	) -> some View {
		HStack(spacing: 8) {
			if action.isLoading && !action.isPaused {
				Button("暂停") { action.pause() }
					.buttonStyle(.bordered)
			}
			if action.isPaused {
				Button("继续") { action.resume() }
					.buttonStyle(.borderedProminent)
			}
			if action.isLoading {
				Button("取消") { action.cancel() }
					.buttonStyle(.bordered)
					.foregroundStyle(.red)
			}
		}
	}
}

// MARK: - Task 工具扩展

public extension Task where Failure == Error {
	/// 忽略错误的 await
	func ignoreError() async {
		_ = try? await value
	}
}