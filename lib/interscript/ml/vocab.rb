module Interscript::ML
  class Vocab
    UNK = "<unk>"
    attr_reader :stoi, :itos

    def initialize(
      list, specials: ["<unk>", "<pad>", "<sos>", "<eos>"], specials_first: true
    )
      @unk_index = nil
      @itos = []
      if specials_first && (list & specials).length == 0
        @itos = specials
      end

      @itos += list

      if !specials_first && (list & specials).length == 0
        @itos.concat(specials)
      end

      # Automatic substitution of unknown symbols
      if @itos.include?("<unk>")
        unk_index = @itos.index("<unk>")
        @stoi = Hash.new(unk_index)
      elsif @itos.include?("[UNK]")
        unk_index = @itos.index("[UNK]")
        @stoi = Hash.new(unk_index)
      else
        @stoi = {}
      end


      # stoi is simply a reverse dict for itos
      @itos.each_with_index do |tok, i|
        @stoi[tok] = i
      end
    end

    def [](token)
      @stoi.fetch(token, @stoi.fetch(UNK))
    end

    def length
      @itos.length
    end
    alias_method :size, :length
  end
end