$: << "."

require 'interscript.rb'



fname = './sandbox.imp'

fname = '../../maps/odni-che-Cyrl-Latn-2015.imp'

#fname = '../../maps/iso-kor-Hang-Latn-1996-method1.imp'


$document = Interscript::DSL.parse(fname)

$DEBUG = false

require 'pry'

Pry::ColorPrinter.pp($document)

pry
