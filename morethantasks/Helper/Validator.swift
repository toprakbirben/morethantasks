//
//  Validator.swift
//  morethantasks
//
//  Created by Toprak Birben on 08/11/2025.
//

import Foundation

enum Validator {
    static func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }
    
    static func isValidPassword(_ password: String) -> Bool {
        let passRegex = "(?=.*[A-Za-z])(?=.*\\d)[A-Za-z\\d]{8,}"
        let passPredicate = NSPredicate(format: "SELF MATCHES %@", passRegex)
        return passPredicate.evaluate(with: password)
    }
    
    static func loginCredentialsValid(_ email: String, _ password: String) -> Bool {
        return isValidEmail(email) && isValidPassword(password)
    }
}
