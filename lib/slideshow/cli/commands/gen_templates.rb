module Slideshow


#### fix:
#  move to attic - no longer used/needed - old code ??
#    just clone template repos or use zip or use ~/.slideshow  folder


class GenTemplates


  include LogUtils::Logging

### fix: remove opts, use config (wrapped!!)

  def initialize( opts, config )
    @opts    = opts
    @config  = config
  end

  attr_reader :opts, :config

  def run
    manifest_name = opts.manifest
    manifest_name = manifest_name.downcase.gsub( '.txt', '' )  # remove (optional) .txt ending
    logger.debug "manifest=#{manifest_name}"
    
    # check for builtin generator manifests
    manifests = installed_generator_manifests.select { |m| m[0] == manifest_name+'.txt.gen' }
    
    if manifests.empty?
      puts "*** error: unknown generator template pack '#{manifest_name}'"
      # todo: list installed manifests
      exit 2
    end
        
    manifestsrc = manifests[0][1]
    pakpath     = opts.output_path

    logger.debug( "manifestsrc=>#{manifestsrc}<, pakpath=>#{pakpath}<" )
    
    Pakman::Copier.new.copy_pak( manifestsrc, pakpath )
  end

private

  def installed_generator_manifests
    # 1) search gem/templates 

    patterns = [
      "#{Slideshow.root}/templates/*.txt.gen"
    ]

    Pakman::Finder.new.find_manifests( patterns )
  end

end # class GenTemplates
end # module Slideshow