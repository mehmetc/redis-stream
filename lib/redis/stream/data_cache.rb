#encoding: UTF-8
require 'moneta'
require 'redis/stream/config'

class Redis
  module Stream
    class DataCache
      def initialize
        @cache = Moneta.new(:HashFile, dir: Redis::Stream::Config[:data_cache] || "/tmp/cache", serializer: :json)
      end

      def []=(key, value)
        @cache.store(key, value)
      end

      def [](key)
        @cache.fetch(key)
      end

      def include?(key)
        @cache.key?(key)
      end

      def delete(key)
        @cache.delete(key)
      end

      def build_key(data)
        key = ""
        if data && data.include?('payload')
          payload_data = data['payload']
        else
          payload_data = data
        end

        if payload_data.include?("id")
          action = payload_data["action"].downcase
          id = payload_data["id"].downcase
          key = "#{action}_#{id}"
        end
        key
      end

    end
  end
end