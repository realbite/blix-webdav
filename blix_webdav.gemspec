require 'rubygems'
require 'rake'

Gem::Specification.new do |spec|
  spec.name = 'blix-webdav'
  spec.version = '0.2.1'
  spec.author  = "Clive Andrews"
  spec.email   = "pacman@realitybites.nl"

  spec.platform = Gem::Platform::RUBY
  spec.summary = 'WebDAV protocol implementation for Blix Rest'
  spec.require_path = 'lib'

  spec.files = FileList['lib/**/*.rb'].to_a
  spec.extra_rdoc_files = ['README.md']


  spec.add_dependency('blix-rest', '>= 0.9.1')
  spec.add_dependency('ffi-xattr', '>= 0.0.0')
  spec.add_dependency('nokogiri', '>= 0.0.0')
end
