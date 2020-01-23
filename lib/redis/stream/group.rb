#encoding: UTF-8
class Redis
  module Stream
    module Group
      THUMBNAIL = "THUMBNAIL".freeze
      STREAM = "STREAM".freeze
      REPRESENTATION = "REPRESENTATION".freeze
      METADATA = "METADATA".freeze
      CACHE = "CACHE".freeze
      LIST = "LIST".freeze
      MANIFEST = "MANIFEST".freeze

      def self.exists?(group)
        self.constants.include?(group.upcase.to_sym)
      end

      def self.to_s
        self.constants.map { |m| m.to_s.downcase }.compact.join(', ')
      end

      def self.lookup(group)
        self.constants.each { |e| return e if e.to_s.downcase.eql?(group.downcase) }

        return '*'
      end
    end
  end
end