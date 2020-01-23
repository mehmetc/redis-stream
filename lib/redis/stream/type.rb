#encoding: UTF-8
class Redis
  module Stream
    module Type
      PING = "PING".freeze
      PONG = "PONG".freeze
      ACTION = "ACTION".freeze

      def self.exists?(type)
        self.constants.include?(type.upcase.to_sym)
      end

      def self.to_s
        self.constants.map { |m| m.to_s.downcase }.join(', ')
      end
    end
  end
end