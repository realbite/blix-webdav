module Blix::WebDAV

  class Resource

    attr_reader :path, :options

    include HTTPStatus

    def initialize(path, request, options)
      @path = path
      @request = request
      @options = options
      @parts = @path.split('/')
      raise Forbidden if @parts.include?('..')
    end

    # If this is a collection, return the child resources.
    def children
      raise NotImplementedError
    end

    # Is this resource a collection?
    def collection?
      raise NotImplementedError
    end

    # Does this recource exist?
    def exist?
      raise NotImplementedError
    end

    # Return the creation time.
    def creation_date
      raise NotImplementedError
    end

    # Return the time of last modification.
    def last_modified
      raise NotImplementedError
    end

    # Set the time of last modification.
    def last_modified=(time)
      raise NotImplementedError
    end

    # Return an Etag, an unique hash value for this resource.
    def etag
      raise NotImplementedError
    end

    # Return the resource type.
    #
    # If this is a collection, return a collection element
    def resource_type
      if collection?
        Nokogiri::XML::fragment('<D:collection xmlns:D="DAV:"/>').children.first
      end
    end

    # Return the mime type of this resource.
    def content_type
      raise NotImplementedError
    end

    # Return the size in bytes for this resource.
    def content_length
      raise NotImplementedError
    end

    # HTTP GET request.
    #
    # Write the content of the resource to the response.body.
    def get
      raise NotImplementedError
    end

    # HTTP PUT request.
    #
    # Save the content of the request.body.
    def put
      raise NotImplementedError
    end

    # HTTP POST request.
    #
    # Usually forbidden.
    def post
      raise NotImplementedError
    end

    # HTTP DELETE request.
    #
    # Delete this resource.
    def delete
      raise NotImplementedError
    end

    # HTTP COPY request.
    #
    # Copy this resource to given destination resource.
    def copy(dest)
      raise NotImplementedError
    end

    # HTTP MOVE request.
    #
    # Move this resource to given destination resource.
    def move(dest)
      copy(dest)
      delete
    end

    # HTTP MKCOL request.
    #
    # Create this resource as collection.
    def make_collection
      raise NotImplementedError
    end

    def ==(other)
      path == other.path
    end

    def name
      File.basename(path)
    end

    def display_name
      name
    end

    def child(name, option={})
      filepath = File.join(path,name)
      self.class.new(filepath, @request, options)
    end

    def lockable?
      self.respond_to?(:lock) && self.respond_to?(:unlock)
    end

    def property_names
      %w(creationdate displayname getlastmodified getetag resourcetype getcontenttype getcontentlength)
      #%w(displayname resourcetype)
    end

    def get_property(name)
      case name
      when 'resourcetype'     then resource_type
      when 'displayname'      then display_name
      when 'creationdate'     then creation_date.xmlschema
      when 'getcontentlength' then content_length.to_s
      when 'getcontenttype'   then content_type
      when 'getetag'          then etag
      when 'getlastmodified'  then last_modified.httpdate
      else self.get_custom_property(name) if self.respond_to?(:get_custom_property)
      end
    end

    def set_property(name, value)
      case name
      when 'resourcetype'    then self.resource_type = value
      when 'getcontenttype'  then self.content_type = value
      when 'getetag'         then self.etag = value
      when 'getlastmodified' then self.last_modified = Time.httpdate(value)
      else self.set_custom_property(name, value) if self.respond_to?(:set_custom_property)
      end
    rescue Errno::EOPNOTSUPP
      # nothing done
    rescue ArgumentError
      raise HTTPStatus::Conflict
    end

    def remove_property(name)
      raise HTTPStatus::Forbidden if property_names.include?(name)
    end

    def parent
      elements = @path.scan(/[^\/]+/)
      return nil if elements.empty?
      self.class.new('/' + elements[0..-2].to_a.join('/'), @request, @options)
    end

    def descendants
      list = []
      children.each do |child|
        list << child
        list.concat(child.descendants)
      end
      list
    end

  end

end
