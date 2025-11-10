//
//  UserDatabase.swift
//  morethantasks
//
//  Created by Toprak Birben on 08/11/2025.
//

import Foundation
import PostgresClientKit

struct UserDatabase: Identifiable, Codable {
    let id: UUID
    var email: String
    var passwordHash: String
}


class userDatabase: ObservableObject {
    private var connection: Connection?
    
    static let shared = userDatabase()
    
    init() {
        setupConnection()
        createUserTableIfNeeded()
    }
    
    private func setupConnection() {
        do {
            var configuration = PostgresClientKit.ConnectionConfiguration()
            configuration.host = "192.168.178.187"
            configuration.port = 5432
            configuration.database = "notes"
            configuration.user = "notes"
            configuration.credential = .scramSHA256(password: "notes")
            configuration.ssl = false
            
            self.connection = try Connection(configuration: configuration)
            print("> Connected to user db")
        } catch {
            print("> Cant connect to user db")
        }
    }
    
    private func createUserTableIfNeeded() {
        let sql = """
        CREATE TABLE IF NOT EXISTS users (
        id SERIAL PRIMARY KEY,
        email VARCHAR(255) NOT NULL UNIQUE,
        password_hash VARCHAR(255) NOT NULL
        );
        """
        do {
            let statement = try connection?.prepareStatement(text: sql)
            defer { statement?.close() }
            try statement?.execute()
        } catch {
            print("Failed to create users table: \(error)")
        }
    }

    func registerUser(email: String, passwordHash: String, completion: @escaping (Bool) -> Void) {
        let sql = "INSERT INTO users (email, password_hash) VALUES ($1, crypt($2, gen_salt('bf')));"
        do {
            let statement = try connection?.prepareStatement(text: sql)
            defer { statement?.close() }
            try statement?.execute(parameterValues: [email, passwordHash])
            print("Added user \(email)")
            completion(true)
        } catch {
            print("Cant do it bruv \(error)")
            completion(false)
        }
    }
    
    func loginUser(username: String, password: String, completion: @escaping (Bool, Error?) -> Void) {
        guard let url = URL(string: "http://192.168.178.187:8000/login") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "username": username,
            "password": password
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            
            if let error = error {
                print("Login request error:", error)
                DispatchQueue.main.async { completion(false, error) }
                return
            }
            
            guard let data = data else {
                DispatchQueue.main.async { completion(false, nil) }
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let success = json["success"] as? Bool {
                    DispatchQueue.main.async { completion(success, nil) }
                } else {
                    DispatchQueue.main.async { completion(false, nil) }
                }
            } catch {
                print("JSON decode error:", error)
                DispatchQueue.main.async { completion(false, error) }
            }
            
        }.resume()
    }
}
