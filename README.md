image:https://github.com/interscript/interscript-ruby/actions/workflows/rake.yml/badge.svg["CI status", link="https://github.com/interscript/interscript-ruby/actions/workflows/rake.yml"]
# Interscript

Documentation is available directory higher in file README.adoc.

## Phonological layer (optional)

Some transliteration systems need their input vocalized before the map
can apply (undiacritized Arabic, nikud-less Hebrew, unsegmented Thai).
The stdlib ships adapters for this: the `secryst` function dispatches
to a [secryst crystal](https://www.secryst.org) —
`gem 'secryst'` (Ruby), `pip install secryst`, or `npm i secryst` —
which resolves a model id through the
[interscript-ml `models.yaml` index](https://github.com/interscript/interscript-ml)
and runs sha256-verified ONNX inference locally. The gem has no
interscript dependency: a crystal can be used standalone for any G2P
need, and an engine without a crystal simply cannot execute maps that
declare a vocalization step.

## ML models (Interscript::Ml)

The gem also runs the IMF v1 neural models published by
[interscript-models](https://github.com/interscript/interscript-models)
(diacritization, G2P — sha256-verified downloads, byte-exact with the
python/TypeScript runtimes):

```ruby
require "interscript/ml"

Interscript::Ml.translate("urd-diac-base-1.0", "کلیدهای پرکینزمانند")
# => "کْلِیدْہای پْرْکِنْزْمانْد"
```

Needs the `onnxruntime`, `rubyzip`, and `numo-narray` gems at runtime
(`gem install onnxruntime rubyzip numo-narray`). Use **fp32** artifacts
— the onnxruntime ruby binding lacks float16 support (fp16 zips raise a
clear error). Models resolve against index-v12; override with
`INTERSCRIPT_ML_INDEX`.
