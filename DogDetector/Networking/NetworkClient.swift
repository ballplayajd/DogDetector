//
//  NetworkClient.swift
//  DogDetector
//
//  Created by Joe Donino on 2/19/26.
//
import Foundation

enum NetworkError: Error {
    case noResponse
    case invalidStatusCode(Int)
    case decodingFailed(Error)
    case badUrl
}

enum HTTPMethod: String {
    case get, post, put, delete
}

protocol Endpoint {
    var path: String { get }
    var method: HTTPMethod { get }
    var headers: [String: String] { get }
    var body: Data? { get }
    var queryItems: [URLQueryItem]? { get }
}

class NetworkClient {
    private let baseUrl: URL
    private let session: URLSession
    
    init(baseUrl: URL, session: URLSession = URLSession.shared) {
        self.baseUrl = baseUrl
        self.session = session
    }
    
    public func request<E: Endpoint, R: Decodable>(_ endpoint: E) async throws -> R {
        let request = try buildRequest(from: endpoint)
      
        let (data, response) = try await session.data(for: request)
       if let JSONString = String(data: data, encoding: String.Encoding.utf8) {
         
           print(JSONString)
        }
        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.noResponse
        }
        guard 200..<300 ~= http.statusCode else {
            throw NetworkError.invalidStatusCode(http.statusCode)
        }
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(R.self, from: data)
        } catch {
            throw NetworkError.decodingFailed(error)
        }
    }
    
    func buildRequest<E: Endpoint>(from endpoint: E) throws -> URLRequest {
        guard var components = URLComponents(url: baseUrl.appendingPathComponent(endpoint.path), resolvingAgainstBaseURL: false) else {
            throw NetworkError.badUrl
        }
        components.queryItems = endpoint.queryItems ?? []
        guard let url = components.url else { throw NetworkError.badUrl }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue

        return request
    }
}

