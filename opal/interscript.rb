# frozen_string_literal: true
require "maps" 
require "interscript/mapping"

# Transliteration
module Interscript

  class << self

    def transliterate(system_code, string, maps={})
      if (!maps.has_key?system_code)
        maps[system_code] = Interscript::Mapping.for(system_code)
      end
      # mapping = Interscript::Mapping.for(system_code)
      mapping = maps[system_code]


      # First, apply chained transliteration as specified in the list `chain`
      chain = mapping.chain.dup
      while chain.length > 0
        string = transliterate(chain.shift, string, maps)
      end

      # Then, apply the rest of the map
      separator = mapping.character_separator || ""
      word_separator = mapping.word_separator || ""
      title_case = mapping.title_case
      downcase = mapping.downcase

      # charmap = mapping.characters&.sort_by { |k, _v| k.size }&.reverse&.to_h
      # dictmap = mapping.dictionary&.sort_by { |k, _v| k.size }&.reverse&.to_h
      charmap = mapping.characters_hash
      dictmap = mapping.dictionary_hash
      trie = mapping.dictionary_trie

      # Segmentation
      # string = external_process(mapping.segmentation, string) if mapping.segmentation

      # Transliteration/Transcription
      # string = external_process(mapping.transcription, string) if mapping.transcription

      pos = 0
      while pos < string.to_s.size
        m = 0
        wordmatch = ""

        # Using Trie, find the longest matching substring
        while (pos + m < string.to_s.size) && (trie.partial_word?string[pos..pos+m]) 
          wordmatch = string[pos..pos+m] if trie.word?string[pos..pos+m]
          m += 1
        end
        m = wordmatch.length
        if m > 0
          repl = dictmap[string[pos..pos+m-1]]
          string[pos..pos+m-1] = repl
          pos += repl.length
        else
          pos += 1
        end
      end

      output = string.clone
      offsets = Array.new string.to_s.size, 1

      mapping.rules.each do |r|
        output = output.gsub(/#{r['pattern']}/u, r['result'])
      end

      charmap.each do |k, v|
        while (match = output&.match(/#{k}/u))
          pos = match.offset(0).first
          result = !downcase && up_case_around?(output, pos) ? v.upcase : v
          result = result[0] if result.is_a?(Array) # if more than one, choose the first one
          output = output[0, pos] + add_separator(separator, pos, result) + output[(pos+match[0].size)..-1]
        end
      end      

      mapping.postrules.each do |r|
        output = output.gsub(/#{r['pattern']}/u, r['result'])
      end

      if output
        output = output.sub(/^(.)/,  &:upcase) if title_case
        if word_separator != ''
          output = output.gsub(/#{word_separator}#{separator}/u,word_separator)
          output = output.gsub(/#{word_separator}(.)/u, &:upcase) if title_case
        end
      end

      output ? output.unicode_normalize : output
    end

    private

    def add_separator(separator, pos, result)
      pos == 0 ? result : separator + result
    end

    def up_case_around?(string, pos)
      return false if string[pos] == string[pos].downcase

      i = pos - 1
      i -= 1 while i.positive? && string[i] !~ /\p{L}/u
      before = i >= 0 && i < pos ? string[i].to_s.strip : ''

      i = pos + 1
      i += 1 while i < string.size - 1 && string[i] !~ /\p{L}/u
      after = i > pos ? string[i].to_s.strip : ''

      before_uc = !before.empty? && before == before.upcase
      after_uc = !after.empty? && after == after.upcase
      # before_uc && (after.empty? || after_uc) || after_uc && (before.empty? || before_uc)
      before_uc || after_uc
    end
  end
end
