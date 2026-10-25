import SwiftUI

// Disambiguate the deployment-compatible State property wrapper from the newer
// same-named macro, whose plugin is not included in every Command Line Tools SDK.
typealias ViewState<Value> = SwiftUI.State<Value>
