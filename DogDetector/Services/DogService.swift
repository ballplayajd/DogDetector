//
//  DogService.swift
//  DogDetector
//
//  Created by Joe Donino on 2/19/26.
//
import Foundation

enum DogEndpoint: Endpoint {
    case randomDogs(count: Int = 10)
    
    var path: String {
        switch self {
        case .randomDogs(let count): return "/breeds/image/random/\(count)"
        }
    }
    
    var method: HTTPMethod {
        switch self {
        case .randomDogs: return .get
        }
    }
    
    var queryItems: [URLQueryItem]? {
        return nil
    }
    
    var headers: [String : String] {
        return [:]
    }
    
    var body: Data? {
        return nil
    }
}

struct DogResponse: Codable {
    let message: [URL]
    let status: String
}

class DogService {
    let networkClient: NetworkClient
    
    init(baseUrl: String = "https://dog.ceo/api"){
        let baseUrl = URL(string: baseUrl)!
        self.networkClient = NetworkClient(baseUrl: baseUrl)
    }
    
    func fetchDogImages(count: Int = 10) async throws -> [URL] {
        let dogResponse: DogResponse = try await networkClient.request(DogEndpoint.randomDogs(count: count))
        return dogResponse.message
    }
}
