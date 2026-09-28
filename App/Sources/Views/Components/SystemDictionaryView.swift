import SwiftUI

struct SystemDictionaryView: UIViewControllerRepresentable {
    let term: String
    @Environment(\.dismiss) var dismiss

    func makeUIViewController(context: Context) -> UIReferenceLibraryViewController {
        let vc = UIReferenceLibraryViewController(term: term)
        return vc
    }

    func updateUIViewController(_ uiViewController: UIReferenceLibraryViewController, context: Context) {}

    /// Checks if the system dictionary has a definition for the given term.
    static func hasDefinition(_ term: String) -> Bool {
        UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm: term)
    }
}
