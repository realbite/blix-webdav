module Blix
  module WebDAV

    module Routes

      OPTIONS = {:accept=>:*, :force=>:raw, :extension=>false}

      module ClassMethods
        attr_reader :dav_root, :dav_prefix, :dav_options

        def webdav_path
          File.join(@dav_prefix ||'/','*path')
        end

        def webdav_routes(options={})
          @dav_options = options

          @dav_prefix = @dav_options[:prefix] || '/'
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

      def webdav_params(params={})
        @dav_params = self.class.dav_options.merge(params)
      end

      def _params
        @dav_params || self.class.dav_options
      end

      def get_protocol
        Protocol.new(path_params[:path], self, _params)
      end

      private

      def self.included(mod)
        mod.extend ClassMethods
      end
    end # Routes


  end
end
