# coding: utf-8

require 'rake'

Gem::Specification.new do |s|
  s.name = %q{transcription_kit}
  s.version = '0.0.1'
  s.authors = ['project_contibutors']
  s.required_rubygems_version = Gem::Requirement.new('>= 0') if s.respond_to? :required_rubygems_version=
  s.date = %q{2019-11-16}
  s.description = %q{Transliteration between cyrillic <-> latin | Транслитерация между кириллицей и латиницей }
  s.files = FileList['{bin,lib}/**/*', 'README.markdown'].to_a
  s.bindir = 'bin'
  s.summary = %q{Transliteration between cyrillic <-> latin from command-line or your program | Транслитерация между кириллицей и латиницей с коммандной строки или в твоей программе}
  s.post_install_message = %q{You are ready to transliterate | Вы готовы к транслитерации}
end
