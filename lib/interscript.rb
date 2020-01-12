# frozen_string_literal: true

require "yaml"
require "interscript/mapping"

# Transliteration
module Interscript
  class << self
    def root_path
      @root_path ||= Pathname.new(File.dirname(__dir__))
    end

    def transliterate_file(system_code, input_file, output_file)
      input = File.read(input_file)
      output = transliterate(system_code, input)

      File.open(output_file, 'w') do |f|
        f.puts(output)
      end
      puts "Output written to: #{output_file}"
    end

    def transliterate(system_code, string)
      mapping = Interscript::Mapping.for(system_code)
      character_separator = mapping.character_separator || ""
      charmap = mapping.characters&.sort_by { |k, _v| k.size }&.reverse&.to_h

      output = string.clone
      offsets = Array.new string.to_s.size, 1

      mapping.rules.each do |r|
        string.to_s.scan(/#{r['pattern']}/) do |matches|
          match = Regexp.last_match
          pos = match.offset(0).first
          result = r['result'].clone
          matches.each.with_index { |v, i| result.sub!(/\\#{i + 1}/, v) } if matches.is_a? Array
          result.upcase! if up_case_around?(string, pos)
          output[offsets[0...pos].sum, match[0].size] = result
          offsets[pos] += result.size - match[0].size
        end
      end

      charmap.each do |k, v|
        while (match = output&.match(/#{k}/))
          pos = match.offset(0).first
          result = up_case_around?(output, pos) ? v.upcase : v
          result = result[0] if result.is_a?(Array) # if more than one, choose the first one
          output[pos, match[0].size] = character_separator + result
        end
      end

      mapping.postrules.each do |r|
        output.gsub!(/#{r['pattern']}/, r['result'])
      end

      output
    end

    private

    def up_case_around?(string, pos)
      return false if string[pos] == string[pos].downcase

      i = pos - 1
      i -= 1 while i.positive? && string[i] !~ /[[:alpha:]]/
      before = i >= 0 && i < pos ? string[i].to_s.strip : ''

      i = pos + 1
      i += 1 while i < string.size - 1 && string[i] !~ /[[:alpha:]]/
      after = i > pos ? string[i].to_s.strip : ''

      !before.empty? && before == before.upcase || !after.empty? && after == after.upcase
    end
  end
end
