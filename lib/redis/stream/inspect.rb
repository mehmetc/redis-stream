#encoding: UTF-8
class Redis
  module Stream
    module Inspect
      def groups
        @redis_pool.with do |redis|
          redis.xinfo("groups", @stream)
        end
      rescue Exception => e
        @logger.error("#{@consumer_id} - #{e.message}")
        {}
      end

      def info
        @redis_pool.with do |redis|
          redis.xinfo("stream", @stream)
        end
      end

      def consumers(group = @group)
        @redis_pool.with do |redis|
          redis.xinfo("consumers", @stream, group)
        end
      end

      def del_consumer(group = @group, consumer = @consumer_id)
        @logger.info("#{@consumer_id} - deleting consumer #{group}-#{consumer}")
        @redis_pool.with do |redis|
          redis.xgroup('DELCONSUMER', @stream, group, consumer)
        end
      end

      def del_group(group = @group)
        if consumers(group).length == 0 && groups.map { |m| m["name"] }.include?(group)
          @logger.info("#{@consumer_id} - deleting group #{group}")
          @redis_pool.with do |redis|
            redis.xgroup('DESTROY', @stream, group)
          end
        end
      end

      def pending_messages
        @redis_pool.with do |redis|
          redis.xrange(@stream)
        end
      end
    end #Inspect
  end #Stream
end # Redis