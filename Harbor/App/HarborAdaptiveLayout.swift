import SwiftUI
import UIKit

enum HarborAdaptiveLayout: Equatable {
    case phone
    case pad

    /// Size classes can change when an iPhone rotates. The root navigation
    /// hierarchy must stay tied to the device family so playback and pushed
    /// screens are not discarded during that transition.
    static func resolve(
        userInterfaceIdiom: UIUserInterfaceIdiom,
        horizontalSizeClass _: UserInterfaceSizeClass?
    ) -> HarborAdaptiveLayout {
        userInterfaceIdiom == .pad ? .pad : .phone
    }
}
