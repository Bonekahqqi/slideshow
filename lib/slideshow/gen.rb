module Slideshow

class Gen
  
  def initialize
    @logger = Logger.new(STDOUT)
    @logger.level = Logger::INFO
    @opts   = Opts.new
    @config = Config.new
  end

  attr_reader :logger, :opts, :config
  attr_reader :session      # give helpers/plugins a session-like hash
  
  def headers
    # give access to helpers to opts with a different name
    @opts
  end

  attr_reader :markup_type  # :textile, :markdown
  
  def load_markdown_libs
    # check for available markdown libs/gems
    # try to require each lib and remove any not installed
    @markdown_libs = []

    config.known_markdown_libs.each do |lib|
      begin
        require lib
        @markdown_libs << lib
      rescue LoadError => ex
        logger.debug "Markdown library #{lib} not found. Use gem install #{lib} to install."
      end
    end

    puts "  Found #{@markdown_libs.length} Markdown libraries: #{@markdown_libs.join(', ')}"
  end
 
  
  def markdown_to_html( content )
    # call markdown filter; turn markdown lib name into method_name (mn)
    # eg. rpeg-markdown =>  rpeg_markdown_to_html
    
    puts "  Converting Markdown-text (#{content.length} bytes) to HTML using library '#{@markdown_libs.first}'..."
        
    mn = @markdown_libs.first.downcase.tr( '-', '_' )
    mn = "#{mn}_to_html".to_sym
    send mn, content   # call 1st configured markdown engine e.g. kramdown_to_html( content )
  end

  # uses configured markup processor (textile,markdown) to generate html
  def text_to_html( content )
    content = case @markup_type
      when :markdown
        markdown_to_html( content )
      when :textile
        textile_to_html( content )
    end
    content
  end
 
  def guard_text( text )
    # todo/fix 2: note for Textile we need to differentiate between blocks and inline
    #   thus, to avoid runs - use guard_block (add a leading newline to avoid getting include in block that goes before)
    
    # todo/fix: remove wrap_markup; replace w/ guard_text
    #   why: text might be css, js, not just html      
    wrap_markup( text )
  end
   
  def guard_block( text )
    if markup_type == :textile
      # saveguard with notextile wrapper etc./no further processing needed
      # note: add leading newlines to avoid block-runons
      "\n\n<notextile>\n#{text}\n</notextile>\n"
    else
      text
    end    
  end
  
  def guard_inline( text )
    wrap_markup( text )
  end
  
   
  def wrap_markup( text )    
    if markup_type == :textile
      # saveguard with notextile wrapper etc./no further processing needed
      "<notextile>\n#{text}\n</notextile>"
    else
      text
    end
  end
    
  def cache_dir
    RUBY_PLATFORM =~ /win32/ ? win32_cache_dir : File.join(File.expand_path("~"), ".slideshow")
  end

  def win32_cache_dir
    unless ENV['HOMEDRIVE'] && ENV['HOMEPATH'] && File.exists?(home = ENV['HOMEDRIVE'] + ENV['HOMEPATH'])
      puts "No HOMEDRIVE or HOMEPATH environment variable.  Set one to save a" +
           "local cache of stylesheets for syntax highlighting and more."
      return false
    else
      return File.join(home, '.slideshow')
    end
  end
  
  def config_dir
    unless @config_dir  # first time? calculate config_dir value to "cache"
      
      if opts.config_path
        @config_dir = opts.config_path
      else
        @config_dir = cache_dir
      end
    
      # make sure path exists
      FileUtils.makedirs( @config_dir ) unless File.directory? @config_dir
    end
    
    @config_dir
  end

  def load_manifest_core( path )
    manifest = []
  
    File.open( path ).readlines.each_with_index do |line,i|
      case line
      when /^\s*$/
        # skip empty lines
      when /^\s*#.*$/
        # skip comment lines
      else
        logger.debug "line #{i+1}: #{line.strip}"
        values = line.strip.split( /[ <,+]+/ )
        
        # add source for shortcuts (assumes relative path; if not issue warning/error)
        values << values[0] if values.size == 1
                
        manifest << values
      end      
    end

    manifest
  end

  def load_manifest( path )
        
    filename = path
 
    puts "  Loading template manifest #{filename}..."  
    manifest = load_manifest_core( filename )
    
    # post-processing
    # normalize all source paths (1..-1) /make full path/add template dir

    templatesdir = File.dirname( path )
    logger.debug "templatesdir=#{templatesdir}"

    manifest.each do |values|
      (1..values.size-1).each do |i|
        values[i] = "#{templatesdir}/#{values[i]}"
        logger.debug "  path[#{i}]=>#{values[i]}<"
      end
    end
             
    manifest
  end

  def find_manifests( patterns )
    manifests = []
    
    patterns.each do |pattern|
      pattern.gsub!( '\\', '/')  # normalize path; make sure all path use / only
      logger.debug "Checking #{pattern}"
      Dir.glob( pattern ) do |file|
        logger.debug "  Found manifest: #{file}"
        manifests << [ File.basename( file ), file ]
      end    
    end
    
    manifests
  end

  def installed_generator_manifests
    # 1) search gem/templates 

    builtin_patterns = [
      "#{File.dirname( LIB_PATH )}/templates/*.txt.gen"
    ]

    find_manifests( builtin_patterns )
  end

  def installed_template_manifests
    # 1) search ./templates
    # 2) search config_dir/templates
    # 3) search gem/templates

    builtin_patterns = [
      "#{File.dirname( LIB_PATH )}/templates/*.txt"
    ]
    config_patterns  = [
      "#{config_dir}/templates/*.txt",
      "#{config_dir}/templates/*/*.txt"
    ]
    current_patterns = [
      "templates/*.txt",
      "templates/*/*.txt"
    ]
    
    patterns = []
    patterns += current_patterns  unless LIB_PATH == File.expand_path( 'lib' )  # don't include working dir if we test code from repo (don't include slideshow/templates)
    patterns += config_patterns
    patterns += builtin_patterns
 
    find_manifests( patterns )
  end

  def load_template( path ) 
    puts "  Loading template #{path}..."
    return File.read( path )
  end
  
  def render_template( content, the_binding )
    ERB.new( content ).result( the_binding )
  end

  def load_template_old_delete( name, builtin )
    
    if opts.has_includes? 
      opts.includes.each do |path|
        logger.debug "File.exists? #{path}/#{name}"
        
        if File.exists?( "#{path}/#{name}" ) then          
          puts "Loading custom template #{path}/#{name}..."
          return File.read( "#{path}/#{name}" )
        end
      end       
    end
    
    # fallback load builtin template packaged with gem
    load_builtin_template( builtin )
  end
  
  def with_output_path( dest, output_path )
    dest_full = File.expand_path( dest, output_path )
    logger.debug "dest_full=#{dest_full}"
      
    # make sure dest path exists
    dest_path = File.dirname( dest_full )
    logger.debug "dest_path=#{dest_path}"
    FileUtils.makedirs( dest_path ) unless File.directory? dest_path
    dest_full
  end
  

  def fetch_file( dest, src )
    logger.debug "fetch( dest: #{dest}, src: #{src})"

    uri = URI.parse( src )
  
    # new code: honor proxy env variable HTTP_PROXY
    proxy = ENV['HTTP_PROXY']
    proxy = ENV['http_proxy'] if proxy.nil?   # try possible lower/case env variable (for *nix systems) is this necessary??
    
    if proxy
      proxy = URI.parse( proxy )
      logger.debug "using net http proxy: proxy.host=#{proxy.host}, proxy.port=#{proxy.port}"
      if proxy.user && proxy.password
        logger.debug "  using credentials: proxy.user=#{proxy.user}, proxy.password=****"
      else
        logger.debug "  using no credentials"
      end
    else
      logger.debug "using direct net http access; no proxy configured"
      proxy = OpenStruct.new   # all fields return nil (e.g. proxy.host, etc.)
    end
  
    # same as short-cut: http_proxy.get_respone( uri )
    # use full code for easier changes
    
    http_proxy = Net::HTTP::Proxy( proxy.host, proxy.port, proxy.user, proxy.password )
    http       = http_proxy.new( uri.host, uri.port )
    request    = Net::HTTP::Get.new( uri.request_uri )
    response   = http.request( request )  
  
    unless response.code == '200'   # note: responsoe.code is a string
      msg = "#{response.code} #{response.message}" 
      puts "*** error: #{msg}"
      return   # todo: throw StandardException?
    end

    logger.debug "  content_type: #{response.content_type}, content_length: #{response.content_length}"
  
    # check for content type; use 'wb' for images
    if response.content_type =~ /image/
      logger.debug '  switching to binary'
      flags = 'wb'
    else
      flags = 'w'
    end
  
    File.open( dest, flags ) do |f|
      f.write( response.body )	
    end
  end
  
  
  def fetch_slideshow_templates
    logger.debug "fetch_uri=#{opts.fetch_uri}"
    
    src = opts.fetch_uri
    
    ## check for builtin shortcut (assume no / or \) 
    if src.index( '/' ).nil? && src.index( '\\' ).nil?
      shortcut = src.clone
      src = config.map_fetch_shortcut( src )
      
      if src.nil?
        puts "** Error: No mapping found for fetch shortcut '#{shortcut}'."
        return
      end
      puts "  Mapping fetch shortcut '#{shortcut}' to: #{src}"
    end
    
    
    # src = 'http://github.com/geraldb/slideshow/raw/d98e5b02b87ee66485431b1bee8fb6378297bfe4/code/templates/fullerscreen.txt'
    # src = 'http://github.com/geraldb/sandbox/raw/13d4fec0908fbfcc456b74dfe2f88621614b5244/s5blank/s5blank.txt'
    uri = URI.parse( src )
  
    logger.debug "host: #{uri.host}, port: #{uri.port}, path: #{uri.path}"
  
    dirname  = File.dirname( uri.path )    
    basename = File.basename( uri.path, '.*' ) # e.g. fullerscreen     (without extension)
    filename = File.basename( uri.path )       # e.g. fullerscreen.txt (with extension)

    logger.debug "dirname: #{dirname}"
    logger.debug "basename: #{basename}, filename: #{filename}"

    dlbase = "http://#{uri.host}:#{uri.port}#{dirname}"
    pkgpath = File.expand_path( "#{config_dir}/templates/#{basename}" )
  
    logger.debug "dlpath: #{dlbase}"
    logger.debug "pkgpath: #{pkgpath}"
  
    FileUtils.makedirs( pkgpath ) unless File.directory? pkgpath 
   
    puts "Fetching template package '#{basename}'"
    puts "  : from '#{dlbase}'"
    puts "  : saving to '#{pkgpath}'"
  
    # download manifest
    dest = "#{pkgpath}/#{filename}"

    puts "  Downloading manifest '#{filename}'..."

    fetch_file( dest, src )

    manifest = load_manifest_core( dest )
      
    # download templates listed in manifest
    manifest.each do |values|
      values[1..-1].each do |file|
      
        dest = "#{pkgpath}/#{file}"

        # make sure path exists
        destpath = File.dirname( dest )
        FileUtils.makedirs( destpath ) unless File.directory? destpath
    
        src = "#{dlbase}/#{file}"
    
        puts "  Downloading template '#{file}'..."
        fetch_file( dest, src )
      end
    end   
    puts "Done."  
  end

  def create_slideshow_templates
    
    manifest_name = opts.manifest 
    logger.debug "manifest=#{manifest_name}"
    
    manifests = installed_generator_manifests
    
    # check for builtin generator manifests
    matches = manifests.select { |m| m[0] == manifest_name+".gen" }
    
    if matches.empty?
      puts "*** error: unknown template manifest '#{manifest_name}'"  
      # todo: list installed manifests
      exit 2
    end
        
    manifest = load_manifest( matches[0][1] )

    # expand output path in current dir and make sure output path exists
    outpath = File.expand_path( opts.output_path ) 
    logger.debug "outpath=#{outpath}"
    FileUtils.makedirs( outpath ) unless File.directory? outpath 

    manifest.each do |entry|
      dest   = entry[0]      
      source = entry[1]
                  
      puts "Copying to #{dest} from #{source}..."     
      FileUtils.copy( source, with_output_path( dest, outpath ) )
    end
    
    puts "Done."   
  end
  
  def list_slideshow_templates
    manifests = installed_template_manifests
    
    puts ''
    puts 'Installed templates include:'
    
    manifests.each do |manifest|
      puts "  #{manifest[0]} (#{manifest[1]})"
    end
  end


  def create_slideshow( fn )

    manifest_path_or_name = opts.manifest
    
    # add .txt file extension if missing (for convenience)
    manifest_path_or_name << ".txt"   if File.extname( manifest_path_or_name ).empty?

  
    logger.debug "manifest=#{manifest_path_or_name}"
    
    # check if file exists (if yes use custom template package!) - allows you to override builtin package with same name 
    if File.exists?( manifest_path_or_name )
      manifest = load_manifest( manifest_path_or_name )
    else
      # check for builtin manifests
      manifests = installed_template_manifests
      matches = manifests.select { |m| m[0] == manifest_path_or_name } 

      if matches.empty?
        puts "*** error: unknown template manifest '#{manifest_path_or_name}'"  
        # todo: list installed manifests
        exit 2
      end
        
      manifest = load_manifest( matches[0][1] )
    end
  
    # expand output path in current dir and make sure output path exists
    outpath = File.expand_path( opts.output_path ) 
    logger.debug "outpath=#{outpath}"
    FileUtils.makedirs( outpath ) unless File.directory? outpath 

    dirname  = File.dirname( fn )    
    basename = File.basename( fn, '.*' )
    extname  = File.extname( fn )
    logger.debug "dirname=#{dirname}, basename=#{basename}, extname=#{extname}"

    # change working dir to sourcefile dir
    # todo: add a -c option to commandline? to let you set cwd?
    
    newcwd  = File.expand_path( dirname )
    oldcwd  = File.expand_path( Dir.pwd )
    
    unless newcwd == oldcwd then
      logger.debug "oldcwd=#{oldcwd}"
      logger.debug "newcwd=#{newcwd}"
      Dir.chdir newcwd
    end  

    puts "Preparing slideshow '#{basename}'..."
                
  if extname.empty? then
    extname  = ".textile"   # default to .textile 
    
    config.known_extnames.each do |e|
       logger.debug "File.exists? #{dirname}/#{basename}#{e}"
       if File.exists?( "#{dirname}/#{basename}#{e}" ) then         
          extname = e
          logger.debug "extname=#{extname}"
          break
       end
    end     
  end

  if config.known_markdown_extnames.include?( extname )
    @markup_type = :markdown
  else
    @markup_type = :textile
  end
  
  # shared variables for templates (binding)
  @content_for = {}  # reset content_for hash

  @name        = basename
  @extname     = extname

  @headers     = @opts  # deprecate/remove: use headers method in template

  @session     = {}  # reset session hash for plugins/helpers

  inname  =  "#{dirname}/#{basename}#{extname}"

  logger.debug "inname=#{inname}"
    
  content = File.read( inname )

  # run text filters
  
  unless @markdown_libs.first == "pandoc-ruby"
    config.text_filters.each do |filter|
      mn = filter.tr( '-', '_' ).to_sym  # construct method name (mn)
      content = send( mn, content )   # call filter e.g.  include_helper_hack( content )  
    end
  end

  # convert light-weight markup to hypertext
logger.debug (content) 
  content = text_to_html( content )
  # post-processing (skip if using pandoc-ruby)
  
  if @markdown_libs.first == "pandoc-ruby"
    @content = content
    @slides = content
  else

    slide_counter = 0

    slides       = []
    slide_source = ""
     
    # wrap h1's in slide divs; note: use just <h1 since some processors add ids e.g. <h1 id='x'>
    content.each_line do |line|
       if line.include?( '<h1' ) || line.include?( '<!-- _S9SLIDE_' )  then
          if slide_counter > 0 then   # found start of new slide (and, thus, end of last slide)
            slides   << slide_source  # add slide to slide stack
            slide_source = ""         # reset slide source buffer
          end
          slide_counter += 1
       end
       slide_source  << line
    end
  
    if slide_counter > 0 then
      slides   << slide_source     # add slide to slide stack
      slide_source = ""            # reset slide source buffer 
    end

    ## split slide source into header (optional) and content/body
    ## plus check for (css style) classes

    slides2 = []
    slides.each do |slide_source|
      slide = Slide.new

      ## check for css style classes    
      from = 0
      while (pos = slide_source.index( /<!-- _S9(SLIDE|STYLE)_(.*?)-->/m, from ))
        logger.debug "  adding css classes from pi #{$1.downcase}: #{$2.strip}"

        if slide.classes.nil?
          slide.classes = $2.strip
        else
          slide.classes << " #{$2.strip}"
        end
      
        from = Regexp.last_match.end(0)
      end
       
      if slide_source =~ /^\s*(<h1.*?>.*?<\/h\d>)\s*(.*)/m  # try to cut off header using non-greedy .+? pattern; tip test regex online at rubular.com
        slide.header  = $1
        slide.content = ($2 ? $2 : "")
        logger.debug "  adding slide with header:\n#{slide.header}"
      else
        slide.content = slide_source
        logger.debug "  adding slide with *no* header:\n#{slide.content}"
      end
      slides2 << slide
    end

     # for convenience create a string w/ all in-one-html
     #  no need to wrap slides in divs etc.
   
     content2 = ""
     slides2.each do |slide|         
        content2 << slide.to_classic_html
     end
   
    # make content2 and slide2 available to erb template
    # -- todo: cleanup variable names and use attr_readers for content and slide
  
    @slides   = slides2     # strutured content 
    @content  = content2   # content all-in-one

  end

  manifest.each do |entry|
    outname = entry[0]
    if outname.include? '__file__' # process
      outname = outname.gsub( '__file__', basename )
      puts "Preparing #{outname}..."

      out = File.new( with_output_path( outname, outpath ), "w+" )

      out << render_template( load_template( entry[1] ), binding )
      
      if entry.size > 2 # more than one source file? assume header and footer with content added inbetween
        out << content2 
        out << render_template( load_template( entry[2] ), binding )
      end

      out.flush
      out.close

    else # just copy verbatim if target/dest has no __file__ in name
      dest   = entry[0]      
      source = entry[1]
            
      puts "Copying to #{dest} from #{source}..."     
      FileUtils.copy( source, with_output_path( dest, outpath ) )
    end
  end

  puts "Done."
end

def load_plugins
    
  patterns = []
  patterns << "#{config_dir}/lib/**/*.rb"
  patterns << 'lib/**/*.rb' unless LIB_PATH == File.expand_path( 'lib' )  # don't include lib if we are in repo (don't include slideshow/lib)
  
  patterns.each do |pattern|
    pattern.gsub!( '\\', '/')  # normalize path; make sure all path use / only
    Dir.glob( pattern ) do |plugin|
      begin
        puts "Loading plugins in '#{plugin}'..."
        require( plugin )
      rescue Exception => e
        puts "** error: failed loading plugins in '#{plugin}': #{e}"
      end
    end
  end
end

def run( args )

  opt=OptionParser.new do |cmd|
    
    cmd.banner = "Usage: slideshow [options] name"
    
    cmd.on( '-o', '--output PATH', 'Output Path' ) { |s| opts.put( 'output', s ) }

    cmd.on( '-g', '--generate',  'Generate Slide Show Templates (Using Built-In S6 Pack)' ) { opts.put( 'generate', true ) }
    
    cmd.on( "-t", "--template MANIFEST", "Template Manifest" ) do |t|
      # todo: do some checks on passed in template argument
      opts.put( 'manifest', t )
    end

    # ?? opts.on( "-s", "--style STYLE", "Select Stylesheet" ) { |s| $options[:style]=s }
    # ?? opts.on( "--version", "Show version" )  {}
        
    # ?? cmd.on( '-i', '--include PATH', 'Load Path' ) { |s| opts.put( 'include', s ) }

    cmd.on( '-f', '--fetch URI', 'Fetch Templates' ) do |u|
      opts.put( 'fetch_uri', u )
    end
    
    cmd.on( '-c', '--config PATH', 'Configuration Path (default is ~/.slideshow)' ) do |p|
      opts.put( 'config_path', p )
    end
    
    cmd.on( '-l', '--list', 'List Installed Templates' ) { opts.put( 'list', true ) }

    # todo: find different letter for debug trace switch (use v for version?)
    cmd.on( "-v", "--verbose", "Show debug trace" )  do
       logger.datetime_format = "%H:%H:%S"
       logger.level = Logger::DEBUG      
    end
 
    cmd.on_tail( "-h", "--help", "Show this message" ) do
         puts 
         puts "Slide Show (S9) is a free web alternative to PowerPoint or KeyNote in Ruby"
         puts
         puts cmd.help
         puts
         puts "Examples:"
         puts "  slideshow microformats"
         puts "  slideshow microformats.textile         # Process slides using Textile"
         puts "  slideshow microformats.text            # Process slides using Markdown"
         puts "  slideshow -o slides microformats       # Output slideshow to slides folder"
         puts
         puts "More examles:"
         puts "  slideshow -g                           # Generate slide show templates using built-in S6 pack"
         puts
         puts "  slideshow -l                           # List installed slide show templates"
         puts "  slideshow -f s5blank                   # Fetch (install) S5 blank starter template from internet"
         puts "  slideshow -t s5blank microformats      # Use your own slide show templates (e.g. s5blank)"
         puts
         puts "Further information:"
         puts "  http://slideshow.rubyforge.org" 
         exit
    end
  end

  opt.parse!( args )
  
  config.load

  puts "Slide Show (S9) Version: #{VERSION} on Ruby #{RUBY_VERSION} (#{RUBY_RELEASE_DATE}) [#{RUBY_PLATFORM}]"

  if opts.list?
    list_slideshow_templates
  elsif opts.generate?
    create_slideshow_templates
  elsif opts.fetch?
    fetch_slideshow_templates
  else
    load_markdown_libs
    load_plugins  # check for optional plugins/extension in ./lib folder
    
    args.each { |fn| create_slideshow( fn ) }
  end
end

end # class Gen


end # module Slideshow