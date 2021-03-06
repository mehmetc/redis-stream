#encoding: UTF-8
require "redis"
require "connection_pool"
require "logger"
require "json"
require "thread"
require "redis/stream/inspect"
require "redis/stream/config"
require "redis/stream/data_cache"
require "zipkin/tracer"

class Redis
  module Stream
    class Client
      include Redis::Stream::Inspect

      attr_reader :logger, :name, :group, :stream, :consumer_id, :cache, :redis_pool, :non_blocking

      # Initialize: setup rstream
      # @param [String] stream_name        name of the rstream
      # @param [String] group_name         name of the rstream group
      # @param [String] name               name of the Stream Client
      # @param [Object] options       options can contain redis[host, port, db] and logger keys
      #
      # Example: Redis::Stream::Client.new("resolver", "stream", {"logger" => Logger.new(STDOUT)})
      # if group is nil or not supplied then no rstream group will be setup
      def initialize(stream_name, group_name = nil, name = rand(36 ** 7).to_s(36), options = {})
        default_options = {"host" => "127.0.0.1",
                           "port" => 6379,
                           "db" => 0,
                           "config_file_path" => '.',
                           "logger" => Logger.new(STDOUT),
                           "tracer" => nil
        }
        options = default_options.merge(options)

        Redis::Stream::Config.path = options['config_file_path']

        host = options["host"]
        port = options["port"]
        db = options["db"]
        @logger = options["logger"]
        @cache = options.include?('caching') && options['caching'] ? Redis::Stream::DataCache.new : nil
        @name = name
        @state = Redis::Stream::State::IDLE
        @stream = stream_name
        @group = group_name
        if options.include?('redis')
          @logger.info("Taking REDIS as a parameter")
          @redis_pool = ConnectionPool.new(size: 10, timeout: 5) { options['redis'] }
        elsif Redis::Stream::Config.file_exists? && Redis::Stream::Config.include?(:redis)
          @logger.info("Taking REDIS from config file")
          @redis_pool = ConnectionPool.new(size: 10, timeout: 5) { Redis.new(Redis::Stream::Config[:redis]) }
        else
          @logger.info("Instantiating REDIS")
          @redis_pool = ConnectionPool.new(size: 10, timeout: 5) { Redis.new(host: host, port: port, db: db) }
        end
        @consumer_id = "#{@name}-#{@group}-#{Process.pid}"
        @non_blocking = nil
        #  @send_queue = []

        raise "No redis" if @redis_pool.nil? || @redis_pool.available == 0

        if options.has_key?('tracer') && !options['tracer'].nil?
          OpenTracing.global_tracer = options["tracer"]
        elsif Redis::Stream::Config.include?(:zipkin)
          OpenTracing.global_tracer = Zipkin::Tracer.build(url: Redis::Stream::Config[:zipkin], service_name: "#{@name}-#{@group}", flush_interval: 1)
        end

        @state = Redis::Stream::State::RUNNING if options.include?("sync_start") && options["sync_start"]
        setup_stream

        @last_id = info['last-generated-id'] rescue '0'
        @logger.info "#{@consumer_id} - Last ID = #{@last_id}"
      end

      # add: add a message to the stream
      # @param [Object] data                    Any data you want to transmit
      # @param [Hash{String->String}]           Options
      #
      # no passthrough variable here. The passthrough is available in the start method
      def add(data = {}, options = {})
        raise "Client isn't running" unless @state.eql?(Redis::Stream::State::RUNNING)
        add_id = nil
        OpenTracing.start_active_span('add') do |scope|
          default_options = {"to" => "*", "group" => "*", "type" => Redis::Stream::Type::ACTION, "cache_key" => nil, "tracer" => nil}
          options = default_options.merge(options)

          type = options["type"]
          to = options["to"]
          group = options["group"]
          payload = build_payload(data, options)
          add_id = nil
          @redis_pool.with do |redis|
            add_id = redis.xadd(@stream, payload)
          end

          @logger.info("#{@consumer_id} - send to '#{to}' in group '#{group}' with id '#{add_id}' of type '#{type}'")
        end
        add_id
      end

      # sync_add: same as add command but synchronous. Blocks call until a message arrives
      # @param [Object] data                    Any data you want to transmit
      # @param [Hash{String->String}]           Options
      def sync_add(data = {}, options = {})
        raise "Client isn't running" unless @state.eql?(Redis::Stream::State::RUNNING)

        default_options = {"to" => "*", "group" => "*", "type" => Redis::Stream::Type::ACTION, "time_out" => 5, "passthrough" => false, "cache_key" => nil, "tracer" => nil}
        options = default_options.merge(options)

        to = options["to"]
        group = options["group"]
        passthrough = options["passthrough"]
        time_out = options["time_out"]

        #@state = Redis::Stream::State::RUNNING
        data_out = nil
        add_id = add(data, "to" => to, "group" => group, "type" => options["type"], "cache_key" => options["cache_key"], "tracer" => options['tracer'])

        time = Time.now

        loop do
          timing = ((Time.now - time)).to_i
          if timing > time_out
            @logger.info("#{@consumer_id} - Time out(#{time_out}) for '#{to}' in group '#{group}'")
            #@send_queue.delete(add_id) if @send_queue.include?(add_id)
            break
          end
          break if (data_out = read_next_message_from_stream(false, passthrough))
        end
        #@state = Redis::Stream::State::STOPPED
        data_out
      end

      # on_message: execute this block everytime a new message is received
      def on_message(&block)
        @on_message_callback = block
      end

      # start: start listening for stream messages
      #
      # @param [Boolean] block          Should the thread be blocked.
      # @param [Boolean] passthrough    Receive all messages also the ones intended for other consumers
      def start(block = true, passthrough = false)
        raise "#{@consumer_id} already running" if @state == Redis::Stream::State::RUNNING
        @state = Redis::Stream::State::RUNNING
        #sanitize
        if block
          while @state == Redis::Stream::State::RUNNING
            read_next_message_from_stream(true, passthrough)
          end
        else
          @non_blocking = Thread.new do
            while @state == Redis::Stream::State::RUNNING
              read_next_message_from_stream(true, passthrough)
            end
            @logger.info("#{@consumer_id} - ending thread")
          end
        end
      end

      #stop: stop listening for new messages
      def stop
        @state = Redis::Stream::State::STOPPED
        @logger.info("#{@consumer_id} - stopping")
        @non_blocking.join unless @non_blocking.nil?
      ensure
        del_consumer
        del_group
      end

      #running?: Are we still in the running state
      def running?
        t = @non_blocking.nil? ? true : @non_blocking.alive?
        t && @state.eql?(Redis::Stream::State::RUNNING)
      end

      #remove dead and non existing consumers and groups
      def sanitize
        groups.each do |group|
          consumers(group["name"]).each do |consumer|
            if @consumer_id != consumer["name"]
              result = sync_add({}, "to" => consumer["name"], "group" => group["name"], "type" => Redis::Stream::Type::PING, "time_out" => 1)
              if result.nil?
                del_consumer(group['name'], consumer['name'])
              end
            end
          end
        end
      end

      def trace(operation_name, parent_scope = nil)
        # span = OpenTracing.start_span(operation_name)
        # yield span if block_given?
        # span.finish

        # active_scope = OpenTracing.scope_manager.active
        if parent_scope.is_a?(Zipkin::Scope)
          OpenTracing.start_active_span(operation_name, child_of: parent_scope.span) do |scope|
            yield scope if block_given?
          end
        else
          OpenTracing.start_active_span(operation_name) do |scope|
            yield scope if block_given?
          end
        end
      end

      private

      def build_payload(data, options)
        to = options['to']
        group = options['group']
        type = options['type']
        tracer_data = {}
        if options['tracer'].nil?
          tracer_data = nil
        else
          tracer_span = options['tracer']
          OpenTracing.inject(tracer_span.context, OpenTracing::FORMAT_TEXT_MAP, tracer_data)
        end
        payload = nil

        unless @cache.nil?
          if options.include?("cache_key") && not(options['cache_key'].nil?)
            cache_key = options["cache_key"] # @cache.build_key(data)
            if @cache.include?(cache_key)
              if data && data.include?('from_cache') && data['from_cache'].eql?(0)
                @cache.delete(cache_key)
                @logger.info("#{@consumer_id} - invalidating cache with key #{cache_key}")
              else
                payload = {
                    type: type,
                    from: to,
                    from_group: group,
                    to: @consumer_id,
                    to_group: @group,
                    tracer: tracer_data.to_json,
                    payload: @cache[cache_key].to_json
                }
                @logger.info("#{@consumer_id} - fetching from cache with key #{cache_key}")
              end
            else
              #cache_key = @cache.build_key(data)
              unless cache_key.nil? || cache_key.empty?
                @logger.info("#{@consumer_id} - caching with key #{cache_key}")
                @cache[cache_key] = data
              end
            end
          end
        end

        if payload.nil?
          payload = {
              type: type,
              from: @consumer_id,
              from_group: @group,
              to: to,
              to_group: group,
              tracer: tracer_data.to_json,
              payload: data.to_json
          }
        end
        payload
      end

      #setup stream
      def setup_stream
        if @group
          begin
            @redis_pool.with do |redis|
              redis.xgroup(:create, @stream, @group, '$', mkstream: true)
            end
            @logger.info("#{@consumer_id} - Group #{@group} created")
          rescue Redis::CommandError => e
            @logger.error("#{@consumer_id} - Group #{@group} exists")
            @logger.error("#{@consumer_id} - #{e.message}")
          end
        end

        Signal.trap('INT') {
          @logger.info("#{@consumer_id} - Caught CTRL+c")
          stop
        }

        at_exit do
          stop if @state == Redis::Stream::State::RUNNING
          @logger.info("#{@consumer_id} - Done")
        end

        @logger.info("#{@consumer_id} - Listening for incoming requests")
      end

      #handle_incoming: process incoming message
      # @param [Object] message
      def handle_incoming(message)
        if callback = @on_message_callback
          timing = Time.now
          begin
            callback.call(message)
          rescue Exception => e
            @logger.error("#{@consumer_id} - #{e.message} - #{message["payload"].to_json}")
          ensure
            @logger.info("#{@consumer_id} - message from '#{message["from"]}' handled in #{((Time.now.to_f - timing.to_f).to_f * 1000.0).to_i}ms")
          end
        end
      end

      #read message from the stream
      # @param [Boolean] async          return the message if synchronous else call handle_incoming
      # @param [Boolean] passthrough    Receive all messages also the ones intended for other consumers
      def read_next_message_from_stream(async = true, passthrough = false)
        if @state == Redis::Stream::State::RUNNING
          result = nil
          @redis_pool.with do |redis|
            result = redis.xread(@stream, @lastid, block: 1000, count: 1) if @group.nil?
            result = redis.xreadgroup(@group, @consumer_id, @stream, '>', block: 1000, count: 1) if @group
          end

          unless result.empty?
            id, data_out = result[@stream][0]
            ack_count = 0
            @redis_pool.with do |redis|
              ack_count = redis.xack(@stream, @group, id) if @group
            end
            tracer_data = JSON.parse(data_out["tracer"])
            unless tracer_data.nil? || tracer_data.empty?
              #trace_scope.span.log_kv('has_tracer' => true)
              tracer_span = OpenTracing.extract(OpenTracing::FORMAT_TEXT_MAP, tracer_data)
              data_out["tracer"] = OpenTracing.start_span(@consumer_id, child_of: tracer_span)
            end

            begin
              data_out["payload"] = JSON.parse(data_out["payload"])
            rescue Exception => e
              @logger.error("#{@consumer_id} error parsing payload: #{e.message}")
            end

            if data_out["from"].eql?(@consumer_id)
              return false
            end

            unless passthrough
              unless (data_out["to"].nil? || data_out["to"].eql?('') || data_out["to"].eql?('*') || data_out["to"].eql?(@consumer_id)) &&
                     (data_out["to_group"].nil? || data_out["to_group"].eql?('') || data_out["to_group"].eql?('*') || data_out["to_group"].eql?(@group))
                @logger.info("#{@consumer_id} - ignoring message from '#{data_out["from"]}' to '#{data_out["to"]}-#{data_out["to_group"]}'")

                return false
              end
            end

            @logger.info("#{@consumer_id} - received from '#{data_out["from"]}' of type '#{data_out['type']}' to '#{data_out["to"]}' in group '#{data_out["to_group"]}' with message id '#{id}' - with ack #{ack_count}")

            if data_out["type"].eql?(Redis::Stream::Type::PING)
              add(data_out["payload"].to_s, "to" => data_out["from"], "group" => "*", "type" => Redis::Stream::Type::PONG)
              return false
            end

            if data_out["type"].eql?(Redis::Stream::Type::PONG)
              return true
            end

            return data_out unless async
            handle_incoming(data_out)
          end
        end
      rescue Exception => e
        return false
      end
    end
  end
end