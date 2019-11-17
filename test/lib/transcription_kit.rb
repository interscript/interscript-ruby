
module TranscriptionKit
    def self.files(file_name, write_file)
        @file_name = file_name
        @file = write_file
        self.set_translation(@file_name, @file)
    end

    def self.set_translation(file_name, file)
        require 'yaml'
        @translations = YAML.load_file(file_name)
        self.create_russian_map(@translations,file)
    end

    def self.create_russian_map(translation,fileName)
        puts"aaaaaaaaaaaaaa #{translation["map"]["characters"]}"
        my_hash =   translation["map"]["characters"].invert
        data = File.read(fileName)
        data.split('').map do |char|
            is = my_hash[char] ? my_hash[char] : char 
            data[char] = is
        end

        puts"===== #{data}"
        self.outputResult("converted_#{fileName}", data)


    end

    def self.outputResult(fileName, text)
        out_file = File.new(fileName, "w")
        out_file.puts(text)
        out_file.close
        puts "output to converted_#{fileName}"
    end
end

puts TranscriptionKit.files('bgnpcgn-rus-Cyrl-Latn.yaml' , "aaa")