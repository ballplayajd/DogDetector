//
//  DogService.swift
//  DogDetector
//
//  Created by Joe Donino on 2/19/26.
//
import Foundation

enum DogEndpoint: Endpoint {
    case randomDogs
    
    var path: String {
        switch self {
        case .randomDogs: return "/breeds/image/random/10"
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
    
    func fetchDogImages() async throws -> [URL] {
        let dogResponse: DogResponse = try await networkClient.request(DogEndpoint.randomDogs)
        return dogResponse.message
    }
}
