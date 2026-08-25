platform :ios, '16.0'

target 'Harbor' do
  use_frameworks!

  pod 'MobileVLCKit', '~> 3.6'

  target 'HarborTests' do
    inherit! :search_paths
  end
end

post_install do |installer|
  installer.pods_project.targets.each do |t|
    t.build_configurations.each do |config|
      config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.0'
    end
  end
end
