#encoding: UTF-8
class Redis
  module Stream
    module Inspect
      def groups
        @redis.xinfo("groups", @stream)
      rescue Exception => e
        @logger.error("#{@consumer_id} - #{e.message}")
        {}
      end

      def info
        @redis.xinfo("stream", @stream)
      end

      def consumers(group = @group)
        @redis.xinfo("consumers", @stream, group)
      end

      def del_consumer(group = @group, consumer = @consumer_id)
        @logger.info("#{@consumer_id} - deleting consumer #{group}-#{consumer}")
        @redis.xgroup('DELCONSUMER', @stream, group, consumer)
      end

      def del_group(group = @group)
        if consumers(group).length == 0 && groups.map { |m| m["name"] }.include?(group)
          @logger.info("#{@consumer_id} - deleting group #{group}")
          @redis.xgroup('DESTROY', @stream, group)
        end
      end

      def pending_messages
        @redis.xrange(@stream)
      end
    end #Inspect
  end #Stream
end # Redis