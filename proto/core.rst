Go Protocol buffers
===================

.. _proto_library: https://docs.bazel.build/versions/master/be/protocol-buffer.html#proto_library
.. _default Go plugin: https://github.com/golang/protobuf
.. _common plugins: #predefined-plugins
.. _Go providers: /go/providers.rst
.. _GoLibrary: /go/providers.rst#golibrary
.. _GoSource: /go/providers.rst#gosource
.. _GoArchive: /go/providers.rst#goarchive
.. _Gazelle: https://github.com/bazelbuild/bazel-gazelle
.. _Make variable substitution: https://docs.bazel.build/versions/master/be/make-variables.html#make-var-substitution
.. _Bourne shell tokenization: https://docs.bazel.build/versions/master/be/common-definitions.html#sh-tokenization
.. _gogoprotobuf: https://github.com/gogo/protobuf
.. _compiler.bzl: compiler.bzl

.. role:: param(kbd)
.. role:: type(emphasis)
.. role:: value(code)
.. |mandatory| replace:: **mandatory value**

rules_go provides rules that generate Go packages from .proto files. These
packages can be imported like regular Go libraries.

.. contents:: :depth: 2

-----

Overview
--------

Protocol buffers are built with the three rules below. ``go_proto_library`` and
``go_proto_compiler`` may be loaded from ``@io_bazel_rules_go//proto:def.bzl``.

* `proto_library`_: This is a Bazel built-in rule. It lists a set of .proto
  files in its ``srcs`` attribute and lists other ``proto_library`` dependencies
  in its ``deps`` attribute. ``proto_library`` rules may be referenced by
  language-specific code generation rules like ``java_proto_library`` and
  ``go_proto_library``.
* `go_proto_library`_: Generates Go code from .proto files using one or more
  proto plugins, then builds that code into a Go library. ``go_proto_library``
  references ``proto_library`` sources via the ``proto`` attribute. They may
  reference other ``go_proto_library`` and ``go_library`` dependencies via the
  ``deps`` attributes.  ``go_proto_library`` rules can be depended on or
  embedded directly by ``go_library`` and ``go_binary``.
* `go_proto_compiler`_: Defines a protoc plugin. By default,
  ``go_proto_library`` generates Go code with the `default Go plugin`_, but
  other plugins can be used by setting the ``compilers`` attribute. A few
  `common plugins`_ are provided in ``@io_bazel_rules_go//proto``.

The ``go_proto_compiler`` rule produces a `GoProtoCompiler`_ provider. If you
need a greater degree of customization (for example, if you don't want to use
protoc), you can implement a compatible rule that returns one of these.

The ``go_proto_library`` rule produces the normal set of `Go providers`_. This
makes it compatible with other Go rules for use in ``deps`` and ``embed``
attributes.

API
---

go_proto_library
~~~~~~~~~~~~~~~~

``go_proto_library`` generates a set of .go files from a set of .proto files
(specified in a ``proto_library`` rule), then builds a Go library from those
files. ``go_proto_library`` can be imported like any ``go_library`` rule.

Providers
^^^^^^^^^

* GoLibrary_
* GoSource_
* GoArchive_

Attributes
^^^^^^^^^^

+---------------------+----------------------+-------------------------------------------------+
| **Name**            | **Type**             | **Default value**                               |
+---------------------+----------------------+-------------------------------------------------+
| :param:`name`       | :type:`string`       | |mandatory|                                     |
+---------------------+----------------------+-------------------------------------------------+
| A unique name for this rule.                                                                 |
|                                                                                              |
| By convention, and in order to interoperate cleanly with Gazelle_, this                      |
| should be a name like ``foo_go_proto``, where ``foo`` is the Go package name                 |
| or the last component of the proto package name (hopefully the same). The                    |
| ``proto_library`` referenced by ``proto`` should be named ``foo_proto``.                     |
+---------------------+----------------------+-------------------------------------------------+
| :param:`proto`      | :type:`label`        | |mandatory|                                     |
+---------------------+----------------------+-------------------------------------------------+
| Points to the ``proto_library`` containing the .proto sources this rule                      |
| should generate code from.                                                                   |
+---------------------+----------------------+-------------------------------------------------+
| :param:`deps`       | :type:`label_list`   | :value:`[]`                                     |
+---------------------+----------------------+-------------------------------------------------+
| List of Go libraries this library depends on directly. Usually, this will be                 |
| a list of ``go_proto_library`` rules that correspond to the ``deps`` of the                  |
| ``proto_library`` rule referenced by ``proto``.                                              |
|                                                                                              |
| Additional dependencies may be added by the proto compiler. For example, the                 |
| default compiler implicitly adds dependencies on the ``go_proto_library``                    |
| rules for the Well Known Types.                                                              |
+---------------------+----------------------+-------------------------------------------------+
| :param:`importpath` | :type:`string`       | :value:`""`                                     |
+---------------------+----------------------+-------------------------------------------------+
| The Go import path of this library. If unspecified, this will be inferred                    |
| from the rule's location in the repository.                                                  |
|                                                                                              |
| If `option go_package` is declared in the .proto sources, this string                        |
| should match. However, this takes attribute precedence if the option does                    |
| not match.                                                                                   |
+---------------------+----------------------+-------------------------------------------------+
| :param:`importmap`  | :type:`string`       | :value:`""`                                     |
+---------------------+----------------------+-------------------------------------------------+
| The Go package path of this library. This is mostly only visible to the                      |
| compiler and linker, but it may also be seen in stack traces. This may be                    |
| set to prevent a binary from linking multiple packages with the same import                  |
| path, e.g., from different vendor directories.                                               |
+---------------------+----------------------+-------------------------------------------------+
| :param:`embed`      | :type:`label_list`   | :value:`[]`                                     |
+---------------------+----------------------+-------------------------------------------------+
| List of Go libraries that should be combined with this library. The ``srcs``                 |
| and ``deps`` from these libraries will be incorporated this library when it                  |
| is compiled. Embedded libraries must have the same ``importpath`` and                        |
| Go package name.                                                                             |
+---------------------+----------------------+-------------------------------------------------+
| :param:`gc_goopts`  | :type:`string_list`  | :value:`[]`                                     |
+---------------------+----------------------+-------------------------------------------------+
| List of flags to add to the Go compilation command when using the gc                         |
| compiler. Subject to `Make variable substitution`_ and `Bourne shell tokenization`_.         |
+---------------------+----------------------+-------------------------------------------------+
| :param:`compiler`   | :type:`label`        | :value:`None`                                   |
+---------------------+----------------------+-------------------------------------------------+
| Equivalent to ``compilers`` with a single label.                                             |
+---------------------+----------------------+-------------------------------------------------+
| :param:`compilers`  | :type:`label_list`   | :value:`["@io_bazel_rules_go//proto:go_proto"]` |
+---------------------+----------------------+-------------------------------------------------+
| List of rules producing `GoProtoCompiler`_ providers (normally                               |
| `go_proto_compiler`_ rules). This is usually understood to be a list of                      |
| protoc plugins used to generate Go code. See `Predefined plugins`_ for                       |
| some options.                                                                                |
+---------------------+----------------------+-------------------------------------------------+

Example: Basic proto
^^^^^^^^^^^^^^^^^^^^

Suppose you have two .proto files in separate packages: foo/foo.proto and
bar/bar.proto. foo/foo.proto looks like this:

.. code:: proto

  syntax = "proto3";

  option go_package = "example.com/repo/foo";

  import "google/protobuf/any.proto";
  import "bar/bar.proto";

  message Foo {
    bar.Bar x = 1;
    google.protobuf.Any y = 2;
  };

In foo/BUILD.bazel, we need to declare a ``proto_library`` rule that lists
foo.proto in its ``srcs`` attribute. Since we import some other protos, we
also need a label in ``deps`` for each imported package. We will need to
create another ``proto_library`` in bar/BUILD.bazel, but we can use an
existing library for any.proto, since it's one of the Well Known Types.

.. code:: bzl

  proto_library(
      name = "foo_proto",
      srcs = ["foo.proto"],
      deps = [
          "//bar:bar_proto",
          "@com_google_protobuf//:any_proto",
      ],
      visibility = ["//visibility:public"],
  )

In order to these this proto in Go, we need to declare a ``go_proto_library``
that references to ``proto_library`` to be built via the ``proto`` attribute.
Like ``go_library``, an ``importpath`` attribute needs to be declared.
Ideally, this should match the ``option go_package`` declaration in the .proto
file, but this is not required. We also need to list Go packages that the
generated Go code imports in the ``deps`` attributes. Generally, ``deps``
in ``go_proto_library`` will correspond with ``deps`` in ``proto_library``,
but the Well Known Types don't need to be listed (they are added automatically
by the compiler in use).

.. code:: bzl

  load("@io_bazel_rules_go//proto:def.bzl", "go_proto_library")

  go_proto_library(
      name = "foo_go_proto",
      importpath = "example.com/repo/foo",
      proto = ":foo_proto",
      visibility = ["//visibility:public"],
      deps = ["//bar:bar_go_proto"],
  )

This library can be imported like a regular Go library by other rules.

.. code:: bzl

  load("@io_bazel_rules_go//go:def.bzl", "go_binary")

  go_binary(
      name = "main",
      srcs = ["main.go"],
      deps = ["//foo:foo_go_proto"],
  )

If you need to add additional source files to a package built from protos,
you can do so with a separate ``go_library`` that embeds the
``go_proto_library``.

.. code:: bzl

  load("@io_bazel_rules_go//go:def.bzl", "go_library")

  go_library(
      name = "go_default_library",
      srcs = ["extra.go"],
      embed = [":foo_go_proto"],
      importpath = "example.com/repo/foo",
      visibility = ["//visibility:public"],
  )

For convenience, ``proto_library``, ``go_proto_library``, and ``go_binary``
can all be generated by Gazelle_.

Example: gRPC
^^^^^^^^^^^^^

To compile protos that contain service definitions, just use the ``go_grpc``
plugin.

.. code:: bzl

  load("@io_bazel_rules_go//proto:def.bzl", "go_proto_library")

  proto_library(
      name = "foo_proto",
      srcs = ["foo.proto"],
      visibility = ["//visibility:public"],
  )

  go_proto_library(
      name = "foo_go_proto",
      compilers = ["@io_bazel_rules_go//proto:go_grpc"],
      importpath = "example.com/repo/foo",
      proto = ":foo_proto",
      visibility = ["//visibility:public"],
      deps = ["//bar:bar_go_proto"],
  )

go_proto_compiler
~~~~~~~~~~~~~~~~~

``go_proto_compiler`` describes a plugin for protoc, the proto compiler.
Different plugins will generate different Go code from the same protos.
Compilers may be chosen through the ``compilers`` attribute of
``go_proto_library``. 

Several instances of this rule are listed in `Predefined plugins`_. You will
only need to use this rule directly if you need a plugin which is not there.

Providers
^^^^^^^^^

* GoProtoCompiler_
* GoLibrary_
* GoSource_

Attributes
^^^^^^^^^^

+-----------------------------+----------------------+-----------------------------------------------------+
| **Name**                    | **Type**             | **Default value**                                   |
+-----------------------------+----------------------+-----------------------------------------------------+
| :param:`name`               | :type:`string`       | |mandatory|                                         |
+-----------------------------+----------------------+-----------------------------------------------------+
| A unique name for this rule.                                                                             |
+-----------------------------+----------------------+-----------------------------------------------------+
| :param:`deps`               | :type:`label_list`   | :value:`[]`                                         |
+-----------------------------+----------------------+-----------------------------------------------------+
| List of Go libraries that Go code *generated by* this compiler depends on                                |
| implicitly. Rules in this list must produce the `GoLibrary`_ provider. This                              |
| should contain libraries for the Well Known Types at least.                                              |
+-----------------------------+----------------------+-----------------------------------------------------+
| :param:`options`            | :type:`string_list`  | :value:`[]`                                         |
+-----------------------------+----------------------+-----------------------------------------------------+
| List of command line options to be passed to the compiler. Each option will                              |
| be preceded by ``--option``.                                                                             |
+-----------------------------+----------------------+-----------------------------------------------------+
| :param:`suffix`             | :type:`string`       | :value:`.pb.go`                                     |
+-----------------------------+----------------------+-----------------------------------------------------+
| File name suffix of generated Go files. ``go_proto_compiler`` assumes that                               |
| one Go file will be generated for each input .proto file. Output file names                              |
| will have the .proto suffix removed and this suffix appended. For example,                               |
| ``foo.proto`` will become ``foo.pb.go``.                                                                 |
+-----------------------------+----------------------+-----------------------------------------------------+
| :param:`valid_archive`      | :type:`bool`         | :value:`True`                                       |
+-----------------------------+----------------------+-----------------------------------------------------+
| Whether code generated by this compiler can be compiled into a standalone                                |
| archive file without additional sources.                                                                 |
+-----------------------------+----------------------+-----------------------------------------------------+
| :param:`import_path_option` | :type:`bool`         | :value:`True`                                       |
+-----------------------------+----------------------+-----------------------------------------------------+
| When true, the ``importpath`` attribute from ``go_proto_library`` rules                                  |
| using this compiler will be passed to the compiler on the command line as                                |
| ``--option import_path={}``.                                                                             |
+-----------------------------+----------------------+-----------------------------------------------------+
| :param:`plugin`             | :type:`label`        | :value:`@com_github_golang_protobuf//protoc-gen-go` |
+-----------------------------+----------------------+-----------------------------------------------------+
| The plugin to use with protoc via the ``--plugin`` option. This rule must                                |
| produce an executable file.                                                                              |
+-----------------------------+----------------------+-----------------------------------------------------+

Predefined plugins
------------------

Several ``go_proto_compiler`` rules are predefined in
``@io_bazel_rules_go//proto``.

* ``go_proto``: default plugin from github.com/golang/protobuf.
* ``go_grpc``: default gRPC plugin.
* ``go_proto_validate``: validator plugin from
  github.com/mwitkow/go-proto-validators. Generates ``Validate`` methods.
* gogoprotobuf_ plugins for the variants ``combo``, ``gofast``, ``gogo``,
  ``gogofast``, ``gogofaster``, ``gogoslick``, ``gogotypes``, ``gostring``.
  For each variant, there is a regular version (e.g., ``gogo_proto``) and a
  gRPC version (e.g., ``gogo_grpc``).

Providers
---------

Providers are objects produced by Bazel rules and consumed by other rules that
depend on them. See `Go providers`_ for information about Go providers,
specifically GoLibrary_, GoSource_, and GoArchive_.

GoProtoCompiler
~~~~~~~~~~~~~~~

GoProtoCompiler is the provider returned by the ``go_proto_compiler`` rule and
anything compatible with it. The ``go_proto_library`` rule expects any rule
listed in its ``compilers`` attribute to provide ``GoProtoCompiler``. If the
``go_proto_compiler`` rule doesn't do what you need (e.g., you don't want to
use protoc), you can write a new rule that produces this.

``GoProtoCompiler`` is loaded from ``@io_bazel_rules_go//proto:def.bzl``.

``GoProtoCompiler`` has the fields described below. Additional fields may be
added to pass information to the ``compile`` function. This interface is 
*not final* and may change in the future.

+-----------------------------+-------------------------------------------------+
| **Name**                    | **Type**                                        |
+-----------------------------+-------------------------------------------------+
| :param:`deps`               | :type:`Target list`                             |
+-----------------------------+-------------------------------------------------+
| A list of Go libraries to be added as dependencies to any                     |
| ``go_proto_library`` compiled with this compiler. Each target must provide    |
| GoLibrary_, GoSource_, and GoArchive_. This list should include libraries     |
| for the Well Known Types and anything else considered "standard".             |
+-----------------------------+-------------------------------------------------+
| :param:`compile`            | :type:`Function`                                |
+-----------------------------+-------------------------------------------------+
| A function which declares output files and actions when called. See           |
| `compiler.bzl`_ for details.                                                  |
+-----------------------------+-------------------------------------------------+
| :param:`valid_archive`      | :type:`bool`                                    |
+-----------------------------+-------------------------------------------------+
| Whether the compiler produces a complete Go library. Compilers that just add  |
| methods to structs produced by other compilers will set this to false.        |
+-----------------------------+-------------------------------------------------+

Dependencies
------------

In order to support protocol buffers, rules_go declares the external
repositories listed below in ``go_rules_dependencies()``. These repositories
will only be downloaded if proto rules are used.

* ``@com_google_protobuf (github.com/google/protobuf)``: Well Known Types and
  general proto support.
* ``@com_github_golang_protobuf (github.com/golang/protobuf)``: standard
  Go proto plugin.
* ``@com_github_mwitkow_go_proto_validators
  (github.com/mwitkow/go-proto-validators)``: validator plugin.
* ``@com_github_gogo_protobuf (github.com/gogo/protobuf)``: gogoprotobuf
  plugins.
* ``@org_golang_google_grpc (github.com/grpc/grpc-go``: gRPC support.
* gRPC dependencies

  * ``@org_golang_x_net (golang.org/x/net)``
  * ``@org_golang_x_text (golang.org/x/text)``
  * ``@org_golang_google_genproto (google.golang.org/genproto)``
