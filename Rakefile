# frozen_string_literal: true

require_relative "lib/remind/library"
require_relative "lib/remind/version"

# lib/remind/libremind.so on Linux, .bundle on macOS: what Remind::Library
# loads, and what a precompiled gem carries.
LIBRARY = Remind::Library.default_path

# Compiles the vendored Remind sources, plus ext/remind/shim.c, into LIBRARY so
# `require "remind"` finds something to bind.
#
# There is no Rake::ExtensionTask here and no extconf.rb, because the result is
# not a Ruby extension: it has no Init_, nothing requires it, and Fiddle opens
# it by path. What ./configure decides -- the compiler, the flags, the feature
# macros, the libraries -- is read back out of the src/Makefile it generates;
# see lib/remind/builder.rb.
desc "Compile Remind into #{LIBRARY}"
task :compile do
  require_relative "lib/remind"

  puts Remind::Builder.new.call
end

# Package a precompiled gem for one platform, e.g. `rake native[x86_64-linux]`.
# CI (cross-compile.yml) drives the platform matrix; each runner builds
# natively, because Remind is configured by a shell script that probes the
# machine it runs on and there is no cross-compilation story for that.
#
# This is what keeps a compiler off the installing machine: RubyGems serves the
# gem matching the platform, and the library is already inside it.
desc "Package a precompiled gem for a platform"
task :native, [:platform] => :compile do |_task, args|
  require "bundler"

  platform = args[:platform] || Gem::Platform.local.to_s
  package = "pkg/remind-rb-#{Remind::VERSION}-#{platform}.gem"

  mkdir_p "pkg"

  # Outside the bundle, deliberately. REMIND_RB_PRECOMPILED changes the
  # gemspec's platform and its file list, and to bundler -- which re-reads the
  # gemspec of a path gem on every command -- that is a Gemfile that no longer
  # matches its lockfile. Under `bundle install --deployment`, as CI runs, that
  # is a hard error. Packaging is not part of the bundle anyway.
  Bundler.with_unbundled_env do
    sh({ "REMIND_RB_PRECOMPILED" => platform }, "gem build remind-rb.gemspec --output #{package}")
  end

  puts "built #{package}"
end

desc "Run the specs co-located in each lib file's __END__ section"
task test: :compile do
  # Scoped to lib: the linter and rem2ics beside it are their own gems, with
  # their own suites and their own Rakefiles.
  sh "bundle exec scampi $(grep -rl '^__END__' lib --include='*.rb' | sort)"
end

desc "Check the bindings' Ruby against the house cops"
task :rubocop do
  sh "bundle exec rubocop"
end

desc "Build the C program the bindings are built from"
task :remind do
  sh "cd remind-v#{Remind::REMIND_VERSION} && ./configure && make"
end

task default: :compile
