
  Pod::Spec.new do |s|
    s.name = 'CapacitorFaceRecPlugin'
    s.version = '0.0.1'
    s.summary = 'Face recognition plugin'
    s.license = 'MIT'
    s.homepage = 'https://bitbucket.org/gnucoop/capacitor-face-rec-plugin'
    s.author = 'gnucoop'
    s.source = { :git => 'https://bitbucket.org/gnucoop/capacitor-face-rec-plugin', :tag => s.version.to_s }
    s.source_files = 'ios/Plugin/**/*.{swift,h,m,c,cc,mm,cpp}'
    s.ios.deployment_target  = '11.0'
    s.dependency 'Capacitor'
    s.dependency 'Firebase', '~> 6.8.0'
    s.dependency 'FirebaseMLModelInterpreter', '~> 0.18.0'
    s.dependency 'FirebaseMLVision', '~> 0.18.0'
    s.dependency 'FirebaseMLVisionFaceModel', '~> 0.18.0'
    s.dependency 'TensorFlowLiteSwift', '~> 1.14.0'
  end