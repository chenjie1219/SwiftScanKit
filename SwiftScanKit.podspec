Pod::Spec.new do |spec|
  spec.name = 'SwiftScanKit'
  spec.module_name = 'SwiftScanKit'
  spec.version = '2.0.0'
  spec.summary = 'Native QR and barcode scanning and generation for iOS.'
  spec.homepage = 'https://github.com/chenjie1219/SwiftScanKit'
  spec.author = { 'Jason' => '4234115@qq.com' }
  spec.license = { :type => 'MIT', :file => 'LICENSE' }
  spec.source = { :git => 'https://github.com/chenjie1219/SwiftScanKit.git', :tag => spec.version.to_s }
  spec.ios.deployment_target = '15.0'
  spec.swift_version = '6.0'
  spec.source_files = 'Sources/SwiftScanKit/**/*.swift'
  spec.resource_bundles = { 'SwiftScanKitResources' => ['Sources/SwiftScanKit/Media.xcassets'] }
  spec.frameworks = 'UIKit', 'AVFoundation', 'CoreImage', 'ImageIO'
end
