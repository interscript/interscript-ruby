$: << "."

require 'interscript.rb'

$root = Interscript::Node::Document.new



#$root.parse('./sandbox.imp')
#$root.parse('../../maps/odni-che-Cyrl-Latn-2015.imp')
$root.parse('../../maps/iso-kor-Hang-Latn-1996-method1.imp')

$DEBUG = false

require 'pry'
Pry::ColorPrinter.pp($root)

Pry::ColorPrinter.pp($root.to_hash)
