# Redis::Stream

Sugar coating Redis Streams

TODO: add documentation

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

Load the stream library
```ruby
require 'redis/stream'
```
Available objects
### Redis::Stream::Config
Simple way to read and manage a config file. It looks for a config.yml file in the current and './config' directory.
#### _name_
name defaults to config.yml
```ruby 
    include Redis::Stream
    puts Config.name
    Config.name = "test.yml"
``` 
#### _path_
path to the config file
```ruby 
    include Redis::Stream
    puts Config.path
    Config.path = "./configDEV"
```
#### _[key]_
reads and writes the key or key/value from/to the config file
```ruby 
    include Redis::Stream
    puts Config[:cache]
    Config[:cache] = "./cache"
```

#### include?(key)
check if key exists in the config file
#### file_exists?()
check if the config file exists 
#### _init_
This function is called implicitly. You do not need to call it


### Redis::Stream::Client
### Redis::Stream::Inspect
### Redis::Stream::Type
### Redis::Stream::DataCache



#### A simple non-blocking example
```ruby
require 'redis/stream'
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

#### Microservices example

1. Sinatra as a point of entry
```    http://127.0.0.1:4567?reverse=word```
2. Microservice for processing

# http.rb
```ruby
require 'sinatra'
require 'redis/stream'

class GreetingsApp < Sinatra::Base
  configure do
      set :inline_templates, true
      set :redis_stream, Redis::Stream::Client.new("greetings", "HTTP", "http_client", "sync_start" => true, "caching" => false)
  end

  get '/' do
    halt 500, 'reverse parameter not found' unless params.include?(:reverse)
    result = settings.redis_stream.sync_add(params[:reverse], "group" => "GREETER", "time_out" => 60)
    @reverse  = params[:reverse]
    @reversed = ''
    @reversed = result['payload'] if result && result.include?('payload')
    erb :index
  end
end

GreetingsApp.run!


__END__

@@index

<!DOCTYPE html>
<head><title>Reverse Greeter</title></head>
<body>
<p><%= @reverse %> &lt;=&gt; <%= @reversed %></p>
</body>
</html>
```

# reverse_greeter.rb
```ruby
require 'redis/stream'

reverse_greeter = Redis::Stream::Client.new("greetings", "GREETER", "reverse_greeter")
reverse_greeter.on_message do |message|
    begin
      greeting = message['payload']
      reverse_greeter.add(greeting.reverse, "to" => message['from'])
    rescue Exception => e
    end
end

reverse_greeter.start(true, false)
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/mehmetc/redis-stream. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Redis::Stream project’s codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/[USERNAME]/redis-stream/blob/master/CODE_OF_CONDUCT.md).
