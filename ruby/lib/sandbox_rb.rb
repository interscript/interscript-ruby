$: << "."

require 'pry'
require 'interscript'
require 'interscript/compiler/ruby'

fname = 'iso-kor-Hang-Latn-1996-method1'

$ruby = Interscript::Compiler::Ruby.(fname)
File.open("sandbox_isc.rb",'w'){|f| f.write $ruby.code}



