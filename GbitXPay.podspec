Pod::Spec.new do |s|
  s.name             = 'GbitXPay'
  s.version          = '0.1.0'
  s.summary          = 'Accept crypto payments in your iOS app with GbitXPay.'
  s.description       = <<-DESC
    Opens the hosted GbitX checkout in a hardened WKWebView and returns one typed
    result. Your server creates the payment with the secret key; the app uses a
    publishable key only. Fulfilment is driven by the signed server webhook.
  DESC
  s.homepage         = 'https://doc.gbitx.com'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'GBIT TECHNOLOGIES LIMITED COMPANY' => 'support@gbitx.com' }
  s.source           = { :git => 'https://github.com/gbitx1/gbitxpay-ios.git', :tag => s.version.to_s }

  s.platform         = :ios, '15.0'
  s.swift_version    = '5.9'
  s.source_files     = 'Sources/GbitXPay/**/*.swift'
  s.frameworks       = 'WebKit', 'UIKit', 'SwiftUI', 'Foundation'
end
