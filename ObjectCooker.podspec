Pod::Spec.new do |s|

  s.name            = 'ObjectCooker'
  s.version         = '0.1.1'
  s.summary         = 'Dependecy Injection library for ObjectiveC'
  s.homepage        = 'https://github.com/cristik/ObjectCooker'
  s.source          = { :git => 'https://github.com/cristik/ObjectCooker.git', :tag => s.version.to_s }
  s.license         = { :type => 'MIT', :file => 'LICENSE' }

  s.authors = {
    'Cristian Kocza'   => 'cristik@cristik.com',
  }

  s.libraries = 'c++'

  s.ios.deployment_target = '5.0'
  s.osx.deployment_target = '10.7'

  s.source_files = 'ObjectCooker/**/*.{h,m,mm}'
  s.requires_arc = true

end