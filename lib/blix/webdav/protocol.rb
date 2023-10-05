require 'nokogiri'

module Blix
  module WebDAV

    # class to do the heavy lifting work in implementing the WebDAV
    # protocol. It stores the relevant status/headers/body to enable
    # the controller to set up the response correctly.
    class Protocol

      include HTTPStatus

      attr_reader :resource, :headers, :content, :status, :request

      def initialize(resource, controller,options={})
        @options    = options
        @controller = controller          # blix rest controller
        @resource = resource              # the webdav resource object.
        @request  = @controller&.req       # the rack request
        @status = 200                     # set the response status
        @headers = {}                     # set response headers
        @content = String.new             # set the response body.
        @root    = ensure_path options[:prefix]
      end

      def ensure_path(str)
        str = str.to_s
        str = str.chomp('/')
        str = '/' + str if str[0] != '/'
        str = str + '/' if str[-1] != '/'
        str
      end

      def handle_options
          headers["Allow"] = 'OPTIONS,HEAD,GET,PUT,POST,DELETE,PROPFIND,PROPPATCH,MKCOL,COPY,MOVE'
          headers["Dav"]   = "1"

          if resource.lockable?
            headers["Allow"] << ",LOCK,UNLOCK"
            headers["Dav"]   << ",2"
          end

          headers["Ms-Author-Via"] = "DAV"
          self
      end

      def resource_class
        @options[:resource_class] || FileResource
      end

      def handle_head
        raise NotFound if not resource.exist?
        headers['Etag'] = resource.etag
        headers['Content-Type'] = resource.content_type
        headers['Content-Length'] = resource.content_length.to_s  # FIXME
        headers['Last-Modified'] = resource.last_modified.httpdate
        self
      end

      def handle_get
        raise NotFound if not resource.exist?
        headers['Etag'] = resource.etag
        headers['Content-Type'] = resource.content_type
        headers['Content-Length'] = resource.content_length.to_s
        headers['Last-Modified'] = resource.last_modified.httpdate
        map_exceptions do
          @content = resource.get
          if resource.collection?
            headers['Content-Length'] = @content.bytesize.to_s
          end
        end
        self
      end

      def handle_put
        raise Forbidden if resource.collection?
        locktoken = request_locktoken('LOCK_TOKEN')
        locktoken ||= request_locktoken('IF')
        locketag = request_locketag('IF')
        raise PreconditionFailed if locketag && locketag != resource.etag
        raise Locked if resource.locked?(locktoken, locketag)

        map_exceptions do
          resource.put
        end
        set_status  Created
        headers['Location'] = url_for(resource.path)
        self
      end

      def handle_post
        map_exceptions do
          resource.post
        end
      end

      def handle_delete
        raise NotFound if not resource.exist?
        raise Locked if resource.locked?(request_locktoken('LOCK_TOKEN'))

        delete_recursive(resource, errors = [])

        if errors.empty?
          set_status NoContent
        else
          multistatus do |xml|
            response_errors(xml, errors)
          end
        end
      end

      def handle_mkcol
        # Reject message bodies - RFC2518:8.3.1
        body = request.body.read(8)
        raise UnsupportedMediaType if !body.nil? && body.length > 0

        map_exceptions do
          resource.make_collection
        end
        set_status = Created
      end

      def handle_copy
        raise NotFound if not resource.exist?
        # Source Lock Check
        locktoken = request_locktoken('LOCK_TOKEN')
        locktoken ||= request_locktoken('IF')
        raise Locked if resource.locked?(locktoken) && !overwrite

        dest_uri = URI.parse(env['HTTP_DESTINATION'])
        destination = parse_destination(dest_uri)

        raise BadGateway if dest_uri.host and dest_uri.host != request.host
        raise Forbidden  if destination == resource.path

        dest = resource_class.new(destination, request, resource.options)
        raise PreconditionFailed if dest.exist? && !overwrite
        # Destination Lock Check
        locktoken = request_locktoken('LOCK_TOKEN')
        locktoken ||= request_locktoken('IF')
        raise Locked if dest.locked?(locktoken)

        dest = dest.child(resource.name) if dest.collection?

        dest_existed = dest.exist?

        copy_recursive(resource, dest, depth, errors = [])

        if errors.empty?
          set_status = dest_existed ? NoContent : Created
        else
          multistatus do |xml|
            response_errors(xml, errors)
          end
        end
      rescue URI::InvalidURIError => e
        raise BadRequest #.new(e.message)
      end

      #-------------------------------------------------------------------------


      def handle_move
        raise NotFound if not resource.exist?
        raise Locked if resource.locked?(request_locktoken('LOCK_TOKEN'))

        dest_uri = URI.parse(env['HTTP_DESTINATION'])
        destination = parse_destination(dest_uri)

        raise BadGateway if dest_uri.host and dest_uri.host != request.host
        raise Forbidden if destination == resource.path

        dest = resource_class.new(destination, request, resource.options)
        raise PreconditionFailed if dest.exist? && !overwrite

        dest_existed = dest.exist?
        dest = dest.child(resource.name) if dest.collection?

        raise Conflict if depth <= 1

        copy_recursive(resource, dest, depth, errors = [])
        delete_recursive(resource, errors)

        if errors.empty?
          set_status  dest_existed ? NoContent : Created
        else
          multistatus do |xml|
            response_errors(xml, errors)
          end
        end
      rescue URI::InvalidURIError => e
        raise BadRequest #.new(e.message)  #FIXME
      end


      #-------------------------------------------------------------------------
      # return xml for the properties.


      def handle_propfind
        raise NotFound if not resource.exist?
        if not request_match("/d:propfind/d:allprop").empty?
          nodes = all_prop_nodes
        else
          nodes = request_match("/d:propfind/d:prop/*")
          nodes = all_prop_nodes if nodes.empty?
        end

        nodes.each do |n|
          # Don't allow empty namespace declarations
          # See litmus props test 3
          raise BadRequest if n.namespace.nil? && n.namespace_definitions.empty?

          # Set a blank namespace if one is included in the request
          # See litmus props test 16
          # <propfind xmlns="DAV:"><prop><nonamespace xmlns=""/></prop></propfind>
          if n.namespace.nil?
            nd = n.namespace_definitions.first
            if nd.prefix.nil? && nd.href.empty?
              n.add_namespace(nil, '')
            end
          end
        end

        multistatus do |xml|
          for resource in find_resources
            #resource.path.gsub!(/\/\//, '/')
            xml.response do
              xml.href resource_url( resource)
              propstats xml, get_properties(resource, nodes)
            end
          end
        end
      end



      #-------------------------------------------------------------------------

      def handle_proppatch
        raise NotFound if not resource.exist?
        locktoken = request_locktoken('LOCK_TOKEN')
        locktoken ||= request_locktoken('IF')
        raise Locked if resource.locked?(locktoken)

        nodes = request_match("/d:propertyupdate[d:remove/d:prop/* or d:set/d:prop/*]//d:prop/*")

        # Set a blank namespace if one is included in the request
        # See litmus props test 15
        # <propertyupdate xmlns="DAV:"><set>
        #   <prop><nonamespace xmlns="">randomvalue</nonamespace></prop>
        # </set></propertyupdate>
        nodes.each do |n|
          nd = n.namespace_definitions.first
          if !nd.nil? && nd.prefix.nil? && nd.href.empty?
            n.add_namespace(nil, '')
          end
        end

        multistatus do |xml|
          for resource in find_resources
            xml.response do
              xml.href resource_url(resource)
              propstats xml, set_properties(resource, nodes)
            end
          end
        end
      end

      #=========================================================================
      def handle_lock
        raise MethodNotAllowed unless resource.lockable?
        raise NotFound if not resource.exist?

        timeout = request_timeout
        if timeout.nil? || timeout.zero?
          timeout = 60
        end

        if request_document.content.empty?
          refresh_lock timeout
        else
          create_lock timeout
        end
      end

      def handle_unlock
        raise MethodNotAllowed unless resource.lockable?

        locktoken = request_locktoken('LOCK_TOKEN')
        raise BadRequest if locktoken.nil?

        set_status = resource.unlock(locktoken) ? NoContent : Forbidden
      end

      def set_status(status)
        @status = status.to_i
      end

      def logit
        if @options[:logger]
          Blix::Rest.logger.info "================================================================"
          Blix::Rest.logger.info "REQUST PATH==> #{resource.path}"
          Blix::Rest.logger.info "REQUST METHOD==> #{@controller.verb}"
          Blix::Rest.logger.info "REQUST HEADERS==> #{env.filter{|k| k[0,5]=='HTTP_'}.inspect}"
          Blix::Rest.logger.info "REQUEST DOC==>#{@request_document&.to_xml}"
          Blix::Rest.logger.info "RESPONSE HEADERS =>#{headers}"
          Blix::Rest.logger.info "RESPONSE STATUS =>#{status}"
          Blix::Rest.logger.info "RESPONSE BODY =>#{content}"
          Blix::Rest.logger.info "================================================================"
        end
      end

      # set up the blix response.
      def respond
        logit
        @controller.add_headers headers
        @controller.set_status  status
        content
      end

      def render_xml
        doc = Nokogiri::XML::Builder.new(:encoding => "UTF-8") do |xml|
          yield xml if block_given?
        end
        #doc.remove_namespaces!
        @content = doc.to_xml
        headers["Content-Type"]   = 'application/xml; charset=utf-8'
        headers["Content-Length"] = @content.bytesize.to_s
      end

      def multistatus
        render_xml do |xml|
          xml.multistatus('xmlns' => "DAV:") do
            yield xml if block_given?
          end
        end
        set_status MultiStatus
      end

      def response_errors(xml, errors)
        for path, status in errors
          xml.response do
            xml.href url_for(path)
            xml.status "#{request.env['HTTP_VERSION']} #{status.status_line}"
          end
        end
      end

      def url_for(path)
        @controller.url_for(url_escape File.join(@root,path))
      end

      def resource_url(r)
        @controller.url_for(url_escape File.join(@root,r.path))
      end

      def request_timeout
        timeout = request.env['HTTP_TIMEOUT']
        return if timeout.nil? || timeout.empty?

        timeout = timeout.split /,\s*/
        timeout.reject! {|t| t !~ /^Second-/}
        timeout.first.sub('Second-', '').to_i
      end

      def request_locktoken(header)
        token = request.env["HTTP_#{header}"]
        return if token.nil? || token.empty?
        token.scan /<(opaquelocktoken:.+?)>/
        return $1
      end

      def request_locketag(header)
        etag = request.env["HTTP_#{header}"]
        return if etag.nil? || etag.empty?
        etag.scan /\[(.+?)\]/
        return $1
      end

      #private



        def env
          @request.env
        end

        # def host
        #   @request.host
        # end
        #
        # def resource_class
        #   @options[:resource_class]
        # end

        def depth
          case env['HTTP_DEPTH']
          when '0' then 0
          when '1' then 1
          else 100
          end
        end

        def overwrite
          env['HTTP_OVERWRITE'].to_s.upcase != 'F'
        end

        def find_resources
          case env['HTTP_DEPTH']
          when '0'
            [resource]
          when '1'
            [resource] + resource.children
          else
            [resource] + resource.descendants
          end
        end

        def delete_recursive(res, errors)
          for child in res.children
            delete_recursive(child, errors)
          end

          begin
            map_exceptions { res.delete } if errors.empty?
          rescue Status
            errors << [res.path, $!]
          end
        end

        def copy_recursive(res, dest, depth, errors)
          map_exceptions do
            if dest.exist?
              if overwrite
                delete_recursive(dest, errors)
              else
                raise PreconditionFailed
              end
            end
            res.copy(dest)
          end
        rescue Status
          errors << [res.path, $!]
        else
          if depth > 0
            for child in res.children
              dest_child = dest.child(child.name)
              copy_recursive(child, dest_child, depth - 1, errors)
            end
          end
        end

        def map_exceptions
          yield
        rescue
          case $!
          when URI::InvalidURIError then raise BadRequest
          when Errno::EACCES then raise Forbidden
          when Errno::ENOENT then raise Conflict
          when Errno::EEXIST then raise Conflict
          when Errno::ENOSPC then raise InsufficientStorage
          else
            raise
          end
        end

        def request_document

          @request_document ||= if (body = request.body.read).empty?
            Nokogiri::XML::Document.new
          else
            Nokogiri::XML(body, &:strict)
          end
          @request_document
        rescue Nokogiri::XML::SyntaxError, RuntimeError # Nokogiri raise RuntimeError :-(
          raise BadRequest
        end

        def request_match(pattern)
          request_document.xpath(pattern, 'd' => 'DAV:')
        end

        def qualified_node_name(node)
          node.namespace.nil? || (node.namespace.href=='DAV:') || node.namespace.prefix.nil? ? node.name : "#{node.namespace.prefix}:#{node.name}"
        end

        def qualified_property_name(node)
          node.namespace.nil? || node.namespace.href == 'DAV:' ? node.name : "{#{node.namespace.href}}#{node.name}"
        end

        def all_prop_nodes
          resource.property_names.map do |n|
            node = Nokogiri::XML::Element.new(n, request_document)
            node.add_namespace(nil, 'DAV:')
            node
          end
        end

        def get_properties(resource, nodes)
          stats = Hash.new { |h, k| h[k] = [] }
          for node in nodes
            begin
              map_exceptions do
                stats[OK] << [node, resource.get_property(qualified_property_name(node))]
              end
            rescue Status
              stats[$!] << node
            end
          end
          stats
        end

        def set_properties(resource, nodes)
          stats = Hash.new { |h, k| h[k] = [] }
          for node in nodes
            begin
              map_exceptions do
                stats[OK] << [node, resource.set_property(qualified_property_name(node), node.text)]
              end
            rescue Status
              stats[$!] << node
            end
          end
          stats
        end

        def propstats(xml, stats)
          return if stats.empty?
          for status, props in stats
            xml.propstat do
              xml.prop do
                for node, value in props
                  qnn = qualified_node_name(node)

                  if value.is_a?(Nokogiri::XML::Node)
                      xml.send(qnn.to_sym) do
                      rexml_convert(xml, value)
                    end
                  else
                    attrs = {}
                    unless node.namespace.nil?
                      if node.namespace.prefix.nil?
                        attrs = { 'xmlns' => node.namespace.href }
                      elsif node.namespace.href == 'DAV:'
                        #
                      else
                        attrs = { "xmlns:#{node.namespace.prefix}" => node.namespace.href }
                      end
                    end

                    xml.send(qnn.to_sym, value, attrs)
                  end
                end
              end
              xml.status "#{request.env['HTTP_VERSION']} #{status.status_line}"
            end
          end
        end


        def create_lock(timeout)
          lockscope = request_match("/d:lockinfo/d:lockscope/d:*").first
          lockscope = lockscope.name if lockscope
          locktype = request_match("/d:lockinfo/d:locktype/d:*").first
          locktype = locktype.name if locktype
          owner = request_match("/d:lockinfo/d:owner/d:href").first
          owner ||= request_match("/d:lockinfo/d:owner").first
          owner = owner.text if owner
          locktoken = "opaquelocktoken:" + sprintf('%x-%x-%s', Time.now.to_i, Time.now.sec, resource.etag)

          raise Locked if resource.other_owner_locked?(locktoken, owner)

          # Quick & Dirty - FIXME: Lock should become a new Class
          # and this dirty parameter passing refactored.
          unless resource.lock(locktoken, timeout, lockscope, locktype, owner)
            raise Forbidden
          end

          headers['Lock-Token'] = locktoken

          render_lockdiscovery locktoken, lockscope, locktype, timeout, owner
        end

        def refresh_lock(timeout)
          locktoken = request_locktoken('IF')
          raise BadRequest if locktoken.nil?

          timeout, lockscope, locktype, owner = resource.lock(locktoken, timeout)
          unless lockscope && locktype && timeout
            raise Forbidden
          end

          render_lockdiscovery locktoken, lockscope, locktype, timeout, owner
        end

        # FIXME add multiple locks support
        def render_lockdiscovery(locktoken, lockscope, locktype, timeout, owner)
          render_xml do |xml|
            xml.prop('xmlns' => "DAV:") do
              xml.lockdiscovery do
                render_lock(xml, locktoken, lockscope, locktype, timeout, owner)
              end
            end
          end
        end

        def render_lock(xml, locktoken, lockscope, locktype, timeout, owner)
          xml.activelock do
            xml.lockscope { xml.tag! lockscope }
            xml.locktype { xml.tag! locktype }
            xml.depth 'Infinity'
            if owner
              xml.owner { xml.href owner }
            end
            xml.timeout "Second-#{timeout}"
            xml.locktoken do
              xml.href locktoken
            end
          end
        end

        def rexml_convert(xml, element)
          if element.elements.empty?
            if element.text
              xml.send(element.name.to_sym, element.text, element.attributes)
            else
              xml.send(element.name.to_sym, element.attributes)
            end
          else
            xml.send(element.name.to_sym, element.attributes) do
              element.elements.each do |child|
                rexml_convert(xml, child)
              end
            end
          end
        end

        def parse_destination dest_uri
          destination = url_unescape(dest_uri.path)
          puts "AAAAAAAAAAA:#{destination}/#{@root}"
          destination[@root.length-1..-1]
          # destination.slice!(1..@root.length) if @root.length > 0
          # destination =
          # destination
        end

        def url_format_for_response(resource)
          ret = url_escape(resource.path)
          if resource.collection? and ret[-1,1] != '/'
            ret += '/'
          end
          ret
        end

        def url_escape(s)
          @_p ||= URI::Parser.new
          @_p.escape(s)
        end

        def url_unescape(s)
          #URI.decode(s) #.force_valid_encoding
          @_p ||= URI::Parser.new
          @_p.unescape(s)
        end

        def self.compute_path_prefix(path, suffix)
          path = path.chomp('/') + '/'
          suffix = suffix.chomp('/') + '/'
          suffix = '/' + suffix unless suffix[0] == '/'
          path = '/' + path unless path[0] == '/'
          diff = [path.length-suffix.length,1].max
          path[0, diff]
        end
    end
  end
end
