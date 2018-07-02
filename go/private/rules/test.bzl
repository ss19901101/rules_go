# Copyright 2014 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

load(
    "@io_bazel_rules_go//go/private:context.bzl",
    "go_context",
)
load(
    "@io_bazel_rules_go//go/private:common.bzl",
    "asm_exts",
    "go_exts",
    "split_srcs",
    "pkg_dir",
)
load(
    "@io_bazel_rules_go//go/private:rules/prefix.bzl",
    "go_prefix_default",
)
load(
    "@io_bazel_rules_go//go/private:rules/binary.bzl",
    "gc_linkopts",
)
load(
    "@io_bazel_rules_go//go/private:providers.bzl",
    "INFERRED_PATH",
    "GoLibrary",
    "get_archive",
)
load(
    "@io_bazel_rules_go//go/private:rules/aspect.bzl",
    "go_archive_aspect",
)
load(
    "@io_bazel_rules_go//go/private:rules/rule.bzl",
    "go_rule",
)
load(
    "@io_bazel_rules_go//go/private:mode.bzl",
    "LINKMODE_NORMAL",
)

def _testmain_library_to_source(go, attr, source, merge):
  source["deps"] = source["deps"] + [attr.library]

def _go_test_impl(ctx):
  """go_test_impl implements go testing.

  It emits an action to run the test generator, and then compiles the
  test into a binary."""

  go = go_context(ctx)

  # Compile the library to test with internal white box tests
  internal_library = go.new_library(go, testfilter="exclude")
  internal_source = go.library_to_source(go, ctx.attr, internal_library, ctx.coverage_instrumented())
  internal_archive = go.archive(go, internal_source)
  go_srcs = split_srcs(internal_source.srcs).go

  # Compile the library with the external black box tests
  external_library = go.new_library(go,
      name = internal_library.name + "_test",
      importpath = internal_library.importpath + "_test",
      testfilter="only",
  )
  external_source = go.library_to_source(go, struct(
      srcs = [struct(files=go_srcs)],
      deps = internal_archive.direct + [internal_archive],
      x_defs = ctx.attr.x_defs,
  ), external_library, ctx.coverage_instrumented())
  external_archive = go.archive(go, external_source)
  external_srcs = split_srcs(external_source.srcs).go

  # now generate the main function
  if ctx.attr.rundir:
    if ctx.attr.rundir.startswith("/"):
      run_dir = ctx.attr.rundir
    else:
      run_dir = pkg_dir(ctx.label.workspace_root, ctx.attr.rundir)
  else:
    run_dir = pkg_dir(ctx.label.workspace_root, ctx.label.package)

  main_go = go.declare_file(go, "testmain.go")
  arguments = go.args(go)
  arguments.add(['-rundir', run_dir, '-output', main_go])
  if ctx.configuration.coverage_enabled:
    arguments.add(["-coverage"])
  arguments.add([
      # the l is the alias for the package under test, the l_test must be the
      # same with the test suffix
      '-import', "l="+internal_source.library.importpath,
      '-import', "l_test="+external_source.library.importpath])
  arguments.add(go_srcs, before_each="-src", format="l=%s")
  ctx.actions.run(
      inputs = go_srcs,
      outputs = [main_go],
      mnemonic = "GoTestGenTest",
      executable = go.builders.test_generator,
      arguments = [arguments],
      env = {
          "RUNDIR" : ctx.label.package,
      },
  )

  # Now compile the test binary itself
  test_library = GoLibrary(
      name = go._ctx.label.name + "~testmain",
      label = go._ctx.label,
      importpath = "testmain",
      importmap = "testmain",
      pathtype = INFERRED_PATH,
      resolve = None,
  )
  test_deps = external_archive.direct + [external_archive]
  if ctx.configuration.coverage_enabled:
    test_deps.append(go.coverdata)
  test_source = go.library_to_source(go, struct(
      srcs = [struct(files=[main_go])],
      deps = test_deps,
  ), test_library, False)
  test_archive, executable, runfiles = go.binary(go,
      name = ctx.label.name,
      source = test_source,
      test_archives = [internal_archive.data],
      gc_linkopts = gc_linkopts(ctx),
      version_file=ctx.version_file,
      info_file=ctx.info_file,
  )

  # Bazel only looks for coverage data if the test target has an
  # InstrumentedFilesProvider, but this provider can currently only be
  # created using "legacy" provider syntax. Old and new provider syntaxes
  # can be combined by putting new-style providers in a providers field
  # of the old-style struct.
  # If the provider is found and at least one source file is present, Bazel
  # will set the COVERAGE_OUTPUT_FILE environment variable during tests
  # and will save that file to the build events + test outputs.
  return struct(
      providers = [
          test_archive,
          DefaultInfo(
              files = depset([executable]),
              runfiles = runfiles,
              executable = executable,
          ),
      ],
      instrumented_files = struct(
          extensions = ['go'],
          source_attributes = ['srcs'],
          dependency_attributes = ['deps', 'embed'],
      ),
  )


go_test = go_rule(
    _go_test_impl,
    attrs = {
        "data": attr.label_list(
            allow_files = True,
            cfg = "data",
        ),
        "srcs": attr.label_list(allow_files = go_exts + asm_exts),
        "deps": attr.label_list(
            providers = [GoLibrary],
            aspects = [go_archive_aspect],
        ),
        "embed": attr.label_list(
            providers = [GoLibrary],
            aspects = [go_archive_aspect],
        ),
        "importpath": attr.string(),
        "pure": attr.string(
            values = [
                "on",
                "off",
                "auto",
            ],
            default = "auto",
        ),
        "static": attr.string(
            values = [
                "on",
                "off",
                "auto",
            ],
            default = "auto",
        ),
        "race": attr.string(
            values = [
                "on",
                "off",
                "auto",
            ],
            default = "auto",
        ),
        "msan": attr.string(
            values = [
                "on",
                "off",
                "auto",
            ],
            default = "auto",
        ),
        "gc_goopts": attr.string_list(),
        "gc_linkopts": attr.string_list(),
        "rundir": attr.string(),
        "x_defs": attr.string_dict(),
        "linkmode": attr.string(default=LINKMODE_NORMAL),
    },
    executable = True,
    test = True,
)
"""See go/core.rst#go_test for full documentation."""
