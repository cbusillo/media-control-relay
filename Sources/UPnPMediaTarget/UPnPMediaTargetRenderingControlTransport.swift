import Foundation

public protocol UPnPMediaTargetHTTPTransacting: Sendable {
    func send(
        _ request: URLRequest,
        maximumResponseBytes: Int
    ) async throws(UPnPMediaTargetError) -> (Data, HTTPURLResponse)
}

public final class UPnPMediaTargetURLSessionHTTPTransport: NSObject, UPnPMediaTargetHTTPTransacting, @unchecked Sendable {
    public static let defaultTimeoutInterval: TimeInterval = 2
    public static let defaultMaximumResponseBytes = UPnPMediaTargetXMLGate.defaultMaximumPayloadBytes

    private let session: URLSession
    private let delegate: SessionDelegate
    private let maximumResponseBytes: Int

    public init(
        protocolClasses: [AnyClass]? = nil,
        timeoutInterval: TimeInterval = defaultTimeoutInterval,
        maximumResponseBytes: Int = defaultMaximumResponseBytes
    ) {
        self.maximumResponseBytes = max(1, maximumResponseBytes)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpMaximumConnectionsPerHost = 1
        configuration.timeoutIntervalForRequest = max(0.01, timeoutInterval)
        configuration.timeoutIntervalForResource = max(0.01, timeoutInterval)
        configuration.waitsForConnectivity = false
        if let protocolClasses {
            configuration.protocolClasses = protocolClasses
        }

        let delegate = SessionDelegate()
        let delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1
        self.delegate = delegate
        self.session = URLSession(
            configuration: configuration,
            delegate: delegate,
            delegateQueue: delegateQueue
        )
    }

    deinit {
        session.invalidateAndCancel()
    }

    public func send(
        _ request: URLRequest,
        maximumResponseBytes: Int
    ) async throws(UPnPMediaTargetError) -> (Data, HTTPURLResponse) {
        guard let requestURL = request.url else {
            throw .invalidControlURL
        }
        _ = try UPnPMediaTargetEndpointPolicy.validate(requestURL)

        return try await delegate.send(
            request,
            session: session,
            maximumResponseBytes: max(
                1,
                min(maximumResponseBytes, self.maximumResponseBytes)
            )
        )
    }
}

public struct UPnPMediaTargetRenderingControlTransport: Sendable {
    public let endpoint: URL
    public let codec: UPnPMediaTargetRenderingControlSOAPCodec
    public let http: any UPnPMediaTargetHTTPTransacting

    public init(
        endpoint: URL,
        codec: UPnPMediaTargetRenderingControlSOAPCodec = UPnPMediaTargetRenderingControlSOAPCodec(),
        http: any UPnPMediaTargetHTTPTransacting = UPnPMediaTargetURLSessionHTTPTransport()
    ) throws(UPnPMediaTargetError) {
        self.endpoint = try UPnPMediaTargetEndpointPolicy.validate(endpoint)
        self.codec = codec
        self.http = http
    }

    public func perform(
        _ operation: UPnPMediaTargetRenderingControlOperation
    ) async throws(UPnPMediaTargetError) -> UPnPMediaTargetRenderingControlResponse {
        let request = try codec.makeRequest(endpoint: endpoint, operation: operation)
        let (data, response) = try await http.send(
            request,
            maximumResponseBytes: UPnPMediaTargetURLSessionHTTPTransport.defaultMaximumResponseBytes
        )

        guard let responseURL = response.url else {
            throw .nonHTTPResponse
        }
        let validatedResponseURL = try UPnPMediaTargetEndpointPolicy.validate(responseURL)
        guard validatedResponseURL == endpoint else {
            throw .redirectRejected
        }

        if (300...399).contains(response.statusCode) {
            throw .redirectRejected
        }
        if response.statusCode == 500 {
            if !data.isEmpty,
               case let .fault(fault) = try? codec.decodeResponse(
                   data,
                   operation: operation
               ) {
                return .fault(fault)
            }
            throw .unexpectedStatusCode(response.statusCode)
        }
        guard response.statusCode == 200 else {
            throw .unexpectedStatusCode(response.statusCode)
        }
        let decoded = try codec.decodeResponse(data, operation: operation)
        guard case .fault = decoded else {
            return decoded
        }
        throw .invalidResponseValue
    }

    public func getVolume() async throws(UPnPMediaTargetError) -> Int {
        switch try await perform(.getVolume) {
        case let .volume(value):
            return value
        case .fault:
            throw .protocolFault
        case .mute, .acknowledged:
            throw .invalidResponseValue
        }
    }

    public func setVolume(_ volume: Int) async throws(UPnPMediaTargetError) {
        switch try await perform(.setVolume(volume)) {
        case .acknowledged:
            return
        case .fault:
            throw .protocolFault
        case .volume, .mute:
            throw .invalidResponseValue
        }
    }

    public func getMute() async throws(UPnPMediaTargetError) -> Bool {
        switch try await perform(.getMute) {
        case let .mute(value):
            return value
        case .fault:
            throw .protocolFault
        case .volume, .acknowledged:
            throw .invalidResponseValue
        }
    }

    public func setMute(_ isMuted: Bool) async throws(UPnPMediaTargetError) {
        switch try await perform(.setMute(isMuted)) {
        case .acknowledged:
            return
        case .fault:
            throw .protocolFault
        case .volume, .mute:
            throw .invalidResponseValue
        }
    }
}

private final class SessionDelegate: NSObject, URLSessionDataDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    private struct TaskState {
        var continuation: CheckedContinuation<Result<(Data, HTTPURLResponse), UPnPMediaTargetError>, Never>?
        var response: HTTPURLResponse?
        var data = Data()
        var error: UPnPMediaTargetError?
        var maximumResponseBytes: Int
        var finished = false
    }

    private final class TaskBox: @unchecked Sendable {
        private let lock = NSLock()
        private var task: URLSessionDataTask?

        func store(_ task: URLSessionDataTask) {
            lock.lock()
            self.task = task
            lock.unlock()
        }

        func cancel() {
            lock.lock()
            let task = self.task
            lock.unlock()
            task?.cancel()
        }
    }

    private var taskStates: [Int: TaskState] = [:]
    private let lock = NSLock()

    func send(
        _ request: URLRequest,
        session: URLSession,
        maximumResponseBytes: Int
    ) async throws(UPnPMediaTargetError) -> (Data, HTTPURLResponse) {
        let taskBox = TaskBox()
        let result: Result<(Data, HTTPURLResponse), UPnPMediaTargetError> = await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                let task = session.dataTask(with: request)
                taskBox.store(task)
                storeState(
                    TaskState(
                        continuation: continuation,
                        maximumResponseBytes: maximumResponseBytes
                    ),
                    for: task.taskIdentifier
                )
                if Task.isCancelled {
                    task.cancel()
                }
                task.resume()
            }
        }, onCancel: {
            taskBox.cancel()
        })

        switch result {
        case let .success(value):
            return value
        case let .failure(error):
            throw error
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        markError(.redirectRejected, for: task)
        completionHandler(nil)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        markError(.authenticationRejected, for: task)
        completionHandler(.cancelAuthenticationChallenge, nil)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let httpResponse = response as? HTTPURLResponse else {
            markError(.nonHTTPResponse, for: dataTask)
            completionHandler(.cancel)
            return
        }
        guard var state = loadState(for: dataTask.taskIdentifier), !state.finished else {
            completionHandler(.cancel)
            return
        }
        if response.expectedContentLength > Int64(state.maximumResponseBytes) {
            state.error = .oversizedPayload
            storeState(state, for: dataTask.taskIdentifier)
            completionHandler(.cancel)
            return
        }
        state.response = httpResponse
        storeState(state, for: dataTask.taskIdentifier)
        completionHandler(.allow)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        guard var state = loadState(for: dataTask.taskIdentifier), !state.finished else {
            return
        }
        guard data.count <= state.maximumResponseBytes - state.data.count else {
            state.error = .oversizedPayload
            storeState(state, for: dataTask.taskIdentifier)
            dataTask.cancel()
            return
        }
        state.data.append(data)
        storeState(state, for: dataTask.taskIdentifier)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard var state = loadState(for: task.taskIdentifier), !state.finished else {
            return
        }
        state.finished = true
        if state.error == nil, let error {
            state.error = map(error)
        }
        removeState(for: task.taskIdentifier)

        if let error = state.error {
            state.continuation?.resume(returning: .failure(error))
        } else if let response = state.response {
            state.continuation?.resume(returning: .success((state.data, response)))
        } else {
            state.continuation?.resume(returning: .failure(.nonHTTPResponse))
        }
    }

    private func markError(
        _ error: UPnPMediaTargetError,
        for task: URLSessionTask
    ) {
        guard var state = loadState(for: task.taskIdentifier), !state.finished else {
            return
        }
        state.error = error
        storeState(state, for: task.taskIdentifier)
        task.cancel()
    }

    private func loadState(for taskIdentifier: Int) -> TaskState? {
        lock.lock()
        defer { lock.unlock() }
        return taskStates[taskIdentifier]
    }

    private func storeState(_ state: TaskState, for taskIdentifier: Int) {
        lock.lock()
        taskStates[taskIdentifier] = state
        lock.unlock()
    }

    private func removeState(for taskIdentifier: Int) {
        lock.lock()
        taskStates.removeValue(forKey: taskIdentifier)
        lock.unlock()
    }

    private func map(_ error: Error) -> UPnPMediaTargetError {
        let urlError = error as? URLError
        switch urlError?.code {
        case .cancelled:
            return .cancelled
        case .timedOut:
            return .timeout
        default:
            return .offline
        }
    }
}
