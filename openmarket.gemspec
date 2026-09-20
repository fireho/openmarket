require_relative "lib/openmarket/version"

Gem::Specification.new do |spec|
  spec.name        = "openmarket"
  spec.version     = Openmarket::VERSION
  spec.authors     = [ "nofxx" ]
  spec.email       = [ "chadart@gmail.com" ]
  spec.homepage    = "https://github.com/fireho/openmarket"
  spec.summary     = "What a thing IS: Product, Drink, Food, Brand"
  spec.description = "Shared catalogue for fire hosts. Price lives on the host."
  spec.license     = "MIT"

  # Rubygems already has an SMS gem named openmarket. Ship over git, never gem push.
  spec.metadata["allowed_push_host"] = "none"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  end

  spec.add_dependency "rails", ">= 8.0.2"
end
