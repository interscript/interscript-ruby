$: << "."

#require 'pry'
require 'interscript'
require 'interscript/compiler/ruby'

fname = 'iso-kor-Hang-Latn-1996-method1'

# map compilation
$ruby = Interscript::Compiler::Ruby.(fname)
puts $ruby.code

puts $ruby.('동녘에')
