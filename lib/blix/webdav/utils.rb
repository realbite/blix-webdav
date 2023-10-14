require 'nokogiri'

class Blix
  class Utils

    def index_page(title,entries, options={})
      d = Nokogiri::HTML::Builder.new do |doc|
        doc.ul {
          for entry in entries do
            doc.li{
              doc.a entry[0], :href=>entry[1]
            }
          end
        }
      d.to_html
    end

  end


end
