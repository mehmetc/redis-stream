#encoding: UTF-8
class Redis
  module Stream
    module State
      ERROR = -1
      IDLE = 0
      RUNNING = 1
      STOPPED = 2

      def self.exists?(state)
        self.constants.include?(state.upcase.to_sym)
      end

      def self.to_s
        self.constants.map { |m| m.to_s.downcase }.join(', ')
      end
    end
  end
end