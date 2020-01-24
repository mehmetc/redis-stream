#encoding: UTF-8
require 'yaml'
class Redis
  module Stream
    # Simple way to read and manage a config.yml file
    class Config
      @config = {}
      @config_file_path = ""
      @config_file_name = 'config.yml'

      #get name of config file
      # @return [String]    get name of config file
      def self.name
        @config_file_name
      end

      #set config file name defaults to config.yml
      # @param [String] config_file_name      Name of config file
      def self.name=(config_file_name)
        @config_file_name = config_file_name
      end

      # return the current location of the config.yml file
      # @return [String] path of config.yml
      def self.path
        @config_file_path
      end

      # set path to config file
      # @param [String] config_file_path    path to config.yml file
      def self.path=(config_file_path)
        @config_file_path = config_file_path
      end

      # get the value for a key
      # @param [String] key     key of key/value
      # @return [Object] value of key/value pair
      def self.[](key)
        init
        @config[key]
      end

      # set a value into the config.yml file
      # @param [String] key
      # @param [Object] value
      # @return [Object]
      def self.[]=(key, value)
        init
        @config[key] = value
        File.open("#{path}/#{name}", 'w') do |f|
          f.puts @config.to_yaml
        end
      end

      #is key available in config store
      # @param [String] key  key to lookup
      # @return [Boolean]
      def self.include?(key)
        init
        @config.include?(key)
      end

      private

      # load and prepare config.yml
      def self.init
        discover_config_file_path
        if @config.empty?
          config = YAML::load_file("#{path}/#{name}")
          @config = process(config)
        end
      end

      # check if config file is present on system
      # @return [TrueClass, FalseClass]
      def self.file_exists?
        discover_config_file_path
        File.exists?("#{path}/#{name}")
      end

      private

      #determine location of config.yml file
      def self.discover_config_file_path
        if @config_file_path.nil? || @config_file_path.empty?
          if File.exist?(name)
            @config_file_path = '.'
          elsif File.exist?("config/#{name}")
            @config_file_path = 'config'
          end
        end
      end

      #process config.yml file
      # @param [Object] config yaml data
      # @return [Object]
      def self.process(config)
        new_config = {}
        config.each do |k, v|
          if config[k].is_a?(Hash)
            v = process(v)
          end
          new_config.store(k.to_sym, v)
        end

        new_config
      end
    end
  end
end