#encoding: UTF-8
require 'moneta'
require 'redis/stream/config'

class Redis
  module Stream
    class DataCache
      def initialize(logger = Logger.new(STDOUT))
        @logger = logger
        @cache = Moneta.new(:HashFile, dir: Redis::Stream::Config[:data_cache] || "/tmp/cache", serializer: :json)
      end

      def []=(key, value)
        @logger.info("CACHE - #{File.basename(__FILE__)}:#{__LINE__} - caching with key #{key}")
        @cache.store(key, value)
      end

      def [](key)
        @cache.fetch(key)
      end

      def include?(key)
        key?(key)
      end

      def key?(key)
        @cache.key?(key)
      end

      def delete(key)
        @cache.delete(key)
      end

      def key_prefix=(prefix)
        @key_prefix = prefix.downcase
      end

      def key_prefix
        @key_prefix
      end

      def build_key(data)
        key = ""
        if data && data.include?('payload')
          payload_data = data['payload']
        else
          payload_data = data
        end

        if payload_data.include?("id")
          id = payload_data["id"].downcase
          key = "#{id}"
          key = "#{@key_prefix}_#{key}" unless @key_prefix.nil? || @key_prefix&.empty?
        end
        raise "Empty cache key" if key.nil? || key&.empty?
        key
      end

      def resolve_by_message(pid, payload, &block)
        data = nil
        cache_key = build_key(payload)
        invalidate_cache(cache_key, payload)
        data = load_from_cache(cache_key)
        data = load_from_service(pid, cache_key, &block) if data.nil?

        data
      end

      private
      def invalidate_cache(cache_key, payload)
        if payload&.include?('from_cache') && payload['from_cache'].eql?('0')
          delete(cache_key)
          @logger.warn("CACHE - #{File.basename(__FILE__)}:#{__LINE__} - invalidating key #{cache_key}")
        end
      end

      def load_from_cache(cache_key)
        data = nil
        if key?(cache_key)
          @logger.info("CACHE - #{File.basename(__FILE__)}:#{__LINE__} - fetching with key #{cache_key}")
          data = get_from_cache(cache_key)
        end
        data
      end

      def load_from_service(pid, cache_key)
        data = nil
        data = yield pid, cache_key if block_given?

        if data.nil? || data&.empty?
          @logger.warn("CACHE - #{File.basename(__FILE__)}:#{__LINE__} - empty result for key #{cache_key} and id #{pid}")
        end

        data
      end

      def get_from_cache(cache_key)
        key?(cache_key)

        data = self[cache_key]
        if data&.key?('parent')
          data = get_from_cache(self.build_key({'id' => data['parent']}))
        end

        data
      end
    end
  end
end