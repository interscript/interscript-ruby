$: << "."

require 'interscript.rb'



fname = 'sandbox'

#fname = 'odni-che-Cyrl-Latn-2015'

fname = 'iso-kor-Hang-Latn-1996-method1'


$document = Interscript::DSL.parse(fname)

$DEBUG = false

require 'pry'

Pry::ColorPrinter.pp($document.to_hash)

pry
