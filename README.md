# Redis::Stream
### !!!Use jRuby for now. It has a weird bug in cruby

Sugar coating Redis Streams

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'redis-stream'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install redis-stream

## Usage

A simple non-blocking example
```ruby
require 'redis-stream'
s1 =  Redis::Stream::Client.new("test", "LIST", 't1')
s2 =  Redis::Stream::Client.new("test", "MANIFEST", 't2')

s2.on_message do |message|
  m = message['payload']
  puts "Hello #{m}"
  s1.stop
  s2.stop
end

s1.start(false)
s2.start(false)

id = s1.add("World!", "to" => "*", "group" => "MANIFEST", "type" => Redis::Stream::Type::ACTION)

Timeout::timeout(10) do
  loop do
    break unless s1.running? || s2.running?
    sleep 1
    puts "checkin if still active #{s1.running?}, #{s2.running?}"
  end
end
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/redis-stream. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Redis::Stream project’s codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/[USERNAME]/redis-stream/blob/master/CODE_OF_CONDUCT.md).
