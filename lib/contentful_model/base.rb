module ContentfulModel
  class Base < Contentful::DynamicEntry
    include ContentfulModel::ChainableQueries
    include ContentfulModel::Associations
    include ContentfulModel::Validations
    include ContentfulModel::Manageable

    def initialize(*args)
      super
      define_getters
      self.class.coercions ||= {}
    end

    private

    def define_getters
      fields.each do |k, v|
        if Contentful::Constants::KNOWN_LOCALES.include?(k.to_s)
          v.keys.each do |name|
            define_getter(name)
          end
        else
          define_getter(k)
        end
      end
    end

    def define_getter(name)
      define_singleton_method "#{name.to_s.underscore}" do
        fields(default_locale)[name]
      end
    end

    #use method_missing to call fields on the model
    def method_missing(method, *args, &block)
      result = fields[:"#{method.to_s.camelize(:lower)}"]
      # we need to pull out any Contentful::Link references, and also things which don't have any fields at all
      # because they're newly created
      if result.is_a?(Array)
        result.reject! {|r| r.is_a?(Contentful::Link) || (r.respond_to?(:invalid) && r.invalid?)}
      elsif result.is_a?(Contentful::Link)
        result = nil
      elsif result.respond_to?(:fields) && result.send(:fields).empty?
        result = nil
      elsif result.respond_to?(:invalid?) && result.invalid?
        result = nil
      end

      if result.nil?
        # if self.class.rescue_from_no_attribute_fields.member?()
        # end
        if self.class.return_nil_for_empty_attribute_fields && self.class.return_nil_for_empty_attribute_fields.include?(method)
          return nil
        else
          raise ContentfulModel::AttributeNotFoundError, "no attribute #{method} found"
        end
      else
        # if there's no coercion specified, return the result
        if self.class.coercions[method].nil?
          return result
        #if there's a coercion specified for the field and it's a proc, pass the result
        #to the proc
        elsif self.class.coercions[method].is_a?(Proc)
          return self.class.coercions[method].call(result)
        #provided the coercion is in the COERCIONS constant, call the proc on that
        elsif !self.class::COERCIONS[self.class.coercions[method]].nil?
          return self.class::COERCIONS[self.class.coercions[method]].call(result)
        else
          #... or just return the result
          return result
        end
      end
    end

    def respond_to_missing?(method, private=false)
      if fields[:"#{method.to_s.camelize(:lower)}"].nil?
         super
      else
        true
      end
    end

    def cache_key(*timestamp_names)
      if timestamp_names.present?
        raise ArgumentError, "ContentfulModel::Base models don't support named timestamps."
      end

      "#{self.class.to_s.underscore}/#{self.id}-#{self.updated_at.utc.to_s(:number)}"
    end

    class << self
      attr_accessor :content_type_id, :coercions, :return_nil_for_empty_attribute_fields

      def descendents
        ObjectSpace.each_object(Class).select { |klass| klass < self }
      end

      def add_entry_mapping
        unless ContentfulModel.configuration.entry_mapping.has_key?(@content_type_id)
          ContentfulModel.configuration.entry_mapping[@content_type_id] = self.to_s.constantize
        end
      end

      def client
        # add an entry mapping for this content type
        self.add_entry_mapping
        if ContentfulModel.use_preview_api
          @preview_client ||= ContentfulModel::Client.new(ContentfulModel.configuration.to_hash)
        else
          @client ||= ContentfulModel::Client.new(ContentfulModel.configuration.to_hash)
        end
      end

      def content_type
        client.content_type(@content_type_id)
      end

      def coerce_field(*coercions)
        @coercions ||= {}
        coercions.each do |coercions_hash|
          @coercions.merge!(coercions_hash)
        end
        @coercions
      end

      def return_nil_for_empty(*fields)
        @return_nil_for_empty_attribute_fields ||= []

        fields.each do |field|
          define_method field do
            begin
              super()
            rescue ContentfulModel::AttributeNotFoundError
              nil
            end
          end

          @return_nil_for_empty_attribute_fields.push(field)
        end
      end
    end
  end
end
