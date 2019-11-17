module TranscriptionKit
    def self.convert(file_name, write_file, output_file)
        @file_name = file_name
        @file = write_file
        @output_file = output_file
        self.set_translation(@file_name, @file, @output_file)
    end

    def self.set_translation(file_name, file, output_file)
        require 'yaml'
        @translations = YAML.load_file(file_name)
        self.create_russian_map(@translations,file,output_file)
    end

    def self.create_russian_map(translation,fileName,output_file)
        my_hash =   translation["map"]["characters"]
        data = File.read(fileName)
        data.split('').map do |char|
            is = my_hash[char] ? my_hash[char] : char 
            data[char] = is
        end
        self.outputResult(output_file, data)
    end

    def self.outputResult(fileName, text)
        out_file = File.new(fileName, "w")
        out_file.puts(text)
        out_file.close
        puts "output to #{fileName}"
    end
end