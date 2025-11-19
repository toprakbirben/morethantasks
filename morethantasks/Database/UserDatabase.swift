//
//  UserDatabase.swift
//  morethantasks
//
//  Created by Toprak Birben on 08/11/2025.
//

import Foundation
import SwiftUI
import PostgresClientKit

struct UserDatabase: Identifiable, Codable {
    let id: UUID
    var email: String
    var passwordHash: String
}


class userDatabase: ObservableObject {
    private var connection: Connection?
    
    @StateObject var userDB = DatabaseManager.shared
    
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
        
        guard let url = URL(string: "http://192.168.178.187:8000/add_user") else { return }
        
        let userData: [String: Any] = [
            "id": UUID().uuidString,
            "email": email,
            "passwordHash": passwordHash
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: userData) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            
            if let error = error {
                print("Registration request error:", error)
            } else {
                DispatchQueue.main.async {completion(true)}
            }
            
        }.resume()

    }
    
    func loginUser(email: String, password: String, completion: @escaping (Bool, Error?) -> Void) {
        guard let url = URL(string: "http://192.168.178.187:8000/login") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "email": email,
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
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let success = json["success"] as? Bool, success {
                        if let user = json["user"] as? [String: Any],
                           let userId = user["id"] as? Int,
                           let emailFromServer = user["email"] as? String {

                            UserDefaults.standard.set(userId, forKey: "loggedInUserId")
                            UserDefaults.standard.set(emailFromServer, forKey: "loggedInUserEmail")
                            
                            Task { @MainActor in
                                DatabaseManager.shared.notesArray = []
                                DatabaseManager.shared.tagsArray = []
                                DatabaseManager.shared.fetchNotes()
                                DatabaseManager.shared.fetchTags()
                            }

                            DispatchQueue.main.async { completion(true, nil) }
                        }
                    } else {
                        DispatchQueue.main.async { completion(false, nil) }
                    }
                }
            } catch {
                print("JSON decode error:", error)
                DispatchQueue.main.async { completion(false, error) }
            }
            
        }.resume()
    }
    
    
    
    func resetPassword(email: String, password: String, completion: @escaping (Bool, Error?) -> Void) {
        guard let url = URL(string: "http://192.168.178.187:8000/reset") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "email": email,
            "password": password
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(false, error)
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(false, nil)
                return
            }
            
            if httpResponse.statusCode == 200, let data = data {
                do {
                    print(data)
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let success = json["success"] as? Bool {
                        completion(success, nil)
                    } else {
                        completion(false, nil)
                    }
                } catch {
                    completion(false, error)
                }
            }
            else {
                completion(false, nil)
            }
            
        }.resume()
    }
    
    func logout() {
        UserDefaults.standard.removeObject(forKey: "loggedInUserId")
        UserDefaults.standard.removeObject(forKey: "loggedInUserEmail")
        self.connection = nil
    }
    
    func delete_user(completion: @escaping (Bool) -> Void) {
        guard let email = UserDefaults.standard.string(forKey: "loggedInUserEmail") else {
            completion(false)
            return
        }
        
        guard let url = URL(string: "http://192.168.178.187:8000/delete_user") else {
            completion(false)
            return
        }
        
        let body: [String: Any] = ["email": email]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            completion(false)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Delete user request error:", error)
                DispatchQueue.main.async { completion(false) }
                return
            }
            
            guard let data = data else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let success = json["success"] as? Bool {
                    
                    if success {
                        DispatchQueue.main.async {
                            self.logout()
                            completion(true)
                        }
                    } else {
                        DispatchQueue.main.async { completion(false) }
                    }
                } else {
                    DispatchQueue.main.async { completion(false) }
                }
            } catch {
                print("JSON decode error:", error)
                DispatchQueue.main.async { completion(false) }
            }
        }.resume()
    }
}
