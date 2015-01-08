/**
 * C preprocessor driver
 * Copyright 2014 Facebook, Inc.
 * License: $(LINK2 http://boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: Andrei Alexandrescu
 */

// Forwards to warp by emulating the predefined options defined by gcc
// 4.7 or gcc 4.8. Use -version=gcc47 or -version=gcc48 when building.
//
// The predefined preprocessor flags have been
// obtained by running:
//
// g++ -dM -E - </dev/null|sed -e "s/#define /\"-D'/" -e "s/ /=/" -e "s/\$/' \"/"
//
// with the appropriate version of gcc.

import std.algorithm, std.datetime, std.path, std.process, std.stdio,
  std.string;

// Uncomment this line to debug this script
//debug = warpdrive;

// Import the appropriate built-in #define menagerie
version (gcc4_7_1) {
  version = gnu;
  import defines_gcc4_7_1, defines_gxx4_7_1;
}
version (gcc4_8_1) {
  version = gnu;
  import defines_gcc4_8_1, defines_gxx4_8_1;
}
version (clang3_2) {
  version = clang;
  import defines_clang3_2, defines_clangxx3_2;
}
version (clang3_4) {
  version = clang;
  import defines_clang3_4, defines_clangxx3_4;
}
version (clangdev) {
  version = clang;
  import defines_clangdev, defines_clangxxdev;
}

// Compiler-dependent extra defines
version (gnu) {
  immutable extras = [
  "-D_GNU_SOURCE=1",
  "-D__USE_GNU=1",
  ];
}
version (clang) {
  immutable extras = [
    "-D__has_attribute(x)=0",
    "-D__has_builtin(x)=0",
    "-D__has_extension(x)=0",
    "-D__has_feature(x)=0",
    "-D__has_include(x)=0",
    "-D__has_include_next(x)=0",
    "-D__has_warning(x)=0",
  ];
}

// Defines for all builds
immutable defaultOptions = [
  "-D__I86__=6",
  "-D__FUNC__=__func__",
  "-D__FUNCTION__=__func__",
  "-D__PRETTY_FUNCTION__=__func__",
];

// Path to warp binary. If relative, it's assumed to start in the same
// dir as warpdrive. If absolute, then, well, it's absolute.
immutable warp = "warp";

int main(string[] args) {
  debug (warpdrive) stderr.writefln("Exec@%s: %s", Clock.currTime(), warp);
  debug (warpdrive) stderr.writeln(args);

  string[] options;

  // The warp binary is assumed to be in the same directory as
  // warpdrive UNLESS it is actually an absolute path.
  options ~= warp.startsWith('/') ? warp : buildPath(args[0].dirName, warp);
  options ~= defaultOptions;
  options ~= extras;

  string toCompile;
  bool dashOhPassed = false;

  for (size_t i = 1; i < args.length; ++i) {
    auto arg = args[i];
    if (arg.startsWith("-")) {
      if (arg == "--param" || arg == "-iprefix") {
        // There are options set with --param name=value, see e.g.
        // http://gcc.gnu.org/onlinedocs/gcc-3.4.5/gcc/Optimize-Options.html
        // Just skip those. Also skip -iprefix /some/path/. Note that
        // the versions without space after the flag name are taken
        // care of in the test coming after this.
        ++i;
        continue;
      }
      if (arg == "-o") {
        dashOhPassed = true;
        options ~= "-o";
        options ~= args[++i];
        continue;
      }
      // __SANITIZE_ADDRESS__ for ASAN
      if (arg == "-fsanitize=address") {
        options ~= "-D__SANITIZE_ADDRESS__=1";
        continue;
      }
      // __OPTIMIZE__
      if (arg.startsWith("-O") && arg != "-O0") {
        options ~= "-D__OPTIMIZE__=1";
        options ~= "-D__USE_EXTERN_INLINES=1";
        continue;
      }
      if (!arg.startsWith("-isystem", "-I", "-d", "-MF", "-MQ", "-D",
              "-MD", "-MMD")) {
        continue;
      }
      // Sometimes there may be a space between -I and the path, or
      // between "-D" and the macro defined. Merge them.
      if (arg == "-I" || arg == "-D") {
        assert(i + 1 < args.length);
        options ~= arg;
        options ~= args[++i];
        continue;
      }
    } else {
      // This must be the file to compile
      assert(!toCompile, toCompile);
      toCompile = arg;
      continue;
    }
    if (arg == "-MF" || arg == "-MD" || arg == "-MMD") {
      // This is a weird one: optional parameter after -MMD
      if (i + 1 < args.length && args[i + 1].startsWith('-')) {
        // Optional argument
        continue;
      }
      options ~= "--dep=" ~ args[++i];
      continue;
    }
    if (arg == "-MQ") {
      // just skip the object file
      ++i;
      continue;
    }
    if (arg == "-isystem") {
      arg = "--isystem=" ~ args[++i];
    }
    options ~= arg;
  }

  // If no -o default to output to stdout
  if (!dashOhPassed) {
    options ~= "--stdout";
  }

  if (toCompile.endsWith(".c")) {
    options ~= defines;
  } else {
    options ~= xxdefines;
  }

  // Add the file to compile at the very end for easy spotting by humans
  options ~= toCompile;

  debug (warpdrive) {
    string cmd;
    foreach (opt; options) {
      cmd ~= " " ~ escapeShellCommand(opt);
    }
    stderr.writeln(cmd);
  }

  return execvp(options[0], options);
}

/*
 * Local Variables:
 * mode: d
 * c-basic-offset: 4
 * End:
 */
