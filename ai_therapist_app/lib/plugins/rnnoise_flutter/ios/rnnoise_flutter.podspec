#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint rnnoise_flutter.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'rnnoise_flutter'
  s.version          = '1.0.0'
  s.summary          = 'A Flutter plugin for RNNoise audio denoising and voice activity detection.'
  s.description      = <<-DESC
A Flutter plugin for RNNoise audio denoising and voice activity detection.
                       DESC
  s.homepage         = 'https://github.com/xiph/rnnoise'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Uplift' => 'support@uplift.app' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
end
