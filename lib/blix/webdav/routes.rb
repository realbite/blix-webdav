module Blix
  module WebDAV

    module Routes

      OPTIONS = {:accept=>:*, :force=>:raw, :extension=>false}

      module ClassMethods
        attr_reader :dav_root, :dav_prefix, :dav_options

        def webdav_root(val)
          @dav_root = val
        end

        def webdav_options(val)
          @dav_options = val
        end

        def webdav_path
          File.join(@dav_prefix ||'/','*path')
        end

        def webdav_define_routes(prefix=nil)

          @dav_prefix = prefix || '/'
          @dav_prefix = '/' + @dav_prefix unless @dav_prefix[0]=='/'

          route 'OPTIONS',  webdav_path , OPTIONS do
            protocol = get_protocol
            protocol.handle_options
            protocol.respond
          end

          route 'HEAD',  webdav_path , OPTIONS do
            protocol = get_protocol
            protocol.handle_head
            protocol.respond
          end

          route 'GET',  webdav_path , OPTIONS do
            protocol = get_protocol
            protocol.handle_get
            protocol.respond
          end

          route 'PUT',  webdav_path , OPTIONS do
            protocol = get_protocol
            protocol.handle_put
            protocol.respond
          end

          route 'POST',  webdav_path , OPTIONS do
            protocol = get_protocol
            protocol.handle_post
            protocol.respond
          end

          route 'DELETE',  webdav_path , OPTIONS do
            protocol = get_protocol
            protocol.handle_delete
            protocol.respond
          end

          route 'MKCOL',  webdav_path , OPTIONS do
            protocol = get_protocol
            protocol.handle_mkcol
            protocol.respond
          end

          route 'COPY',  webdav_path , OPTIONS do
            protocol = get_protocol
            protocol.handle_copy
            protocol.respond
          end

          route 'MOVE',  webdav_path , OPTIONS do
            protocol = get_protocol
            protocol.handle_move
            protocol.respond
          end

          route 'PROPFIND',  webdav_path , OPTIONS do
            protocol = get_protocol
            protocol.handle_propfind
            protocol.respond
          end

          route 'PROPPATCH',  webdav_path , OPTIONS do
            protocol = get_protocol
            protocol.handle_proppatch
            protocol.respond
          end

          route 'LOCK',  webdav_path , OPTIONS do
            protocol = get_protocol
            protocol.handle_lock
            protocol.respond
          end

          route 'UNLOCK',  webdav_path , OPTIONS do
            protocol = get_protocol
            protocol.handle_unlock
            protocol.respond
          end
        end

      end # ClassMethods

      def webdav_root
        self.class.dav_root || raise( 'you must specify the webdav_root')
      end

      def webdav_options
        self.class.dav_options || {}
      end

      def get_protocol
        resource_path = path_params[:path]
        prefix = Protocol.compute_path_prefix(path, resource_path)
        resource = Blix::WebDAV::FileResource.new(resource_path,req,webdav_options.merge(:root=>webdav_root))
        Protocol.new(resource, self, webdav_options.merge(:prefix=>prefix))
      end

      private

      def self.included(mod)
        mod.extend ClassMethods
      end
    end # Routes


  end
end
