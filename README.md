image:https://github.com/interscript/interscript-ruby/actions/workflows/rake.yml/badge.svg["CI status", link="https://github.com/interscript/interscript-ruby/actions/workflows/rake.yml"]

# Interscript (Ruby)

The Ruby runtime for https://www.interscript.org[Interscript] —
interoperable script conversion systems. Interscript turns the world's
transliteration standards from paper tables into executable, verifiable
software: authority schemes (BGN/PCGN, ISO, UN/UNGEGN, ALA-LC, ICAO,
ODNI, ...) are encoded once in the ISC language, every runtime produces
provably identical output, and neural models ship under the same proof
regime — pinned artifacts, sha256 verification, frozen conformance
vectors.

== Install

[source,sh]
----
gem install interscript
----

== Transliterate

[source,sh]
----
interscript -s odni-ara-Arab-Latn-2015 ara-Arab.txt -o out.txt
----

[source,ruby]
----
require "interscript"

Interscript.transliterate("odni-rus-Cyrl-Latn-2015", "привет")
# => "privet"
----

== Neural models (Interscript::ML)

The gem embeds the IMF v1 model runtime — resolve a model id through
the interscript-models index, verify its sha256, and run ONNX
inference locally:

[source,ruby]
----
require "interscript/ml"

Interscript::ML::Translator.new(model_file: "urd-diac-base-1.0")
  .translate("...")
----

Runtime dependencies (onnxruntime, rubyzip, numo-narray) are optional
and load lazily; a missing gem raises a `LoadError` naming it. The
artifact contract and frozen conformance vectors live in
https://github.com/interscript/interscript-models[interscript-models]
(see its `conformance/CONFORMANCE.md`).

== The phonological layer

Some transliteration systems need their input vocalized before the map
can apply (undiacritized Arabic, nikud-less Hebrew, unsegmented Thai).
The stdlib ships adapters for this: the `secryst` function dispatches
to a crystal runtime — `pip install secryst`, or `npm i secryst` —
which resolves a model id through the
https://github.com/interscript/interscript-models[models.yaml index]
and runs sha256-verified ONNX inference locally. An engine without a
crystal simply cannot execute maps that declare a vocalization step.

== Development

[source,sh]
----
bundle install
bundle exec rake   # spec suite
----

`SKIP_JS=1 SKIP_PYTHON=1` exclude the cross-compiler *execution* specs
(they need the monorepo's sibling js assets); that coverage is owned by
the CI matrix that runs on every push.

== Release

Push a `v*` tag: the release workflow runs the spec suite, builds the
gem, and publishes via RubyGems.org trusted publishing (OIDC). The
`interscript-maps` dependency is pinned to the published lineage
(`~> 2.5`), not derived from the gem version.

== Project

Purpose, architecture, and direction: see the
https://github.com/interscript/interscript-models#direction-audit-2026-10[project
direction] and https://github.com/interscript/interscript[the project
monorepo].
