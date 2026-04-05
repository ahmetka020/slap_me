Pod::Spec.new do |s|
  s.name             = 'mac_tap_detector'
  s.version          = '1.0.0'
  s.summary          = 'Flutter macOS plugin for physical tap/impact detection via microphone.'
  s.description      = <<-DESC
    Detects short impulsive chassis-tap-like events using AVAudioEngine with
    multi-condition impulse detection: adaptive noise floor, attack detection,
    decay checking, spectral filtering, and continuity rejection.
  DESC
  s.homepage         = 'https://github.com/ahmetka020/slap_me'
  s.license          = { :type => 'MIT' }
  s.author           = { 'ahmetka020' => '' }

  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'

  s.dependency 'FlutterMacOS'

  s.platform = :osx, '10.14'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
