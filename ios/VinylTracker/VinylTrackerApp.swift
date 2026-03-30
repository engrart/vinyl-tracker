import SwiftUI

@main
struct VinylTrackerApp: App {

    // Inject auth token here after Clerk/Auth0 sign-in.
    // Example with ClerkSDK:
    //   APIClient.shared.authToken = try await Clerk.shared.session?.getToken()
    @StateObject private var api = APIClient.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(api)
        }
    }
}
