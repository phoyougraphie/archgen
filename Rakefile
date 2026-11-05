# frozen_string_literal: true

require 'rake/testtask'

Rake::TestTask.new(:test) do |t|
  t.libs << 'test'
  t.pattern = 'test/{unit,contract}/**/*_test.rb'
  t.warning = false
end

desc 'Régénère la carte mentale (docs/carte/index.html, docs/CARTE.md)'
task :carte do
  ruby 'scripts/build_carte.rb'
end

desc 'Construit le RBZ de développement dans pkg/'
task :package do
  ruby 'scripts/package_rbz.rb'
end

task default: :test
