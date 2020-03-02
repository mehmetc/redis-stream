require "test_helper"
require "timeout"

class Redis::StreamTest < Minitest::Test
  def test_create_client
    s1 = Redis::Stream::Client.new("test", "LIST", 't1')
    assert_equal(s1.class, Redis::Stream::Client)
    s1.stop
  end

  def test_send_message_between_two_non_blocking_streams
    s1 =  Redis::Stream::Client.new("test", "LIST", 't1')
    s2 =  Redis::Stream::Client.new("test", "MANIFEST", 't2')

    s2.on_message do |message|
      m = message
      assert_equal("hello", m['payload'])
      s1.stop
      s2.stop
    end

    s1.start(false)
    s2.start(false)

    id = s1.add("hello", "to" => "*", "group" => "MANIFEST", "type" => Redis::Stream::Type::ACTION)
    assert(!id.empty?, id)

    Timeout::timeout(10) do
      loop do
        break unless s1.running? || s2.running?
        sleep 1
        puts "checkin if still active #{s1.running?}, #{s2.running?}"
      end
    end

    assert_equal(s1.running?, false)
    assert_equal(s2.running?, false)
  end

  def test_sync_stream
    s1 = Redis::Stream::Client.new('test', "HTTP", "http_agent", "sync_start" => true, "caching" => false)
    s2 = Redis::Stream::Client.new("test", "MANIFEST", 'manifest_client', "caching" => false)

    s2.on_message do |message|
      m = message
      assert_equal("hello", m['payload'])
      id = s2.add("world", "to" => "*", "group" => "HTTP", "type" => Redis::Stream::Type::ACTION)
      assert(!id.empty?, id)
    end

    s2.start(false)
    result = s1.sync_add("hello", "to" => "*", "group" => "MANIFEST", "type" => Redis::Stream::Type::ACTION)
    assert(result.include?('payload'), result)
    assert_equal(result['payload'], "world")

    s1.stop
    s2.stop
    Timeout::timeout(10) do
      loop do
        break unless s1.running? || s2.running?
        sleep 1
        puts "checkin if still active #{s1.running?}, #{s2.running?}"
      end
    end

    assert_equal(s1.running?, false)
    assert_equal(s2.running?, false)
  end

  def test_zipkin
    s1 = Redis::Stream::Client.new('test', "HTTP", "http_agent", "sync_start" => true, "caching" => false)
    s2 = Redis::Stream::Client.new("test", "MANIFEST", 'manifest_client', "caching" => false)


    s2.on_message do |message|
      s2.trace('on_message', message['tracer']) do |scope|
        scope.span.set_tag("data", "world")

        id = s2.add("world", "to" => "*", "group" => "HTTP", "type" => Redis::Stream::Type::ACTION, "tracer" => scope.span)
        scope.span.set_tag('id', id)

        s2.trace("get_manifest", scope) do |mscope|
          mscope.span.set_tag('manifest_type','iiif')
        end
        scope.span.set_tag('error', 'oops')
        assert_equal(3, scope.span.tags.size)
      end
    end

    s2.start(false)
    result = s1.sync_add("hello", "to" => "*", "group" => "MANIFEST", "type" => Redis::Stream::Type::ACTION)

    assert_equal('world', result['payload'])
    s1.stop
    s2.stop
    Timeout::timeout(10) do
      loop do
        break unless s1.running? || s2.running?
        sleep 1
        puts "checkin if still active #{s1.running?}, #{s2.running?}"
      end
    end
  end
end
