require 'socket'
require 'zipkin-tracer'

module ZipkinTracer
  class RedisStreamHandler
    def initialize(stream, config = nil)
      @stream = stream

      @config = Config.new(nil, config)
      @tracer = TracerFactory.new.tracer(@config) rescue nil
    end

    def trace(topic, span=nil)
      if @tracer.nil? || @tracer.class.name.eql?("Trace::NullSender")
        yield nil if block_given?
      else
        trace_id = trace_id_from_span(span)
        TraceContainer.with_trace_id(trace_id) do
          trace_id = trace_id.next_id unless span.nil?
          @tracer.with_new_span(trace_id, topic) do |new_span|
            new_span.kind = Trace::Span::Kind::CLIENT
            new_span.record("Session")
            new_span.record_tag('group', @stream.group)
            new_span.record_tag('stream',@stream.stream)
            new_span.record_tag('client', @stream.name)

            yield new_span if block_given?
          end
        end
      end
    rescue Exception => e
      @stream.logger.error(e.message)
      return nil
    end

    def trace_error(msg, span = nil)
      if @tracer.nil? || @tracer.class.name.eql?("Trace::NullSender")
        yield nil if block_given?
      else
        span.record_tag(Trace::Span::Tag::ERROR, msg)
        yield span if block_given?
      end
    rescue Exception => e
      @stream.logger.error(e.message)
      return nil
    end

    private
    def trace_id_from_span(span=nil)
      if span.nil?
        span_id  = TraceGenerator.new.generate_id
        trace_id = TraceGenerator.new.generate_id_from_span_id(span_id)
        parent_span_id = nil
        sampled = false
        flags = 0
        shared = false
      else
        span_h = span.to_h
        span_id  = span_h[:id]
        trace_id = span_h[:traceId]
        parent_span_id = span_h[:parent_span_id]
        sampled = false
        flags = 0
        shared = true
      end

      Trace::TraceId.new(trace_id, parent_span_id, span_id, sampled, flags, shared)
    rescue Exception => e
      @stream.logger.error(e.message)
      return nil
    end


  end
end