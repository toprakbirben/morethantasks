//  MockURLProtocol.swift
//  Test helper: a URLProtocol that returns canned responses and records whether
//  a request was attempted, so we can test AuthService's status→error mapping
//  and ViewModel validation gating without real network.

import Foundation

final class MockURLProtocol: URLProtocol {
    /// Maps a request to a (statusCode, body) pair. Defaults to 200/empty.
    static var responder: ((URLRequest) -> (Int, Data))?
    /// Set true the moment any request reaches the network layer.
    static var didReceiveRequest = false

    static func reset(responder: ((URLRequest) -> (Int, Data))? = nil) {
        didReceiveRequest = false
        self.responder = responder
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        MockURLProtocol.didReceiveRequest = true
        let (status, data) = MockURLProtocol.responder?(request) ?? (200, Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

extension URLSession {
    static func mock() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }
}
