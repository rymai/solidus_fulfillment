# encoding: UTF-8
Gem::Specification.new do |s|
  s.platform    = Gem::Platform::RUBY
  s.name        = 'solidus_fulfillment'
  s.version     = '2.0.0'
  s.summary     = 'Solidus extension to do fulfillment processing via various services when a shipment becomes ready'
  s.description = 'Solidus extension to do fulfillment processing via various services when a shipment becomes ready'

  s.required_ruby_version     = '>= 2.2.7'

  s.author   = 'Rémy Coutable'
  s.email    = 'remy@rymai.me'
  s.homepage = 'https://rubygems.org/gems/solidus_fulfillment'

  s.files        = `git ls-files`.split("\n")
  s.test_files   = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.require_path = 'lib'
  s.requirements << 'none'

  s.add_dependency 'solidus_core', '~> 2.1'
  s.add_dependency 'active_fulfillment'

#  s.add_development_dependency 'capybara', '~> 1.1.2'
#  s.add_development_dependency 'coffee-rails'
#  s.add_development_dependency 'factory_girl', '~> 2.6.4'
#  s.add_development_dependency 'ffaker'
#  s.add_development_dependency 'rspec-rails',  '~> 2.9'
#  s.add_development_dependency 'sass-rails'
#  s.add_development_dependency 'sqlite3'
end
