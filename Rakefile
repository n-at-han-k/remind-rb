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

# The platforms a precompiled gem is built for, and the toolchain triplet each
# is cross-compiled with inside the rb-sys / rake-compiler-dock images.
#
# The triplets are not guesses: they are rake-compiler-dock's own
# platform-to-target table (its Rakefile), which is what its images name their
# cross compilers after. Two of them are not what the platform name suggests --
# `x86_64-linux-musl` builds with `x86_64-unknown-linux-musl-gcc`, and
# `arm-linux` with `arm-linux-gnueabihf-gcc` -- which is exactly why they are
# copied rather than derived.
#
# No Windows: Remind is POSIX C -- fork, termios, unistd, glob -- and a mingw
# build does not get as far as failing usefully.
CROSS_PLATFORMS = {
  "aarch64-linux"      => "aarch64-linux-gnu",
  "aarch64-linux-gnu"  => "aarch64-linux-gnu",
  "aarch64-linux-musl" => "aarch64-linux-musl",
  "arm-linux"          => "arm-linux-gnueabihf",
  "arm-linux-gnu"      => "arm-linux-gnueabihf",
  "arm-linux-musl"     => "arm-linux-musleabihf",
  "arm64-darwin"       => "aarch64-apple-darwin",
  "x86-linux-gnu"      => "i686-linux-gnu",
  "x86-linux-musl"     => "i686-unknown-linux-musl",
  "x86_64-darwin"      => "x86_64-apple-darwin",
  "x86_64-linux"       => "x86_64-linux-gnu",
  "x86_64-linux-gnu"   => "x86_64-linux-gnu",
  "x86_64-linux-musl"  => "x86_64-unknown-linux-musl",
}.freeze

# What `rb-sys-dock --build` runs inside the container is
#
#   bundle exec rake native:$RUBY_TARGET gem
#
# with RUBY_TARGET naming the platform, so these are the task names it expects
# to find. `native:<platform>` cross-compiles; `gem` packages what it built.
def cross_configure_args(platform)
  host = CROSS_PLATFORMS.fetch(platform)
  compiler = ["#{host}-gcc", "#{host}-cc", "#{host}-clang"].find { |name| which(name) }

  unless compiler
    raise "no cross compiler for #{platform} (tried #{host}-gcc, -cc, -clang)"
  end

  # --host is what tells configure it is cross-compiling, and therefore not to
  # try running the test programs it builds. Remind's configure only ever
  # compiles and links them -- its one class of run-test, AC_CHECK_SIZEOF, has
  # been compile-only since autoconf 2.61 -- so there is nothing here that
  # needs a machine of the target's kind to answer.
  [
    "--host=#{host}",
    "CC=#{compiler}",
    # A library inside a gem must not need what the installing machine may
    # lack; nothing in the bindings uses readline.
    "ac_cv_lib_readline_readline=no",
    "ac_cv_header_readline_readline_h=no",
  ].join(" ")
end

def which(name)
  ENV.fetch("PATH", "").split(File::PATH_SEPARATOR)
     .map { |directory| File.join(directory, name) }
     .find { |path| File.executable?(path) }
end

def package_for(platform)
  "pkg/remind-rb-#{Remind::VERSION}-#{platform}.gem"
end

namespace :native do
  CROSS_PLATFORMS.each_key do |platform|
    desc "Cross-compile Remind for #{platform}"
    task platform do
      require_relative "lib/remind"

      ENV["REMIND_RB_CONFIGURE_ARGS"] = cross_configure_args(platform)
      ENV["REMIND_RB_PLATFORM"] = platform

      puts Remind::Builder.new.call
    end
  end
end

# Packages whatever `native:<platform>` just compiled. Named `gem` because
# that is the second half of the command rb-sys-dock runs.
desc "Package a precompiled gem for the platform just compiled for"
task :gem do
  require "bundler"
  require_relative "lib/remind/version"

  platform = ENV["REMIND_RB_PLATFORM"] || ENV["RUBY_TARGET"] || Gem::Platform.local.to_s
  package = package_for(platform)

  mkdir_p "pkg"

  # Outside the bundle, deliberately. REMIND_RB_PRECOMPILED changes the
  # gemspec's platform and its file list, and to bundler -- which re-reads the
  # gemspec of a path gem on every command -- that is a Gemfile that no longer
  # matches its lockfile. Packaging is not part of the bundle anyway.
  Bundler.with_unbundled_env do
    sh({ "REMIND_RB_PRECOMPILED" => platform }, "gem build remind-rb.gemspec --output #{package}")
  end

  puts "built #{package}"
end

desc "Compile and package for this machine's own platform"
task native: %i[compile gem]

desc "Run the specs co-located in each lib file's __END__ section"
task test: :compile do
  # All three gems' specs: they share this lib/, so they share one run.
  sh "RUBYOPT=-Ilib scampi $(grep -rl '^__END__' lib --include='*.rb' | sort)"
end

desc "Lint the Remind files that ship with Remind itself"
task :smoke do
  sh "ruby -Ilib exe/remlint remind-v*/examples remind-v*/tests remind-v*/include" do |ok, _status|
    # A corpus is expected to have offences; the point is that we survive it.
    puts ok ? "smoke: clean" : "smoke: offences reported (expected)"
  end
end

desc "Regenerate lib/remlint/tables.rb from the vendored Remind sources"
task :tables do
  sh "ruby tasks/generate_tables.rb remind-v#{Remind::REMIND_VERSION}"
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
