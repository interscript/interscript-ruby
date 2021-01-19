$: << "."

require 'interscript.rb'

#fname = 'odni-che-Cyrl-Latn-2015'
#fname = 'iso-kor-Hang-Latn-1996-method1'
#$document = Interscript::DSL.parse(fname)

$DEBUG = false

#require 'pry'
#Pry::ColorPrinter.pp($document.to_hash)
#pry

#p Interscript::Interpreter.(fname).("강에")

for fname in ["iso-kor-Hang-Latn-1996-method1",
  "odni-che-Cyrl-Latn-2015",
  "var-kor-Hang-Hang-jamo"]
  
  map = Interscript::DSL.parse(fname)
  interp = Interscript::Interpreter.(fname)
  count = 0
  map.tests.data.each do |from, to|
    res = interp.(from)
    p [from, to, res, to == res]
    count += 1 if to == res
  end
  puts "Passing: #{count}"
end
