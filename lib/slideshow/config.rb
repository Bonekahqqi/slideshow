module Slideshow

class Config
  
  def initialize
    @hash = {}
  end

  def []( key )
    value = @hash[ normalize_key( key ) ]
    if value.nil?
      puts "** Warning: config key '#{key}' undefined (returning nil)"
    end
    
    value
  end

  def load
   
    # load builtin config file @  <gem>/config/slideshow.yml
    config_file = "#{File.dirname( LIB_PATH )}/config/slideshow.yml"

    # run through erb        
    config_txt = File.read( config_file )
    config_txt = ERB.new( config_txt ).result( binding() )
    
    @hash = YAML.load( config_txt )       
  end

  
  def known_textile_extnames
    # returns an array of known file extensions e.g.
    # [ '.textile', '.t' ]
    #
    # using nested key
    # textile:
    #   extnames:  [ .textile, .t ]
    
    @hash[ 'textile' ][ 'extnames' ]
  end

  def known_markdown_extnames
    @hash[ 'markdown' ][ 'extnames' ]    
  end

  def known_extnames
    # ruby check: is it better self. ?? or more confusing
    #  possible conflict only with write access (e.g. prop=) 
    
    known_textile_extnames + known_markdown_extnames
  end


private

  def normalize_key( key )
    #  make key all lower case/downcase (e.g. Content-Type  => content-type)
    #  replace _ with -                 (e.g. gradient_color => gradient-color)
    #  todo: replace space(s) with -  ??
    #  todo: strip leading and trailing spaces - possible use case ??
    
    key.to_s.downcase.tr( '_', '-' )
  end

end # class Config

end # module Slideshow