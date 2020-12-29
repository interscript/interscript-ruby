$: << "."

require 'interscript.rb'

#fname = 'odni-che-Cyrl-Latn-2015'
fname = 'iso-kor-Hang-Latn-1996-method1'
#$document = Interscript::DSL.parse(fname)

$DEBUG = false

require 'pry'
#Pry::ColorPrinter.pp($document.to_hash)
#pry

#p Interscript::Interpreter.(fname).("강에")

for fname in ["iso-kor-Hang-Latn-1996-method1", "odni-che-Cyrl-Latn-2015"]
  map = Interscript::DSL.parse(fname)
  interp = Interscript::Interpreter.(fname)
  map.tests.data.each do |from, to|
    res = interp.(from)
    p [from, to, res, to == res]
  end
end
