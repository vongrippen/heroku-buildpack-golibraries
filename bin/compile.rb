#!/usr/bin/env ruby
require 'yaml'
require 'uri'

DEFAULT_GO_VERSION = 'go1.6'

BUILD_DIR = File.join __dir__, ARGV[0]
CACHE_DIR = File.join __dir__, ARGV[1]
ENV_DIR = ARGV[2]

CURL = 'curl -s -L --retry 15 --retry-delay 2'

initialize_env(ENV_DIR)

config = YAML.load File.join(BUILD_DIR, '.golibraries.yml')

go_version = config['go_version'] || DEFAULT_GO_VERSION
install_go(go_version)

`mkdir -p #{File.join BUILD_DIR, 'lib'}`

config['libraries'].each {|lib| compile_library(lib)}

`mkdir -p #{BUILD_DIR}/.profile.d`
system('cp', 'vendor/concurrency.sh', "#{BUILD_DIR}/.profile.d/")

def compile_library(library)
  name = File.basename(URI.parse(lib).path, '.*')

  # Use separate gopaths to ensure no version issues
  ENV['GOPATH'] = File.join CACHE_DIR, 'gopath', name
  system('mkdir', '-p', ENV['GOPATH'])

  # go get the library
  system('go', 'get', library)

  Dir.chdir File.join(ENV['GOPATH'], library) do
    if File.exist? File.join(ENV['GOPATH'], name, library, 'Godeps', 'Godeps.json')
      run_godep(library, name)
    else
      raise 'Unsupported go dependency manager, please use Godeps'
    end

    compile(name)
  end
end

def run_godep(library, name)
  system('go', 'install', 'github.com/tools/godep')
  system('godep', 'restore')
end

def compile(name)
  system('go', 'build', '-buildmode=c-shared', '-o', File.join(BUILD_DIR, 'lib', "#{name}.so"), '*.go')
end

def url_for_version(version)
  # if version.starts_with('devel')
  #   sha = version.gsub('devel-','')
  #   return "https://github.com/golang/go/archive/#{sha}.tar.gz"
  # else
    if Gem::Version.new(version) > Gem::Version.new('1.5.0')
      return "https://storage.googleapis.com/golang/#{version}.linux-amd64.tar.gz"
    else
      raise 'Go 1.5 or higher is required for building shared libraries.'
    end
  # end
end

def install_go(version)
  url = url_for_version(version)
  `mkdir -p #{File.join CACHE_DIR, version}`
  `mkdir -p #{File.join CACHE_DIR, 'gopath'}`
  Dir.chdir File.join(CACHE_DIR, version) do
    `#{CURL} #{url} | tar zxf -`
  end
  ENV['GOROOT'] = File.join CACHE_DIR, version, 'go'
  ENV['GOBIN'] = File.join ENV['GOROOT'], 'bin'
  ENV['PATH'] = "#{ENV['GOBIN']}:#{ENV['PATH']}"
end

def initialize_env(path)
  env_dir = Pathname.new("#{path}")
  if env_dir.exist? && env_dir.directory?
    env_dir.each_child do |file|
      key   = file.basename.to_s
      value = file.read.strip
      ENV[key] = value unless env_blacklist?(key)
    end
  end
end

def env_blacklist?(key)
  %w(PATH GEM_PATH GEM_HOME GIT_DIR JRUBY_OPTS).include?(key)
end