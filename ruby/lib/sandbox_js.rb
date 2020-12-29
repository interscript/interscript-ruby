$: << "."

require 'pry'
require 'interscript'
require 'interscript/compiler/javascript'

fname = 'iso-kor-Hang-Latn-1996-method1'
puts Interscript::Compiler::Javascript.(fname).code
