# frozen_string_literal: true

require_relative "lib/site_import/version"

# The gemspec's name is the plugin's key.
Gem::Specification.new do |spec|
  spec.name = "site_import"
  spec.version = SiteImport::VERSION
  spec.summary = "LibrePublish Import: bring a site over from the old shared LibrePublish deployment"
  spec.authors = ["Martin Business Consultants"]
  spec.homepage = "https://github.com/Martin-Business-Consultants/cms-site-import"
  spec.license = "FSL-1.1-MIT"
  spec.files = Dir["{app,config,db,lib}/**/*"]
  spec.required_ruby_version = ">= 3.3"
  spec.add_dependency "rails", ">= 8.1"
end
