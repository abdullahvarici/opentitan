#!/bin/bash

# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

set -e

# The list of bazel tags is represented as a string and checked with a regex
# https://bazel.build/query/language#attr
# This function takes a tag(or regex component) and wraps it so attr can query
# for exact matches.
exact_regex () {
  echo "[\\[ ]${1}[,\\]]"
}

check_empty () {
    if [[ ${2} ]]; then
        echo "$1"
        echo "$2"|sed 's/^/    /';
        echo "$3"
        return 1
    fi
}

# Check for test_suites without the manual tag and announce them
untagged=$(./bazelisk.sh query \
  "kind(test_suite, //...)
  except
  attr(
      tags,
      '$(exact_regex "manual")',
      //...
  )")
check_empty "Note:" "${untagged}" \
"Test_suites above aren't tagged with manual, and probably should be.

Otherwise they will match wildcards like //... and depend on tests so that
build_tag_filters are unable to filter out test_suites unless they are tagged
with the same set of tags as their contents, but if their contents have
different sets of tags, doing so will filter out their contents because of
how most tags act in test_suites.

There aren't many scenarios in which you need a test_suite to match wildcards
(because it's tests are also in the workspace) so you should probably tag it
with manual." || true

# This check ensures OpenTitan software can be built with a wildcard without
# waiting for Verilator using --build_tag_filters=-verilator
untagged=$(./bazelisk.sh query \
  "rdeps(
      //...,
      //hw:verilator
  )
  except
  attr(
      tags,
      '$(exact_regex "(verilator|manual)")',
      //...
  )" \
  --output=label_kind)
check_empty "Error:" "${untagged}" \
"Target(s) above depend(s) on //hw:verilator; please tag it with verilator or
(to prevent matching any wildcards) manual.
NOTE: test_suites that contain bazel tests with different tags should almost
universally use the manual tag."

# This check ensures OpenTitan software can be built with wildcards in
# environments that don't have vivado or vivado tools installed by using
# --build_tag_filters=-vivado.
untagged=$(./bazelisk.sh query \
  "rdeps(
      //...,
      kind(
          'bitstream_splice',
          //...
      )
      except`# Other than those used to build cached bitstreams`
      (
          deps(//hw/bitstream:rom)
          union
          deps(//hw/bitstream:test_rom)
      )
  )
  except
  attr(
      tags,
      '$(exact_regex "(vivado|manual)")',
      //...
  )" \
  --output=label_kind)
check_empty "Error:" "${untagged}" \
"Target(s) above depend(s) on a bitstream_splice that isn't cached.
Please tag it with vivado or (to prevent matching any wildcards) manual.
NOTE: test_suites that contain tests with different sets of tags should almost
universally use the manual tag."
