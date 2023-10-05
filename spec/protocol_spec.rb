require 'spec_helper'


module Blix::WebDAV

  describe Protocol do

    before do
      @save = Blix::Rest.path_root
      @p = Protocol.new(nil,nil)
    end

    after do
      Blix::Rest.set_path_root @save
    end

    it "should render multistatus xml" do
      @p.multistatus
      puts @p.content
    end

    it "should parse a destination path" do
      dest_uri = URI.parse "http://localhost/xxx/yyy/zzz"
      Blix::Rest.set_path_root ''

      p = Protocol.new(nil,nil)
      expect(p.parse_destination dest_uri).to eq '/xxx/yyy/zzz'
      p = Protocol.new(nil,nil,:prefix=>'/xxx')
      expect(p.parse_destination dest_uri).to eq '/yyy/zzz'
      p = Protocol.new(nil,nil,:prefix=>'/xxx/')
      expect(p.parse_destination dest_uri).to eq '/yyy/zzz'
      p = Protocol.new(nil,nil,:prefix=>'/xxx/yyy')
      expect(p.parse_destination dest_uri).to eq '/zzz'
      p = Protocol.new(nil,nil,:prefix=>'/xxx/yyy/')
      expect(p.parse_destination dest_uri).to eq '/zzz'

      Blix::Rest.set_path_root '/xxx'
      p = Protocol.new(nil,nil)
      expect(p.parse_destination dest_uri).to eq '/yyy/zzz'
      p = Protocol.new(nil,nil,:prefix=>'/yyy')
      expect(p.parse_destination dest_uri).to eq '/zzz'
      p = Protocol.new(nil,nil,:prefix=>'/yyy/')
      expect(p.parse_destination dest_uri).to eq '/zzz'
      p = Protocol.new(nil,nil,:prefix=>'/yyy/zzz')
      expect(p.parse_destination dest_uri).to eq '/'
      p = Protocol.new(nil,nil,:prefix=>'/yyy/zzz/')
      expect(p.parse_destination dest_uri).to eq '/'
    end

    it "should compare paths" do
      expect(Protocol.compute_path_prefix('/', '/') ).to eq '/'

      expect(Protocol.compute_path_prefix('/xxx', '/xxx') ).to eq '/'
      expect(Protocol.compute_path_prefix('/xxx', '/xxx/') ).to eq '/'
      expect(Protocol.compute_path_prefix('/xxx/', '/xxx') ).to eq '/'
      expect(Protocol.compute_path_prefix('/xxx/', '/xxx/') ).to eq '/'

      expect(Protocol.compute_path_prefix('/yyy/zzz', '/') ).to eq '/yyy/zzz'
      expect(Protocol.compute_path_prefix('/yyy/zzz/xxx', '/xxx') ).to eq '/yyy/zzz'
      expect(Protocol.compute_path_prefix('/yyy/zzz/xxx', '/xxx/') ).to eq '/yyy/zzz'
      expect(Protocol.compute_path_prefix('/yyy/zzz/xxx/', '/xxx') ).to eq '/yyy/zzz'
      expect(Protocol.compute_path_prefix('/yyy/zzz/xxx/', '/xxx/') ).to eq '/yyy/zzz'
    end

  end

end
