def welcome
    languages = [
        ["iso", Translate.new('iso-rus-Cyrl-Latn.yaml')],
        ["icao", Translate.new('icao-rus-Cyrl-Latn.yaml')],
        ["bgnpcgn", Translate.new('bgnpcgn-rus-Cyrl-Latn.yaml')],
        ["bas", Translate.new('bas-rus-Cyrl-Latn.yaml')]

    ]

    puts "Welcome to the Translation Center! Please enter the language you would like to translate to English or you can choose from the list below:"
    languages.each_with_index { |item, index| puts String(index + 1) + '. ' + item[0] }
    language = gets.chomp!.downcase

    index = if /^\d+$/.match(language) then
        Integer(language) - 1
    else
        languages.index { |x| x[0].downcase == language }
    end

    if index.nil? or (language = languages[index][1]).nil?
        puts "Language is not yet supported within Translation Center."
    else
        language.translate
    end
end



class Translate
    def initialize(file_name)
        @file_name = file_name
    end

    def set_translation
        require 'yaml'
        @translations = YAML.load_file(@file_name)
    end

    def create_russian_map(translation,data)
        translation["map"].values[-1].inject({}) do |acc, tuple|
            puts"acc",acc.inspect
            puts"tuple",tuple.inspect
            data.gsub!(tuple.last.capitalize ,tuple.first)
            data.gsub!(tuple.last ,tuple.first)
            puts"data is translate",data.inspect
        end
    end

    def checkQuitCommand(command) 
        if command == "Q"
            puts"Quite"
        end
        command != "Q" 
    end

    def outputResult(fileName, text)
        out_file = File.new(fileName, "w")
        out_file.puts(text)
        out_file.close
        puts "output to converted_#{fileName}"
    end

    def translate
        set_translation()
        
        puts "Enter word or phrase to be translated to authority_id #{@translations["authority_id"]}, press 'Q' to quit:"
        fileName = gets.chomp
        data = File.read(fileName)
        create_russian_map(@translations, data )
        puts "source #{data}"
        if checkQuitCommand(data)
         create_russian_map(@translations, data )
         outputResult("converted_#{fileName}", data)
         translate
        end
    end
   welcome()
end