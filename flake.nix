{
  description = "Remind -- a sophisticated calendar and alarm program";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, utils }:
    utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        inherit (pkgs) lib;

        # Read the version from the one place that decides it, so the flake
        # cannot claim a version the build does not produce.
        version = lib.head
          (lib.match "[^)]*AC_INIT\\(remind, ([^,)]+).*"
            (builtins.readFile ./remind-v06.02.10/configure.ac));

        # What `./configure` and the Makefiles actually reach for, inside the
        # vendored upstream tree. Listed rather than filtered, because the
        # release also holds a book PDF, and the repository around it holds
        # the Ruby bindings, the linter and assorted scratch directories --
        # none of which have any business forcing a rebuild of the C program.
        src = lib.fileset.toSource {
          root = ./remind-v06.02.10;
          fileset = lib.fileset.unions [
            ./remind-v06.02.10/src
            ./remind-v06.02.10/include
            ./remind-v06.02.10/man
            ./remind-v06.02.10/scripts
            ./remind-v06.02.10/resources
            ./remind-v06.02.10/tests
            ./remind-v06.02.10/rem2html
            ./remind-v06.02.10/rem2pdf
            ./remind-v06.02.10/www
            ./remind-v06.02.10/docs # configure reads the release date out of docs/WHATSNEW
            ./remind-v06.02.10/examples
            ./remind-v06.02.10/configure
            ./remind-v06.02.10/configure.ac
            ./remind-v06.02.10/install-sh
            ./remind-v06.02.10/Makefile
            ./remind-v06.02.10/COPYRIGHT
            ./remind-v06.02.10/README.md
          ];
        };

        # The Ruby side's gems, from nix rather than from `bundle install`:
        # Gemfile.lock pins them, gemset.nix (regenerated with `bundix -l`)
        # says where nix fetches each one, and bundlerEnv puts the lot on PATH
        # already resolved. Nothing writes to a GEM_HOME.
        # The Ruby side's gems, from nix rather than from `bundle install`:
        # Gemfile.lock pins them and gemset.nix says where nix fetches each
        # one. Regenerate the latter with `bundix -l` after touching either.
        gems = pkgs.bundlerEnv {
          name = "remind-rb";
          ruby = pkgs.ruby;
          gemfile = ./Gemfile;
          lockfile = ./Gemfile.lock;
          gemset = ./gemset.nix;
        };

        # rem2pdf and rem2html are Perl, and their Makefiles quietly skip
        # installation when a module is missing rather than failing -- so the
        # only way to know they were built is to put the modules there and
        # then check for the binaries afterwards.
        #
        # These three are what rem2pdf/Makefile.PL asks for, but the runtime
        # path is built with `makeFullPerlPath`, not `makePerlPath`: Pango
        # loads Glib, which is nobody's direct dependency here and so is
        # missing from the shallow path.
        perlModules = with pkgs.perlPackages; [
          Cairo
          Pango
          JSONMaybeXS
        ];

        # Deliberately a plain stdenv derivation rather than
        # `tcl.mkTclDerivation`, which nixpkgs' own remind package uses: that
        # wraps every executable in $out/bin with the whole TCLLIBPATH, so
        # `remind` stops being a plain binary and rem2pdf's usage message
        # announces itself as `..rem2pdf-wrapped-wrapped`. Only tkremind is
        # Tcl, so only tkremind is wrapped.
        #
        # tk and tcllib are not listed as inputs: nothing compiles against
        # them, and the runtime closure is held by the store paths substituted
        # into tkremind and its wrapper.
        remind =
          { withGui ? true
          , withPdf ? true
          , withReadline ? true
          }:
          pkgs.stdenv.mkDerivation {
            pname = "remind";
            inherit version src;

            strictDeps = true;

            # Perl is native, not host: it runs during the build, both to
            # execute rem2pdf/Makefile.PL and for the `perl -M$module -e 1`
            # probes the Perl Makefiles gate themselves on.
            nativeBuildInputs = [ pkgs.makeWrapper ]
              ++ lib.optionals withPdf ([ pkgs.perl ] ++ perlModules);

            buildInputs = lib.optionals withReadline [ pkgs.readline ];

            postPatch = ''
              # tests/ holds shell scripts that call each other; `make test`
              # runs them from the build tree, where /bin/sh may not be what
              # the sandbox has.
              patchShebangs tests/

            '' + lib.optionalString withGui ''
              substituteInPlace scripts/tkremind.in \
                --replace-fail "exec wish" "exec ${lib.getExe' pkgs.tk "wish"}" \
                --replace-fail 'set Remind "remind"' "set Remind \"$out/bin/remind\"" \
                --replace-fail 'set Rem2PDF "rem2pdf"' "set Rem2PDF \"$out/bin/rem2pdf\""
            '';

            # On Darwin, setenv and unsetenv come from libSystem's stdlib.h and
            # configure's probe does not find them.
            env.NIX_CFLAGS_COMPILE = lib.optionalString pkgs.stdenv.hostPlatform.isDarwin
              (toString [ "-DHAVE_SETENV" "-DHAVE_UNSETENV" ]);

            enableParallelBuilding = true;

            # `make test` is `test-basic` plus `test-tz`: the acceptance suite
            # in tests/test-rem, and the timezone handling in
            # tests/test-timezone-support.
            doCheck = true;
            checkTarget = "test";

            # test-timezone-support asks for America/Los_Angeles and half a
            # dozen other zones by name. Without a zone database glibc answers
            # every one of them with UTC, and the test fails with output that
            # looks like a timezone bug in Remind rather than a missing
            # dependency in the build.
            nativeCheckInputs = [ pkgs.tzdata ];

            preCheck = ''
              export TZDIR=${pkgs.tzdata}/share/zoneinfo

            '';

            postInstall = lib.optionalString withGui ''
              # tcllib's lib directory is the whole of it -- the top-level
              # pkgIndex.tcl there resolves the mime, smtp and json packages
              # tkremind asks for.
              wrapProgram $out/bin/tkremind \
                --set TCLLIBPATH "${pkgs.tclPackages.tcllib}/lib"

            '' + lib.optionalString withPdf ''
              # `use lib` rather than a PERL5LIB wrapper: a wrapper would
              # rename the script, and both of these print $0 in their usage
              # message. Line 2 is just below the shebang configure wrote.
              #
              # makeFullPerlPath, not makePerlPath: Pango loads Glib, which is
              # nobody's direct dependency here and so is missing from the
              # shallow path.
              for script in rem2pdf rem2html; do
                sed -i "2i use lib qw(${
                  lib.replaceStrings [ ":" ] [ " " ]
                    (pkgs.perlPackages.makeFullPerlPath perlModules)
                } $out/${pkgs.perl.libPrefix});" $out/bin/$script
              done

              # ExtUtils::MakeMaker with INSTALL_BASE puts its man pages in
              # $out/man; everything else is in $out/share/man, and stdenv
              # warns about the pair.
              if [ -d "$out/man" ]; then
                mkdir -p $out/share/man
                cp -r $out/man/. $out/share/man/
                rm -rf $out/man
              fi

            '' + lib.optionalString (!withGui) ''
              # src/Makefile installs tkremind unconditionally, and without the
              # GUI it was never patched -- it would still open with `exec wish`
              # and find nothing. Turning the GUI off has to mean the front end
              # is gone, not that it is present and broken.
              rm -f $out/bin/tkremind
              rm -f $out/share/applications/tkremind.desktop
              rm -f $out/share/pixmaps/tkremind.png
              rm -f $out/share/man/man1/tkremind.1*
            '';

            doInstallCheck = true;

            installCheckPhase = ''
              runHook preInstallCheck

              # Everything below writes to a file and greps the file. The
              # stdenv runs with `set -o pipefail`, and `something | grep -q`
              # kills `something` with SIGPIPE the moment grep is satisfied --
              # which reads as a failed build rather than a passed check.
              echo "REM 1 Jan 2026 MSG New Year" > sanity.rem

              $out/bin/remind -n sanity.rem 2026-01-01 > next.txt
              grep -q "New Year" next.txt

              # `rem` is the same binary under another name: it reads
              # $DOTREMINDERS instead of taking a filename, and it decides that
              # from argv[0]. A wrapper that rewrote argv[0] would break it
              # silently, so it is checked rather than assumed.
              test -L $out/bin/rem
              DOTREMINDERS=$PWD/sanity.rem $out/bin/rem -n 2026-01-01 > rem.txt
              grep -q "New Year" rem.txt

              # End to end rather than `--help`: rem2ps reads the calendar
              # format `remind -p` writes, and nothing short of running the
              # pair proves they still agree on it.
              $out/bin/remind -p sanity.rem 2026-01-01 > calendar.txt
              $out/bin/rem2ps < calendar.txt > calendar.ps
              grep -q '^%!PS' calendar.ps

              # $SysInclude has to point at something, or every INCLUDE in the
              # shipped holiday files misses.
              test -d $out/share/remind/holidays
              echo 'INCLUDE [$SysInclude]/holidays/us.rem' > include.rem
              $out/bin/remind -n include.rem 2026-07-04 > holidays.txt
              grep -qi "independence" holidays.txt

              ${lib.optionalString withGui ''
                test -x $out/bin/tkremind
                grep -q '${lib.getExe' pkgs.tk "wish"}' $out/bin/.tkremind-wrapped
              ''}

              ${lib.optionalString (!withGui) ''
                # Turning the GUI off has to actually remove it, not leave
                # behind a script that opens with a `wish` that is not there.
                test ! -e $out/bin/tkremind
              ''}

              ${lib.optionalString withPdf ''
                # The Perl Makefiles skip installation on a missing module
                # instead of failing, so these are the only thing standing
                # between "built with PDF support" and a silent no-op.
                test -x $out/bin/rem2pdf
                test -x $out/bin/rem2html

                $out/bin/remind -pp sanity.rem 2026-01-01 > calendar.json
                $out/bin/rem2pdf < calendar.json > calendar.pdf
                grep -qa '^%PDF' calendar.pdf

                $out/bin/rem2html < calendar.json > calendar.html
                test -s calendar.html
              ''}

              runHook postInstallCheck
            '';

            meta = {
              description = "Sophisticated calendar and alarm program for the console";
              longDescription = ''
                Remind reads a file of reminders written in its own small
                language and reports which of them fall due. It handles
                arbitrarily complex recurrences, moon phases, sunrise and
                sunset, Hebrew dates, timed reminders with advance warning, and
                produces plain text, a character calendar, PostScript
                (rem2ps), HTML (rem2html) or PDF (rem2pdf).
              '';
              homepage = "https://dianne.skoll.ca/projects/remind/";
              license = lib.licenses.gpl2Only;
              mainProgram = "remind";
              platforms = lib.platforms.unix;
            };
          };
      in
      {
        packages = rec {
          default = full;

          # Everything: the C programs, the Tcl/Tk front end and both Perl
          # back ends.
          full = remind { };

          # Just the C programs -- no Tcl, no Perl, no readline. This is the
          # one to depend on from a script or a container.
          minimal = remind {
            withGui = false;
            withPdf = false;
            withReadline = false;
          };

          # The console program and its output filters, without the GUI.
          console = remind { withGui = false; };
        };

        apps = {
          default = {
            type = "app";
            program = lib.getExe self.packages.${system}.default;
          };

          rem2ps = {
            type = "app";
            program = "${self.packages.${system}.default}/bin/rem2ps";
          };

          rem2pdf = {
            type = "app";
            program = "${self.packages.${system}.default}/bin/rem2pdf";
          };

          tkremind = {
            type = "app";
            program = "${self.packages.${system}.default}/bin/tkremind";
          };
        };

        # `nix flake check` builds all three variants, and each runs Remind's
        # own acceptance suite through `doCheck`.
        checks = {
          inherit (self.packages.${system}) full minimal console;
        };

        devShells.default = pkgs.mkShell {
          inputsFrom = [ self.packages.${system}.full ];

          packages = [
            pkgs.autoconf # configure.ac is checked in; so is configure
            pkgs.gdb
            pkgs.cppcheck # the top-level Makefile has a cppcheck target
            pkgs.tzdata # `make test` names real timezones

            # The Ruby side: the bindings, the converter built on them, and
            # the linter beside them. gems.wrappedRuby is a ruby that already
            # sees the bundle, so `scampi`, `rubocop` and `rake` work without
            # `bundle exec` and without installing anything.
            gems
            gems.wrappedRuby
            pkgs.bundix # regenerates gemset.nix from Gemfile.lock
            # fiddle left Ruby's standard library in 3.5, so the Gemfile names
            # it -- and building that gem means libffi's headers.
            pkgs.pkg-config
            pkgs.libffi
            pkgs.libyaml
            pkgs.openssl
            pkgs.lefthook # `lefthook install` writes .git/hooks
            pkgs.trufflehog # what the pre-commit hook scans with
          ];

          shellHook = ''
            export TZDIR=${pkgs.tzdata}/share/zoneinfo

            echo "Remind ${version} sources are in remind-v${version}/; the Ruby bindings are at the root."
            echo "C:    cd remind-v${version} && ./configure --prefix=\$PWD/_install && make && make test"
            echo "Ruby: rake library && rake test"
          '';
        };
      }
    );
}
