import UIKit

func imageNamed(_ name: String) -> UIImage {
    #if SWIFT_PACKAGE
    let resourceBundle = Bundle.module
    #else
    let frameworkBundle = Bundle(for: ScannerVC.self)
    let resourceBundle = frameworkBundle.url(forResource: "SwiftScanKitResources", withExtension: "bundle")
        .flatMap(Bundle.init(url:)) ?? frameworkBundle
    #endif
    return UIImage(named: name, in: resourceBundle, compatibleWith: nil) ?? UIImage()
}
