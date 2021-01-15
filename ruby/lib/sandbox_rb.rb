$: << "."

require 'pry'
require 'interscript'
require 'interscript/compiler/ruby'

fname = 'iso-kor-Hang-Latn-1996-method1'

# map compilation
$ruby = Interscript::Compiler::Ruby.new(fname)
File.open("#{fname}.rb",'w'){|f| f.write $ruby.code}

# map usage
require './iso-kor-Hang-Latn-1996-method1.rb'
Interscript::Maps.transcribe('iso-kor-Hang-Latn-1996-method1','동녘에')