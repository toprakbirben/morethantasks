//
//  testview.swift
//  morethantasks
//
//  Created by Toprak Birben on 05/09/2025.
//

import SwiftUI

struct testview: View {
    var body: some View {
        HStack {
            Button(action: {
                // action here
            }) {
                Text("Close Modal")
                    .foregroundColor(.white)
                    .font(.headline)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(26)
                    .padding(50)
                    .shadow(color: Color.gray.opacity(0.4), radius: 8)
            }
        }
        .frame(alignment: .topLeading)
    }
}

#Preview {
    testview()
}
