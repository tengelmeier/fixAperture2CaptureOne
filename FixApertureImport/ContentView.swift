//
//  ContentView.swift
//  ReadAperture
//
//  Created by Thomas Engelmeier on 09.12.20.
//

import SwiftUI

import SwiftUI

struct ContentView: View {
    #if targetEnvironment(macCatalyst)
    var body: some View {
        Text("Hello, Mac!")
    }
    #else
    var body: some View {
        Text("Hello, iOS!")
    }
    #endif
}

/*
struct ContentView: View {
    var body: some View {
        Text("Hello, world!")
            .padding()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
 */
