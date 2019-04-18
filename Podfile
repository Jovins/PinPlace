platform :ios, '12.0'

target 'PinPlace' do
  use_frameworks!
  inhibit_all_warnings!
  
  pod 'Alamofire'
  pod 'JASON'
  pod 'ObjectMapper'
  pod 'PKHUD'
  pod 'JSQCoreDataKit'
  pod 'RxSwift'
  pod 'RxAlamofire'
  pod 'RxCoreData'
  pod 'RxGesture'
  pod 'RxMKMapView'
    
  target 'PinPlaceTests' do
    inherit! :search_paths
  end

  target 'PinPlaceUITests' do
    inherit! :search_paths
  end

end

post_install do |installer|
    installer.pods_project.targets.each do |target|
        target.build_configurations.each do |config|
            config.build_settings['SWIFT_VERSION'] = '5.0'
        end
    end
  end
