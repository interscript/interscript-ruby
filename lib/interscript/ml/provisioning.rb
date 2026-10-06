require 'open-uri'
require 'uri'
require 'fileutils'
require 'digest/sha2'
require 'yaml'

module Interscript::ML
  # Module Interscript::ML::Provisioning is to provision remote models locally and to
  # dispatch them later on.
  module Provisioning
    extend self

    @remotes = [] # Here's a place for a global model repository
    @preload_models = []
    attr_accessor :remotes, :preload_models

    def add_remote(path)
      @remotes << path
      @remotes = @remotes.uniq
    end

    def prepare_environment
      return if @set_up

      # We provision the environment in the following way:
      # First, we try the SECRYST_DATA environment variable. If that's available,
      # we use it to store the Secryst data we need. Otherwise, we try the following
      # paths:

      possible_paths = candidate_paths

      # We find the first writable path to become the primary one. The remaining
      # ones will be used read-only if they exist

      @write_path = nil
      @read_paths = []

      ([ENV["INTERSCRIPT_ML_DATA"] || ENV["SECRYST_DATA"]] + possible_paths).compact.each do |path|
        FileUtils.mkdir_p(path)
        @write_path = path unless @write_path
      rescue
      ensure
        @read_paths << path if File.readable?(path)
      end

      raise StandardError, "Can't find a writable path for Secryst. Consider setting a SECRYST_DATA environment variable" unless @write_path

      # Now, let's locate the first Secrystfile to be found
      path = Dir.pwd
      secrystfilepath = loop do
        break unless path =~ %r{[/\\]}
        if File.readable?(path + "/Secrystfile")
          break path + "/Secrystfile"
        end
        path = path.sub(%r{[/\\][^/\\]*?\z}, '')
      end

      # It's found, so let's parse it.
      if secrystfilepath
        secrystfile = Secrystfile.new(secrystfilepath)

        @remotes = secrystfile.remotes + @remotes
        @remotes = @remotes.uniq

        @preload_models = secrystfile.models
      end

      # Load the remotes if they are older than 1 minute
      FileUtils.mkdir_p(@write_path + "/remotes/")
      @loaded_remotes = @remotes.map do |uri|
        cache_path = "#{@write_path}/remotes/#{Digest::SHA256.hexdigest(uri)}.yaml"
        if !File.exist?(cache_path)
          data = URI.open(uri).read
          File.write(cache_path, data)
        elsif File.mtime(cache_path) + 60 < Time.now
          begin
            # Just *try* to download it.
            data = URI.open(uri).read
            File.write(cache_path, data)
          rescue
          end
        end
        Remotefile.new(cache_path, uri: uri)
      end

      # Ok we are done now. We still need to resolve the required paths, but for
      # that let's reuse our existing facilities.
      @set_up = true

      @preload_models.each { |i| locate(i) }
    end

    def self.candidate_paths
      [
        File.join(Dir.home, ".local/share/interscript-ml"),
        File.join(Dir.home, ".local/share/secryst") # legacy fallback
      ]
    end

    def locate(name)
      # Shortcut this if user gave a filename.
      return name if name =~ %r{[.\\/]}

      prepare_environment

      @loaded_remotes.each do |i|
        model = i.resolve(name)
        if model
          model_path = @read_paths.map do |j|
            path = j + "/models/" + model.name
            next path if File.readable?(path)
            nil
          end.compact.first

          if model_path
            version = File.read(model_path + "/version").to_f
            if version >= model.version
              return model_path + "/model.zip"
            else
              return download(model, remote: i)
            end
          else
            return download(model, remote: i)
          end
        end
      end

      raise StandardError, "Model #{name} not found"
    end

    def download(model, remote:)
      uri = model.uri
      if uri.start_with?("./") || uri.start_with?("../")
        remote_uri = remote.uri
        if remote_uri =~ %r{\A/|\A\w:[\\/]}
          remote_uri = "file://"+remote_uri
        end

        uri = URI(remote_uri).merge(uri).to_s
        uri = uri.sub(%r{\Afile://}, '')
      end

      warn "* Downloading a Secryst model #{model.name}:#{model.version} from #{uri}..."

      data = URI.open(uri).read
      path = @write_path + "/models/" + model.name
      FileUtils.mkdir_p path
      File.write(path + "/version", model.version)
      File.write(path + "/model.zip", data)
      return path + "/model.zip"
    end

    class Remotefile
      attr_accessor :uri

      def initialize(path, uri:)
        @yaml = YAML.load_file(path)
        @uri = uri
      end

      def resolve(name)
        @yaml["models"].find do |n, desc|
          if name == n
            return Model.new(name: n, uri: desc["path"], version: desc["version"])
          end
        end
      end

      class Model < Struct.new(:name, :uri, :version, keyword_init: true)
      end
    end

    class Secrystfile
      def initialize(path)
        @path = path
        @models, @remotes = [], []
        self.instance_eval(File.read(path), path)
      end

      def model(name)
        @models << name
      end

      def source(src)
        @remotes << src
      end

      attr_accessor :models, :remotes
    end
  end
end
