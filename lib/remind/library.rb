# frozen_string_literal: true

require "rbconfig"

require_relative "version"

module Remind
  # Written out rather than `Class.new(StandardError)`: a test runner that
  # `load`s a file twice would otherwise replace the class and orphan every
  # subclass of it.
  class Error < StandardError
  end

  # The shared library is not built, and no REMIND_LIBRARY says otherwise.
  class LibraryMissing < Error
    def initialize(path)
      super(<<~MESSAGE)
        Remind's shared library is not built: #{path}

        Build it with `rake library`, or point REMIND_LIBRARY at one built
        elsewhere. Building needs a C compiler and make -- the same two things
        Remind itself needs.
      MESSAGE
    end
  end

  # `configure`, `make` or the compiler said no.
  class BuildError < Error
  end

  # Where the shared library is, and where the sources it is built from are.
  #
  # Remind ships no shared library -- its Makefile builds two programs -- so
  # there is nothing installed to find. `Builder` compiles one out of the
  # vendored sources into `tmp/`, and this is the module that agrees with it
  # about where that is.
  module Library
    # An escape hatch for a library built elsewhere: a distribution package, a
    # Nix store path, a scratch build.
    ENV_VAR = "REMIND_LIBRARY"

    # `.so` on Linux, `.bundle` on macOS -- whatever this Ruby loads.
    EXTENSION = RbConfig::CONFIG.fetch("DLEXT")

    module_function

    # The gem's own directory: two levels up from lib/remind/.
    def root
      File.expand_path("../..", __dir__)
    end

    # The vendored Remind release, named for its version so that the bindings
    # cannot be vague about which one they bind.
    def source_root
      File.join(root, "remind-v#{REMIND_VERSION}")
    end

    def source_directory
      File.join(source_root, "src")
    end

    # The one C file this gem owns. See ext/remind/shim.c for what it is for.
    def shim
      File.join(
        root,
        "ext",
        "remind",
        "shim.c",
      )
    end

    # The compiled library: what `rake compile` writes, and what a precompiled
    # gem carries. One place, so that a checkout and an installed gem look the
    # same to everything above this.
    def default_path
      File.join(
        root,
        "lib",
        "remind",
        "libremind.#{EXTENSION}",
      )
    end

    # A library named in the environment is the answer, whether or not it is
    # there: someone who names one has a particular library in mind, and
    # quietly using a different one would be worse than saying it is missing.
    def path
      candidate = ENV.fetch(ENV_VAR, default_path)

      if File.exist?(candidate)
        candidate
      else
        raise LibraryMissing, candidate
      end
    end

    def built?
      File.exist?(ENV.fetch(ENV_VAR, default_path))
    end
  end
end

__END__

describe "Remind::Library" do
  it "puts the library where a precompiled gem carries it" do
    Remind::Library.default_path.should.end_with "/lib/remind/libremind.#{RbConfig::CONFIG["DLEXT"]}"
  end

  it "vendors the sources in a directory named for the Remind release" do
    Remind::Library.source_root.should.end_with "remind-v#{Remind::REMIND_VERSION}"
  end

  it "finds the sources and the shim it claims to build from" do
    File.directory?(Remind::Library.source_directory).should.be.true
    File.exist?(File.join(Remind::Library.source_root, "configure")).should.be.true
    File.exist?(Remind::Library.shim).should.be.true
  end

  it "prefers a library named in the environment" do
    ENV[Remind::Library::ENV_VAR] = __FILE__

    Remind::Library.path.should == __FILE__
  ensure
    ENV.delete(Remind::Library::ENV_VAR)
  end

  it "loads the compiled library when nothing overrides it" do
    Remind::Library.path.should == Remind::Library.default_path
    Remind::Library.should.be.built
  end

  it "explains itself when there is no library to load" do
    ENV[Remind::Library::ENV_VAR] = "/nonexistent/libremind.so"

    error = lambda { Remind::Library.path }.should.raise Remind::LibraryMissing
    error.message.should.include "rake library"
  ensure
    ENV.delete(Remind::Library::ENV_VAR)
  end
end
